import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {Readable, Writable} from "node:stream";
import {beforeEach, describe, test} from "node:test";
import {HttpsError} from "firebase-functions/https";
import * as yauzl from "yauzl";
import {
  BucketLike,
  CallableRequestLike,
  CallerAuth,
  computeFingerprint,
  DocumentSnapshotLike,
  FirestoreLike,
  getGalleryDownload,
  GalleryDeps,
  GalleryProgress,
  handleGalleryDownloadRequest,
  MESSAGES,
  progressSender,
  ProgressStream,
  sanitizeEntryName,
  selectPhotos,
  SignedUrlConfig,
  SLOW_BUILD_MS,
  SourceFileLike,
  totalSize,
  ZIP_FORMAT_VERSION,
  ZipObjectLike,
  zipFileName,
} from "./gallery";

// ---------------------------------------------------------------------------
// In-memory fakes.
// ---------------------------------------------------------------------------

class FakeFirestore implements FirestoreLike {
  readonly docs = new Map<string, Record<string, unknown>>();

  doc(path: string): {get(): Promise<DocumentSnapshotLike>} {
    return {
      get: async () => {
        const data = this.docs.get(path);
        return {exists: data !== undefined, data: () => data};
      },
    };
  }
}

interface StoredObject {
  data: Buffer;
  generation: string;
  updated: string;
  contentType?: string;
  metadata: Record<string, string>;
}

type ReadFault = "error" | "truncate";

/**
 * Bucket fake. Like Cloud Storage, an upload only creates (or replaces) the
 * object when the write stream finishes; a destroyed stream leaves nothing.
 */
class FakeBucket implements BucketLike {
  readonly objects = new Map<string, StoredObject>();
  readonly readFaults = new Map<string, ReadFault>();
  readonly signedUrlConfigs: SignedUrlConfig[] = [];
  getFilesError: Error | undefined;
  writeStreamsOpened = 0;
  lastWriteStream: Writable | undefined;
  uploadsFinished = 0;
  readStreamsOpened = 0;
  private openReads = 0;
  maxOpenReads = 0;
  private nextGeneration = 1000;

  put(name: string, data: string | Buffer, extra: Partial<StoredObject> = {}): void {
    this.objects.set(name, {
      data: Buffer.from(data),
      generation: String(this.nextGeneration++),
      updated: "2026-09-02T10:00:00.000Z",
      metadata: {},
      ...extra,
    });
  }

  async getFiles(query: {prefix: string}): Promise<[SourceFileLike[]]> {
    if (this.getFilesError) throw this.getFilesError;
    const names = [...this.objects.keys()].filter((n) => n.startsWith(query.prefix));
    return [names.map((name) => this.sourceFile(name))];
  }

  private sourceFile(name: string): SourceFileLike {
    const object = this.objects.get(name)!;
    return {
      name,
      metadata: {
        generation: object.generation,
        size: String(object.data.length),
        updated: object.updated,
      },
      createReadStream: () => this.readStream(name),
    };
  }

  private readStream(name: string): Readable {
    this.readStreamsOpened++;
    this.openReads++;
    this.maxOpenReads = Math.max(this.maxOpenReads, this.openReads);
    let open = true;
    const closed = (): void => {
      if (open) this.openReads--;
      open = false;
    };
    const data = this.objects.get(name)!.data;
    const fault = this.readFaults.get(name);
    let sent = false;
    const stream = new Readable({
      read() {
        if (!sent) {
          sent = true;
          this.push(fault ? data.subarray(0, Math.floor(data.length / 2)) : data);
        } else if (fault === "error") {
          this.destroy(new Error(`simulated read failure: ${name}`));
        } else {
          this.push(null);
        }
      },
    });
    stream.on("end", closed);
    stream.on("close", closed);
    return stream;
  }

  file(name: string): ZipObjectLike {
    return {
      exists: async () => [this.objects.has(name)],
      getMetadata: async () => {
        const object = this.objects.get(name);
        if (!object) throw Object.assign(new Error("Not found"), {code: 404});
        return [{metadata: {...object.metadata}}];
      },
      createWriteStream: (options) => {
        this.writeStreamsOpened++;
        const chunks: Buffer[] = [];
        return (this.lastWriteStream = new Writable({
          write(chunk: Buffer, _encoding, callback) {
            chunks.push(chunk);
            callback();
          },
          final: (callback) => {
            this.put(name, Buffer.concat(chunks), {
              contentType: options.metadata.contentType,
              metadata: {...options.metadata.metadata},
            });
            this.uploadsFinished++;
            callback();
          },
        }));
      },
      getSignedUrl: async (config) => {
        this.signedUrlConfigs.push(config);
        return [`https://storage.example/${name}?signature=${this.signedUrlConfigs.length}`];
      },
    };
  }
}

/**
 * onCall's response as getGalleryDownload sees it. Records every chunk it's
 * handed, even after the abort, so a test can tell that none was sent then.
 */
