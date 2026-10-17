import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {Readable, Writable} from "node:stream";
import {beforeEach, describe, test} from "node:test";
import {HttpsError} from "firebase-functions/https";
import * as yauzl from "yauzl";
import {
  BucketLike,
  computeFingerprint,
  DocumentSnapshotLike,
  FirestoreLike,
  getGalleryDownload,
  GalleryDeps,
  handleGalleryDownloadRequest,
  MESSAGES,
  sanitizeEntryName,
  selectPhotos,
  SignedUrlConfig,
  SourceFileLike,
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

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

const NOW = new Date("2026-10-16T12:00:00.000Z");
const UID = "customer-uid";
const BOOKING_ID = "b1";
const ZIP_NAME = "gallery-zips/b1.zip";

let db: FakeFirestore;
let bucket: FakeBucket;
let deps: GalleryDeps;

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

/** Calls as UID; with no arguments, for BOOKING_ID. */
function call(...args: [data?: unknown]) {
  return getGalleryDownload(deps, UID, args.length > 0 ? args[0] : {bookingId: BOOKING_ID});
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
  deps = {db, bucket, now: () => NOW};
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

  test("stores entries uncompressed and streams one photo at a time", async () => {
    addBooking(BOOKING_ID);
    for (let i = 1; i <= 5; i++) bucket.put(`galleries/b1/IMG_${i}.jpg`, `photo ${i} `.repeat(1000));

    await call();

    const entries = await readZip(bucket.objects.get(ZIP_NAME)!.data);
    assert.equal(entries.size, 5);
    for (const entry of entries.values()) assert.equal(entry.method, 0); // 0 = stored
    assert.equal(bucket.readStreamsOpened, 5);
    assert.equal(bucket.maxOpenReads, 1);
  });

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
        responseDisposition: 'attachment; filename="brookie-babies-photos-2026-09-01.zip"',
      },
    ]);
    assert.deepEqual(result, {
      url: "https://storage.example/gallery-zips/b1.zip?signature=1",
      photoCount: 1,
      expiresAt: "2026-10-16T13:00:00.000Z",
    });
  });

  test("names the download after the booking ID when there is no date", async () => {
    addBooking(BOOKING_ID, {date: undefined});
    bucket.put("galleries/b1/a.jpg", "a");

    await call();

    assert.equal(
      bucket.signedUrlConfigs[0].responseDisposition,
      'attachment; filename="brookie-babies-photos-b1.zip"',
    );
  });

  test("zipFileName keeps the header safe", () => {
    assert.equal(zipFileName("2026-09-01", "b1"), "brookie-babies-photos-2026-09-01.zip");
    assert.equal(zipFileName('2026/09/01"; x=y', "b1"), "brookie-babies-photos-2026-09-01-x-y.zip");
    assert.equal(zipFileName("\r\n", "b1"), "brookie-babies-photos-b1.zip");
    assert.equal(zipFileName('"""', "b1"), "brookie-babies-photos-b1.zip");
    assert.equal(zipFileName(20260901, "b1"), "brookie-babies-photos-b1.zip");
  });
});

describe("handleGalleryDownloadRequest", {timeout: 10_000}, () => {
  let logged: unknown[];
  const handle = (request: {auth?: {uid: string} | null; data: unknown}) =>
    handleGalleryDownloadRequest({...deps, logError: (_m, e) => logged.push(e)}, request);

  beforeEach(() => {
    logged = [];
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
});

describe("helpers", () => {
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