class FakeStream implements ProgressStream {
  readonly chunks: GalleryProgress[] = [];
  readonly controller = new AbortController();
  /** "reject" and "throw" fail every chunk, as a broken connection would. */
  mode: "resolve" | "reject" | "throw" = "resolve";
  onChunk: ((chunk: GalleryProgress) => void) | undefined;

  get signal(): AbortSignal {
    return this.controller.signal;
  }

  sendChunk(chunk: GalleryProgress): Promise<boolean> {
    this.chunks.push(chunk);
    this.onChunk?.(chunk);
    if (this.mode === "throw") throw new Error("simulated response gone");
    if (this.mode === "reject") return Promise.reject(new Error("simulated write failure"));
    return Promise.resolve(!this.signal.aborted);
  }

  get photosDone(): number[] {
    return this.chunks.map((chunk) => chunk.photosDone);
  }
}

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

const NOW = new Date("2026-10-16T12:00:00.000Z");
const UID = "customer-uid";
const BOOKING_ID = "b1";
const ZIP_NAME = "gallery-zips/b1.zip";
const GUEST_UID = "guest-uid";
const GUEST_EMAIL = "harper@example.com";
const GUEST_TOKEN = {email: GUEST_EMAIL, email_verified: true};

let db: FakeFirestore;
let bucket: FakeBucket;
let deps: GalleryDeps;
/** deps.log's calls, as [level, message]. */
let logLines: [level: string, message: string][];

function addBooking(id: string, fields: Record<string, unknown> = {}): void {
  db.docs.set(`bookings/${id}`, {
    uid: UID,
    email: "parent@example.com",
    packageName: "Premium",
    date: "2026-09-01",
    time: "10:00",
    status: "paid",
    photosReady: true,
    ...fields,
  });
}

/** An ad hoc session as the admin pages write it: no uid, shared by email. */
function addAdHocSession(id: string, fields: Record<string, unknown> = {}): void {
  db.docs.set(`bookings/${id}`, {
    status: "adhoc",
    name: "The Harper family",
    email: GUEST_EMAIL,
    date: "2026-09-01",
    photosReady: true,
    createdAt: NOW,
    createdBy: "admin-uid",
    ...fields,
  });
}

/** Calls as UID; with no arguments, for BOOKING_ID. */
function call(...args: [data?: unknown]) {
  return getGalleryDownload(deps, {uid: UID}, args.length > 0 ? args[0] : {bookingId: BOOKING_ID});
}

/** Calls as GUEST_UID with these token claims, for BOOKING_ID. */
function callAsGuest(token: CallerAuth["token"]) {
  return getGalleryDownload(deps, {uid: GUEST_UID, token}, {bookingId: BOOKING_ID});
}

/** Calls as UID for BOOKING_ID, sending progress to `stream`. */
function callStreaming(stream: FakeStream) {
  return getGalleryDownload(deps, {uid: UID}, {bookingId: BOOKING_ID}, stream);
}

/** Makes deps.now move on a second each time it's read, so no progress is throttled. */
function tick(): void {
  let time = NOW.getTime();
  deps.now = () => new Date((time += 1000));
}

/** The log lines whose message matches `pattern`. */
function logLinesMatching(pattern: RegExp): [level: string, message: string][] {
  return logLines.filter(([, message]) => pattern.test(message));
}

async function assertHttpsError(
  promise: Promise<unknown>,
  code: string,
  message?: string,
): Promise<void> {
  await assert.rejects(promise, (error: unknown) => {
    assert.ok(error instanceof HttpsError, `expected HttpsError, got ${String(error)}`);
    assert.equal(error.code, code);
    if (message !== undefined) assert.equal(error.message, message);
    return true;
  });
}

/** Reads a zip back with yauzl, which also rejects unsafe entry names. */
function readZip(buffer: Buffer): Promise<Map<string, {data: Buffer; method: number}>> {
  return new Promise((resolve, reject) => {
    yauzl.fromBuffer(buffer, {lazyEntries: true}, (error, zipfile) => {
      if (error) return reject(error);
      const entries = new Map<string, {data: Buffer; method: number}>();
      zipfile.on("error", reject);
      zipfile.on("end", () => resolve(entries));
      zipfile.on("entry", (entry: yauzl.Entry) => {
        zipfile.openReadStream(entry, (streamError, stream) => {
          if (streamError) return reject(streamError);
          const chunks: Buffer[] = [];
          stream.on("data", (chunk: Buffer) => chunks.push(chunk));
          stream.on("error", reject);
          stream.on("end", () => {
            entries.set(entry.fileName, {
              data: Buffer.concat(chunks),
              method: entry.compressionMethod,
            });
            zipfile.readEntry();
          });
        });
      });
      zipfile.readEntry();
    });
  });
}

async function zipEntries(): Promise<Map<string, string>> {
  const object = bucket.objects.get(ZIP_NAME);
  assert.ok(object, "zip was not uploaded");
  const entries = await readZip(object.data);
  return new Map([...entries].map(([name, entry]) => [name, entry.data.toString()]));
}

/** The documented fingerprint, computed independently of the code under test. */
function expectedFingerprint(prefix: string, names: string[]): string {
  const hash = createHash("sha256");
  hash.update(`${ZIP_FORMAT_VERSION}\n`);
  for (const name of [...names].sort()) {
    const object = bucket.objects.get(prefix + name)!;
    hash.update(`${prefix + name}\n${object.generation}\n${object.data.length}\n`);
  }
  return hash.digest("hex");
}

beforeEach(() => {
  db = new FakeFirestore();
  bucket = new FakeBucket();
  logLines = [];
  deps = {db, bucket, now: () => NOW, log: (level, message) => logLines.push([level, message])};
});

// ---------------------------------------------------------------------------
// Tests.
// ---------------------------------------------------------------------------

describe("getGalleryDownload: access checks", {timeout: 10_000}, () => {
  test("rejects a missing or malformed bookingId", async () => {
    for (const data of [
      undefined,
      null,
      "b1",
      {},
      {bookingId: 42},
      {bookingId: ""},
      {bookingId: "a/b"},
      {bookingId: "../b1"},
      {bookingId: "b1 "},
      {bookingId: "x".repeat(129)},
    ]) {
      await assertHttpsError(call(data), "invalid-argument", MESSAGES.invalidArgument);
    }
    // The longest allowed ID passes validation (and then isn't found).
    await assertHttpsError(call({bookingId: "x".repeat(128)}), "not-found");
  });

  test("a missing booking and another user's booking look the same", async () => {
    addBooking("someone-elses", {uid: "another-uid"});
    bucket.put("galleries/someone-elses/a.jpg", "photo");

    await assertHttpsError(call({bookingId: "missing"}), "not-found", MESSAGES.notFound);
    await assertHttpsError(call({bookingId: "someone-elses"}), "not-found", MESSAGES.notFound);
    assert.equal(bucket.writeStreamsOpened, 0);
    assert.equal(bucket.signedUrlConfigs.length, 0);
  });

  test("a booking without a uid is not found", async () => {
    addBooking(BOOKING_ID, {uid: undefined});
    await assertHttpsError(call(), "not-found");
  });

  test("an unpaid booking is refused", async () => {
    bucket.put("galleries/b1/a.jpg", "photo");
    for (const status of ["pending", "cancelled", "refunded", undefined, 42, "paid later"]) {
      addBooking(BOOKING_ID, {status});
      await assertHttpsError(call(), "failed-precondition", MESSAGES.notPaid);
    }
  });

  test("a hand-typed status like ' Paid ' counts as paid, as in the app", async () => {
    bucket.put("galleries/b1/a.jpg", "photo");
    for (const status of ["PAID", " Paid "]) {
      addBooking(BOOKING_ID, {status});
      const result = await call();
      assert.equal(result.photoCount, 1);
    }
  });

  test("photos not marked ready are refused", async () => {
    bucket.put("galleries/b1/a.jpg", "photo");
    for (const photosReady of [undefined, false, "true", 1]) {
      addBooking(BOOKING_ID, {photosReady});
      await assertHttpsError(call(), "failed-precondition", MESSAGES.notReady);
    }
    assert.equal(bucket.writeStreamsOpened, 0);
  });

  test("a ready booking with no photo files is refused", async () => {
    addBooking(BOOKING_ID);
    await assertHttpsError(call(), "failed-precondition", MESSAGES.notReady);

    // Placeholders and hidden files don't count as photos.
    bucket.put("galleries/b1/", "");
    bucket.put("galleries/b1/sub/", "");
    bucket.put("galleries/b1/.DS_Store", "junk");
    bucket.put("galleries/b1/sub/._IMG_1.jpg", "junk");
    // Neither do another booking's photos that share the prefix.
    bucket.put("galleries/b10/a.jpg", "photo");
    await assertHttpsError(call(), "failed-precondition", MESSAGES.notReady);
    assert.equal(bucket.writeStreamsOpened, 0);
  });
});

describe("getGalleryDownload: ad hoc sessions shared by email", {timeout: 10_000}, () => {
  test("a guest signed in with the session's verified email can download", async () => {
    addAdHocSession(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "photo");
    // The session's email is saved lowercase; Google may report capitals.
    for (const email of [GUEST_EMAIL, "Harper@Example.COM"]) {
      const result = await callAsGuest({email, email_verified: true});
      assert.equal(result.photoCount, 1);
    }
  });

  test("another verified email is not found", async () => {
    addAdHocSession(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "photo");
    await assertHttpsError(
      callAsGuest({email: "someone@example.com", email_verified: true}),
      "not-found",
      MESSAGES.notFound,
    );
    // A session email typed with capitals in the console matches no one, as
    // in firestore.rules.
    addAdHocSession(BOOKING_ID, {email: "Harper@example.com"});
    await assertHttpsError(callAsGuest(GUEST_TOKEN), "not-found", MESSAGES.notFound);
    assert.equal(bucket.writeStreamsOpened, 0);
    assert.equal(bucket.signedUrlConfigs.length, 0);
  });

  test("the session's email is not found until Google has verified it", async () => {
    addAdHocSession(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "photo");
    for (const email_verified of [false, undefined, "true", 1]) {
      await assertHttpsError(
        callAsGuest({email: GUEST_EMAIL, email_verified}),
        "not-found",
        MESSAGES.notFound,
      );
    }
    assert.equal(bucket.writeStreamsOpened, 0);
  });

  test("an email never opens a paid booking", async () => {
    // Only the uid opens a customer's booking, even with the same email on it.
    addBooking(BOOKING_ID, {email: GUEST_EMAIL});
    bucket.put("galleries/b1/a.jpg", "photo");
    await assertHttpsError(callAsGuest(GUEST_TOKEN), "not-found", MESSAGES.notFound);
    // Nor does a status that is only nearly "adhoc".
    for (const status of ["Adhoc", " adhoc", "ADHOC", undefined]) {
      addAdHocSession(BOOKING_ID, {status});
      await assertHttpsError(callAsGuest(GUEST_TOKEN), "not-found", MESSAGES.notFound);
    }
    assert.equal(bucket.writeStreamsOpened, 0);
  });

  test("a missing or non-string token email is not found", async () => {
    addAdHocSession(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "photo");
    for (const token of [
      undefined,
      {},
      {email_verified: true},
      {email: null, email_verified: true},
      {email: 42, email_verified: true},
      {email: [GUEST_EMAIL], email_verified: true},
    ]) {
      await assertHttpsError(callAsGuest(token), "not-found", MESSAGES.notFound);
    }
  });

  test("a session email that isn't a string is not found", async () => {
    bucket.put("galleries/b1/a.jpg", "photo");
    for (const email of [undefined, null, 42, [GUEST_EMAIL], {toLowerCase: () => GUEST_EMAIL}]) {
      addAdHocSession(BOOKING_ID, {email});
      await assertHttpsError(callAsGuest(GUEST_TOKEN), "not-found", MESSAGES.notFound);
    }
  });

  test("access is checked before readiness, so IDs can't be probed", async () => {
    addAdHocSession(BOOKING_ID, {photosReady: false});
    bucket.put("galleries/b1/a.jpg", "photo");
    await assertHttpsError(
      callAsGuest({email: "someone@example.com", email_verified: true}),
      "not-found",
      MESSAGES.notFound,
    );
    await assertHttpsError(callAsGuest(GUEST_TOKEN), "failed-precondition", MESSAGES.notReady);
  });

  test("an ad hoc session is deliverable without payment", async () => {
    bucket.put("galleries/b1/a.jpg", "photo");
    addAdHocSession(BOOKING_ID);
    assert.equal((await callAsGuest(GUEST_TOKEN)).photoCount, 1);
    // Its uid, if one was typed in, opens it too, and the status check
    // forgives a hand-typed " Adhoc " as it does " Paid ". The app doesn't:
    // Booking.fromMap reads only an exact "adhoc", so it never offers this
    // download, and access by email needs the exact value (canDownload).
    for (const status of ["adhoc", " Adhoc "]) {
      addAdHocSession(BOOKING_ID, {uid: UID, status});
      assert.equal((await call()).photoCount, 1);
    }
  });
});

describe("getGalleryDownload: zip", {timeout: 10_000}, () => {
  test("zips every photo, skipping placeholders and hidden files", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/IMG_0001.jpg", "first photo");
    bucket.put("galleries/b1/Edited/IMG_0002.jpg", "second photo");
    bucket.put("galleries/b1/empty.jpg", "");
    bucket.put("galleries/b1/", "");
    bucket.put("galleries/b1/Edited/", "");
    bucket.put("galleries/b1/.DS_Store", "junk");
    bucket.put("galleries/b1/Edited/.DS_Store", "junk");
    bucket.put("galleries/b10/other.jpg", "another booking");
    bucket.put("_admin/gallery/public.jpg", "carousel");

    const result = await call();

    assert.equal(result.photoCount, 3);
    assert.deepEqual(
      await zipEntries(),
      new Map([
        ["Edited/IMG_0002.jpg", "second photo"],
        ["IMG_0001.jpg", "first photo"],
        ["empty.jpg", ""],
      ]),
    );
    const zip = bucket.objects.get(ZIP_NAME)!;
    assert.equal(zip.contentType, "application/zip");
    assert.deepEqual(zip.metadata, {
      sourceFingerprint: expectedFingerprint("galleries/b1/", [
        "IMG_0001.jpg",
        "Edited/IMG_0002.jpg",
        "empty.jpg",
      ]),
    });
    assert.equal(bucket.uploadsFinished, 1);
  });

  // Sending progress mustn't change how the photos stream.
  for (const streaming of [false, true]) {
    const name = "stores entries uncompressed and streams one photo at a time";
    test(streaming ? `${name}, while sending progress` : name, async () => {
      addBooking(BOOKING_ID);
      for (let i = 1; i <= 5; i++) bucket.put(`galleries/b1/IMG_${i}.jpg`, `photo ${i} `.repeat(1000));
      const stream = new FakeStream();
      tick();

      await (streaming ? callStreaming(stream) : call());

      const entries = await readZip(bucket.objects.get(ZIP_NAME)!.data);
      assert.equal(entries.size, 5);
      for (const entry of entries.values()) assert.equal(entry.method, 0); // 0 = stored
      assert.equal(bucket.readStreamsOpened, 5);
      assert.equal(bucket.maxOpenReads, 1);
      assert.deepEqual(stream.photosDone, streaming ? [0, 1, 2, 3, 4, 5] : []);
    });
  }

  test("reuses the cached zip while the photos are unchanged", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "a");
    bucket.put("galleries/b1/b.jpg", "b");

    const first = await call();
    const zipGeneration = bucket.objects.get(ZIP_NAME)!.generation;
    const second = await call();

    assert.equal(bucket.writeStreamsOpened, 1);
    assert.equal(bucket.uploadsFinished, 1);
    assert.equal(bucket.readStreamsOpened, 2); // Only the first call read photos.
    assert.equal(bucket.objects.get(ZIP_NAME)!.generation, zipGeneration);
    assert.equal(second.photoCount, 2);
    assert.notEqual(second.url, first.url); // A fresh signed URL each time.
  });

  test("rebuilds the zip when a photo is replaced, added or deleted", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "a");
    bucket.put("galleries/b1/b.jpg", "b");
    await call();
    const firstFingerprint = bucket.objects.get(ZIP_NAME)!.metadata.sourceFingerprint;

    // Same name and size, new generation.
    bucket.put("galleries/b1/a.jpg", "A");
    await call();
    assert.equal(bucket.uploadsFinished, 2);
    assert.notEqual(bucket.objects.get(ZIP_NAME)!.metadata.sourceFingerprint, firstFingerprint);
    assert.deepEqual(await zipEntries(), new Map([["a.jpg", "A"], ["b.jpg", "b"]]));

    bucket.put("galleries/b1/c.jpg", "c");
    const added = await call();
    assert.equal(bucket.uploadsFinished, 3);
    assert.equal(added.photoCount, 3);

    bucket.objects.delete("galleries/b1/a.jpg");
    const deleted = await call();
    assert.equal(bucket.uploadsFinished, 4);
    assert.equal(deleted.photoCount, 2);
    assert.deepEqual(await zipEntries(), new Map([["b.jpg", "b"], ["c.jpg", "c"]]));
    assert.equal(
      bucket.objects.get(ZIP_NAME)!.metadata.sourceFingerprint,
      expectedFingerprint("galleries/b1/", ["b.jpg", "c.jpg"]),
    );
  });

  test("rebuilds a cached zip that has no fingerprint", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "a");
    bucket.put(ZIP_NAME, "not really a zip");

    await call();

    assert.equal(bucket.uploadsFinished, 1);
    assert.deepEqual(await zipEntries(), new Map([["a.jpg", "a"]]));
  });

  test("sanitizes entry names so nothing escapes the extraction folder", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/../../etc/passwd.jpg", "1");
    bucket.put("galleries/b1/sub\\..\\..\\win.jpg", "2");
    bucket.put("galleries/b1//double-slash.jpg", "3");
    bucket.put("galleries/b1/./dot/x.jpg", "4");
    bucket.put("galleries/b1/C:\\boot.jpg", "5");
    bucket.put("galleries/b1/x.jpg", "6");

    const result = await call();

    assert.equal(result.photoCount, 6);
    const names = [...(await zipEntries()).keys()];
    for (const name of names) {
      assert.ok(!name.startsWith("/"), name);
      assert.ok(!name.includes("\\"), name);
      assert.ok(!name.split("/").includes(".."), name);
    }
    assert.deepEqual(names.sort(), [
      "C_/boot.jpg",
      "dot/x.jpg",
      "double-slash.jpg",
      "etc/passwd.jpg",
      "sub/win.jpg",
      "x.jpg",
    ].sort());
  });

  test("a failing photo download fails the request and leaves no new zip", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "aaaaaaaa");
    bucket.put("galleries/b1/b.jpg", "bbbbbbbb");
    bucket.put("galleries/b1/c.jpg", "cccccccc");
    bucket.put(ZIP_NAME, "stale zip", {metadata: {sourceFingerprint: "stale"}});
    const stale = bucket.objects.get(ZIP_NAME);
    bucket.readFaults.set("galleries/b1/b.jpg", "error");

    await assert.rejects(call(), /simulated read failure: galleries\/b1\/b\.jpg/);

    assert.equal(bucket.writeStreamsOpened, 1);
    // The upload was aborted with the error, not ended.
    assert.equal(bucket.lastWriteStream?.destroyed, true);
    assert.match(String(bucket.lastWriteStream?.errored), /simulated read failure/);
    assert.equal(bucket.uploadsFinished, 0);
    assert.equal(bucket.objects.get(ZIP_NAME), stale);
    assert.equal(bucket.readStreamsOpened, 2); // c.jpg was never opened.
    assert.equal(bucket.signedUrlConfigs.length, 0);
  });

  test("a photo shorter than its listed size fails the request", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "aaaaaaaa");
    bucket.readFaults.set("galleries/b1/a.jpg", "truncate");

    await assert.rejects(call(), /unexpected number of bytes/);
    assert.match(String(bucket.lastWriteStream?.errored), /unexpected number of bytes/);
    assert.equal(bucket.uploadsFinished, 0);
    assert.equal(bucket.objects.has(ZIP_NAME), false);
  });

  test("an upload failure fails the request", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "a");
    bucket.file = (name) => ({
      ...FakeBucket.prototype.file.call(bucket, name),
      createWriteStream: () =>
        new Writable({write: (_chunk, _encoding, callback) => callback(new Error("upload failed"))}),
    });

    await assert.rejects(call(), /upload failed/);
    assert.equal(bucket.objects.has(ZIP_NAME), false);
  });
});

describe("getGalleryDownload: progress", {timeout: 10_000}, () => {
  const T = 12; // The three photos' bytes.

  beforeEach(() => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "aaa");
    bucket.put("galleries/b1/b.jpg", "bbbb");
    bucket.put("galleries/b1/c.jpg", "ccccc");
  });

  test("sends a chunk as each photo is opened, then one once the zip is read", async () => {
    const stream = new FakeStream();
    tick();

    const result = await callStreaming(stream);

    assert.deepEqual(stream.chunks[0], {stage: "zipping", photosDone: 0, photoCount: 3, totalBytes: T});
    assert.deepEqual(stream.photosDone, [0, 1, 2, 3]);
    for (const chunk of stream.chunks) {
      assert.deepEqual(chunk, {...stream.chunks[0], photosDone: chunk.photosDone});
    }
    assert.equal(result.totalBytes, T);
    assert.equal(bucket.uploadsFinished, 1);
  });

  test("sends at most one chunk per 500 ms, but always the first and the last", async () => {
    const stream = new FakeStream();

    await callStreaming(stream); // deps.now stands still.

    assert.deepEqual(stream.photosDone, [0, 3]);
  });

  test("sends nothing for a zip that's already built", async () => {
    await call();
    const stream = new FakeStream();

    const result = await callStreaming(stream);

    assert.equal(bucket.uploadsFinished, 1);
    assert.deepEqual(stream.chunks, []);
    assert.equal(result.totalBytes, T);
  });

  test("sends nothing for an error before the build", async () => {
    addBooking(BOOKING_ID, {photosReady: false});
    const stream = new FakeStream();

    await assertHttpsError(callStreaming(stream), "failed-precondition", MESSAGES.notReady);

    assert.deepEqual(stream.chunks, []);
  });

  test("a caller who leaves mid-build doesn't stop it", async () => {
    const stream = new FakeStream();
    stream.onChunk = (chunk) => {
      if (chunk.photosDone >= 1) stream.controller.abort();
    };
    tick();

    const result = await callStreaming(stream);

    assert.match(result.url, /^https:\/\/storage\.example\/gallery-zips\/b1\.zip/);
    assert.equal(bucket.uploadsFinished, 1);
    assert.equal((await zipEntries()).size, 3);
    assert.deepEqual(stream.photosDone, [0, 1]); // Nothing after the abort.
    assert.equal(logLines.length, 2);
    const [[level, left], [, built]] = logLines;
    assert.equal(level, "info");
    assert.match(left, /caller left/);
    assert.match(left, new RegExp(`uid ${UID}`));
    assert.match(left, /1 of 3 photos in/);
    assert.doesNotMatch(left, /@/);
    assert.match(built, /built the zip/);
  });

  test("a caller gone before the build still gets it built and cached", async () => {
    const stream = new FakeStream();
    stream.controller.abort();
    tick();

    await callStreaming(stream);

    assert.equal(bucket.uploadsFinished, 1);
    assert.deepEqual(stream.chunks, []);
    assert.equal(logLinesMatching(/left/).length, 1);
    assert.match(logLinesMatching(/left/)[0][1], /0 of 3 photos in/);
    await call();
    assert.equal(bucket.uploadsFinished, 1); // The next call found it cached.
  });

  // node:test fails the file on an unhandled rejection, so these also show
  // there isn't one.
  for (const mode of ["reject", "throw"] as const) {
    test(`a sendChunk that fails (${mode}) doesn't fail the download`, async () => {
      const stream = new FakeStream();
      stream.mode = mode;
      tick();

      const result = await callStreaming(stream);

      assert.equal(result.photoCount, 3);
      assert.deepEqual(stream.photosDone, [0, 1, 2, 3]);
      assert.equal(bucket.uploadsFinished, 1);
    });
  }

  test("a failing build never sends the last chunk", async () => {
    bucket.readFaults.set("galleries/b1/b.jpg", "error");
    const stream = new FakeStream();
    tick();

    await assert.rejects(callStreaming(stream), /simulated read failure: galleries\/b1\/b\.jpg/);

    assert.deepEqual(stream.photosDone, [0, 1]);
    assert.ok(stream.chunks.every((chunk) => chunk.photosDone < chunk.photoCount));
    assert.equal(bucket.uploadsFinished, 0);
    assert.deepEqual(logLines, []);
  });
});

describe("getGalleryDownload: signed URL", {timeout: 10_000}, () => {
  test("returns a v4 read URL that expires in 60 minutes and downloads as an attachment", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "a");

    const result = await call();

    const expires = new Date(NOW.getTime() + 60 * 60 * 1000);
    assert.deepEqual(bucket.signedUrlConfigs, [
      {
        version: "v4",
        action: "read",
        expires,
        responseDisposition: 'attachment; filename="brooke-stapleton-photography-2026-09-01.zip"',
      },
    ]);
    assert.deepEqual(result, {
      url: "https://storage.example/gallery-zips/b1.zip?signature=1",
      photoCount: 1,
      expiresAt: "2026-10-16T13:00:00.000Z",
      totalBytes: 1, // "a"
    });
  });

  test("names the download after the booking ID when there is no date", async () => {
    addBooking(BOOKING_ID, {date: undefined});
    bucket.put("galleries/b1/a.jpg", "a");

    await call();

    assert.equal(
      bucket.signedUrlConfigs[0].responseDisposition,
      'attachment; filename="brooke-stapleton-photography-b1.zip"',
    );
  });

  test("zipFileName keeps the header safe", () => {
    assert.equal(zipFileName("2026-09-01", "b1"), "brooke-stapleton-photography-2026-09-01.zip");
    assert.equal(zipFileName('2026/09/01"; x=y', "b1"), "brooke-stapleton-photography-2026-09-01-x-y.zip");
    assert.equal(zipFileName("\r\n", "b1"), "brooke-stapleton-photography-b1.zip");
    assert.equal(zipFileName('"""', "b1"), "brooke-stapleton-photography-b1.zip");
    assert.equal(zipFileName(20260901, "b1"), "brooke-stapleton-photography-b1.zip");
  });
});

describe("handleGalleryDownloadRequest", {timeout: 10_000}, () => {
  let logged: unknown[];
  let loggedMessages: string[];
  // deps.log records into logLines.
  const handle = (request: CallableRequestLike, stream?: FakeStream) =>
    handleGalleryDownloadRequest(
      {
        ...deps,
        logError: (message, error) => {
          loggedMessages.push(message);
          logged.push(error);
        },
      },
      request,
      stream,
    );

  beforeEach(() => {
    logged = [];
    loggedMessages = [];
  });

  test("requires sign-in", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "a");
    for (const auth of [undefined, null, {uid: ""}]) {
      await assertHttpsError(
        handle({auth, data: {bookingId: BOOKING_ID}}),
        "unauthenticated",
        MESSAGES.unauthenticated,
      );
    }
  });

  test("returns the download for the signed-in owner", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "a");
    const result = await handle({auth: {uid: UID}, data: {bookingId: BOOKING_ID}});
    assert.equal(result.photoCount, 1);
  });

  test("passes the token's email claims to the access check", async () => {
    addAdHocSession(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "a");
    const result = await handle({
      auth: {uid: GUEST_UID, token: GUEST_TOKEN},
      data: {bookingId: BOOKING_ID},
    });
    assert.equal(result.photoCount, 1);
    await assertHttpsError(
      handle({auth: {uid: GUEST_UID}, data: {bookingId: BOOKING_ID}}),
      "not-found",
    );
  });

  test("passes HttpsErrors through without logging", async () => {
    await assertHttpsError(handle({auth: {uid: UID}, data: {bookingId: "missing"}}), "not-found");
    assert.deepEqual(logged, []);
  });

  test("turns unexpected errors into a logged 'internal' error", async () => {
    addBooking(BOOKING_ID);
    bucket.getFilesError = new Error("storage is down");
    await assertHttpsError(
      handle({auth: {uid: UID}, data: {bookingId: BOOKING_ID}}),
      "internal",
      MESSAGES.internal,
    );
    assert.deepEqual(logged, [bucket.getFilesError]);
  });

  test("logs the uid, never the email", async () => {
    addAdHocSession(BOOKING_ID);
    bucket.getFilesError = new Error("storage is down");
    await assertHttpsError(
      handle({auth: {uid: GUEST_UID, token: GUEST_TOKEN}, data: {bookingId: BOOKING_ID}}),
      "internal",
    );
    assert.equal(loggedMessages.length, 1);
    assert.match(loggedMessages[0], new RegExp(GUEST_UID));
    assert.doesNotMatch(loggedMessages[0], /harper|@/i);
  });

  test("streams progress and logs the build with the uid, never the email", async () => {
    addAdHocSession(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "aaa");
    bucket.put("galleries/b1/b.jpg", "bbbb");
    const stream = new FakeStream();
    tick();

    await handle({auth: {uid: GUEST_UID, token: GUEST_TOKEN}, data: {bookingId: BOOKING_ID}}, stream);
    // onCall aborts the signal when a normal response ends, too.
    stream.controller.abort();

    assert.deepEqual(stream.photosDone, [0, 1, 2]);
    assert.equal(logLines.length, 1); // Never "left".
    const [level, message] = logLines[0];
    assert.equal(level, "info");
    assert.match(message, /built the zip for booking b1 \(uid guest-uid\): 2 photos, 7 bytes, in \d+ ms/);
    assert.doesNotMatch(message, /harper|@/i);
  });

  test("logs a build of 500 s or more as a warning", async () => {
    addBooking(BOOKING_ID);
    bucket.put("galleries/b1/a.jpg", "a");
    bucket.put("galleries/b1/b.jpg", "b");
    let time = NOW.getTime();
    deps.now = () => new Date(time);
    const stream = new FakeStream();
    stream.onChunk = () => {
      time = NOW.getTime() + SLOW_BUILD_MS; // The clock jumps during the build.
    };

    await handle({auth: {uid: UID}, data: {bookingId: BOOKING_ID}}, stream);

    assert.deepEqual(logLines, [
      [
        "warning",
        `getGalleryDownloadUrl built the zip for booking b1 (uid ${UID}): 2 photos, 2 bytes, in 500000 ms`,
      ],
    ]);
  });
});

describe("helpers", () => {
  test("progressSender sends the first and last chunks, and others at most every 500 ms", () => {
    const stream = new FakeStream();
    let time = 0;
    const send = progressSender(stream, () => new Date(time));
    const progress = (photosDone: number): GalleryProgress => ({
      stage: "zipping",
      photosDone,
      photoCount: 10,
      totalBytes: 1000,
    });

    send(progress(0)); // The first.
    time = 100;
    send(progress(1)); // Too soon.
    time = 600;
    send(progress(2));
    time = 700;
    send(progress(10)); // The last, however soon.
    assert.deepEqual(stream.photosDone, [0, 2, 10]);

    stream.controller.abort();
    time = 2000;
    send(progress(10));
    assert.deepEqual(stream.photosDone, [0, 2, 10]);
  });

  test("totalSize adds up the listed sizes, or is null if one wasn't listed", () => {
    assert.equal(totalSize([{size: 3}, {size: 4}, {size: 0}]), 7);
    assert.equal(totalSize([{size: 3}, {size: undefined}, {size: 4}]), null);
  });

  test("MESSAGES use typographic apostrophes", () => {
    for (const message of Object.values(MESSAGES)) assert.ok(!message.includes("'"), message);
  });

  test("sanitizeEntryName", () => {
    assert.equal(sanitizeEntryName("IMG_0001.jpg"), "IMG_0001.jpg");
    assert.equal(sanitizeEntryName("a/b/c.jpg"), "a/b/c.jpg");
    assert.equal(sanitizeEntryName("/abs.jpg"), "abs.jpg");
    assert.equal(sanitizeEntryName("../../x.jpg"), "x.jpg");
    assert.equal(sanitizeEntryName("a/../b.jpg"), "a/b.jpg");
    assert.equal(sanitizeEntryName("a\\..\\b.jpg"), "a/b.jpg");
    assert.equal(sanitizeEntryName("./a//b.jpg"), "a/b.jpg");
    assert.equal(sanitizeEntryName('C:what?"*<>|.jpg'), "C_what______.jpg");
    assert.equal(sanitizeEntryName("tab\there.jpg"), "tab_here.jpg");
    assert.equal(sanitizeEntryName(".."), "photo");
  });

  test("selectPhotos makes entry names unique, case-insensitively", () => {
    const file = (name: string): SourceFileLike => ({
      name,
      metadata: {generation: "1", size: "1"},
      createReadStream: () => Readable.from([]),
    });
    const photos = selectPhotos(
      [file("p/a.jpg"), file("p//a.jpg"), file("p/A.JPG"), file("p/../a.jpg"), file("p/README")],
      "p/",
    );
    assert.deepEqual(
      photos.map((photo) => [photo.name, photo.entryName]),
      [
        ["p/../a.jpg", "a.jpg"],
        ["p//a.jpg", "a (2).jpg"],
        ["p/A.JPG", "A (3).JPG"],
        ["p/README", "README"],
        ["p/a.jpg", "a (4).jpg"],
      ],
    );
  });

  test("computeFingerprint ignores order and tracks name, generation and size", () => {
    const base = [
      {name: "g/a.jpg", generation: "1", size: 10},
      {name: "g/b.jpg", generation: "2", size: 20},
    ];
    const fingerprint = computeFingerprint(base);
    assert.match(fingerprint, /^[0-9a-f]{64}$/);
    assert.equal(computeFingerprint([...base].reverse()), fingerprint);
    assert.notEqual(computeFingerprint([{...base[0], generation: "3"}, base[1]]), fingerprint);
    assert.notEqual(computeFingerprint([{...base[0], size: 11}, base[1]]), fingerprint);
    assert.notEqual(computeFingerprint([{...base[0], name: "g/c.jpg"}, base[1]]), fingerprint);
    assert.notEqual(computeFingerprint([base[0]]), fingerprint);
  });
});
