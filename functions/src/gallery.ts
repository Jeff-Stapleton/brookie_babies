// Core logic of the getGalleryDownloadUrl callable: checks that the caller
// may download a booking whose photos are ready (their own paid booking, or
// an ad hoc session shared with their verified Google email), zips the
// photos in galleries/{bookingId}/ into gallery-zips/{bookingId}.zip
// (reusing the zip while the photos are unchanged) and returns a short-lived
// signed URL for it. While it builds a zip, it streams its progress to callers
// that ask for it (the site).
//
// Who may download mirrors who may read the booking in firestore.rules
// (admins aside: they read every booking but download none), so the app only
// ever shows a download the caller can get.
//
// Firestore and Storage are injected as the small interfaces below, so the
// unit tests can use in-memory fakes. index.ts passes the real Admin SDK
// objects, which satisfy these interfaces structurally.

import {createHash} from "node:crypto";
import type {Readable, Writable} from "node:stream";
import {pipeline} from "node:stream/promises";
import {HttpsError} from "firebase-functions/https";
import * as yazl from "yazl";

export const GALLERY_PREFIX = "galleries/";
export const ZIP_PREFIX = "gallery-zips/";
export const SIGNED_URL_TTL_MS = 60 * 60 * 1000;
export const BOOKING_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

// Bump when the zip layout changes (entry naming, options) so zips cached by
// an older version are rebuilt.
export const ZIP_FORMAT_VERSION = "brookie-babies-gallery-zip-v1";

// At most one progress chunk per this long, so a gallery of small photos
// doesn't send one per photo.
export const PROGRESS_INTERVAL_MS = 500;
// Builds this long are logged as warnings: they're close to index.ts's
// timeoutSeconds (540).
export const SLOW_BUILD_MS = 500_000;

// Typographic apostrophes: notPaid and notReady reach families as they are
// (galleryErrorMessage in lib/services/gallery_service.dart).
export const MESSAGES = {
  unauthenticated: "Please sign in to download your photos.",
  invalidArgument: "A valid booking ID is required.",
  notFound: "We couldn’t find that booking.",
  notPaid: "This session isn’t paid for yet.",
  notReady: "Your photos aren’t ready yet.",
  internal: "We couldn’t prepare your photos. Please try again in a few minutes.",
} as const;

/**
 * Progress while a zip is built, streamed to the site. Mirrors
 * GalleryProgress.fromChunk in lib/services/gallery_service.dart; change them
 * together, adding fields only.
 */
export interface GalleryProgress {
  /** Always "zipping"; the site ignores other stages, so new ones can be added. */
  stage: "zipping";
  /**
   * Photos read into the zip so far. It reaches photoCount only in the last
   * chunk, sent once the whole zip has been read.
   */
  photosDone: number;
  photoCount: number;
  /**
   * The photos' total size from the listing (the zip adds a few hundred bytes
   * a photo); null if one wasn't listed.
   */
  totalBytes: number | null;
}

/** Response of the callable, shared with the Flutter client. */
export interface GalleryDownload {
  url: string;
  photoCount: number;
  /** ISO 8601. */
  expiresAt: string;
  /** As GalleryProgress.totalBytes. */
  totalBytes: number | null;
}

// ---------------------------------------------------------------------------
// Injected dependencies (subsets of the Admin SDK's Firestore and Bucket).
// ---------------------------------------------------------------------------

export interface DocumentSnapshotLike {
  readonly exists: boolean;
  data(): Record<string, unknown> | undefined;
}

export interface FirestoreLike {
  doc(path: string): {get(): Promise<DocumentSnapshotLike>};
}

/** A source photo as returned by Bucket.getFiles(). */
export interface SourceFileLike {
  readonly name: string;
  readonly metadata: {
    generation?: string | number;
    size?: string | number;
    updated?: string;
  };
  createReadStream(): Readable;
}

export interface SignedUrlConfig {
  version: "v4";
  action: "read";
  expires: Date;
  responseDisposition: string;
}

export interface ZipWriteStreamOptions {
  metadata: {
    contentType: string;
    metadata: {sourceFingerprint: string};
  };
}

/** The cached zip object, as returned by Bucket.file(). */
export interface ZipObjectLike {
  exists(): Promise<[boolean, ...unknown[]]>;
  getMetadata(): Promise<
    [{metadata?: Record<string, unknown> | null}, ...unknown[]]
  >;
  createWriteStream(options: ZipWriteStreamOptions): Writable;
  getSignedUrl(config: SignedUrlConfig): Promise<[string, ...unknown[]]>;
}

export interface BucketLike {
  getFiles(query: {prefix: string}): Promise<[SourceFileLike[], ...unknown[]]>;
  file(name: string): ZipObjectLike;
}

export interface GalleryDeps {
  db: FirestoreLike;
  bucket: BucketLike;
  /** Clock, injectable for tests. */
  now: () => Date;
  /** Build timings and callers who left. uid only, never the email. */
  log?: (level: "info" | "warning", message: string) => void;
}

// ---------------------------------------------------------------------------
// Callable entry points.
// ---------------------------------------------------------------------------

/**
 * The signed-in caller: the uid and the ID token's claims, as onCall passes
 * them. The claims are `unknown` because nothing guarantees their types.
 */
export interface CallerAuth {
  uid: string;
  token?: {email?: unknown; email_verified?: unknown};
}

export interface CallableRequestLike {
  auth?: CallerAuth | null;
  data: unknown;
}

/**
 * What getGalleryDownload needs from onCall's response. A
 * CallableResponse<GalleryProgress> fits it as it is.
 */
export interface ProgressStream {
  /** Resolves false, writing nothing, when the caller doesn't stream or has left. */
  sendChunk(chunk: GalleryProgress): Promise<boolean>;
  /**
   * Aborted when the caller disconnects, and also when a response ends: remove
   * listeners before returning.
   */
  readonly signal: AbortSignal;
}

/**
 * Thin wrapper used by the onCall handler: requires sign-in, passes
 * HttpsErrors through and turns anything else into a logged 'internal' error
 * with a customer-friendly message. The stream goes to getGalleryDownload as
 * it is: for a caller that doesn't stream, sendChunk writes nothing.
 */
export async function handleGalleryDownloadRequest(
  deps: GalleryDeps & {logError: (message: string, error: unknown) => void},
  request: CallableRequestLike,
  stream?: ProgressStream,
): Promise<GalleryDownload> {
  const auth = request.auth;
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", MESSAGES.unauthenticated);
  }
  try {
    return await getGalleryDownload(deps, auth, request.data, stream);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    // Only reachable after the booking ID passed validation. Never log the
    // caller's email: the uid is enough to find them.
    const bookingId = (request.data as {bookingId?: unknown} | null)?.bookingId;
    deps.logError(
      `getGalleryDownloadUrl failed for booking ${String(bookingId)} (uid ${auth.uid})`,
      error,
    );
    throw new HttpsError("internal", MESSAGES.internal);
  }
}

/**
 * Returns a signed download URL for the zip of all photos of a booking the
 * caller may download, building (or rebuilding) the zip if needed. While it
 * builds one, it sends GalleryProgress to `stream`; nothing is sent before
 * the build, on a cached zip or for an error.
 */
export async function getGalleryDownload(
  deps: GalleryDeps,
  caller: CallerAuth,
  data: unknown,
  stream?: ProgressStream,
): Promise<GalleryDownload> {
  const bookingId = parseBookingId(data);

  const snapshot = await deps.db.doc(`bookings/${bookingId}`).get();
  const booking = snapshot.exists ? snapshot.data() : undefined;
  // Same error for "doesn't exist" and "someone else's", and before any
  // status or readiness check, so booking IDs can't be probed.
  if (!booking || !canDownload(booking, caller)) {
    throw new HttpsError("not-found", MESSAGES.notFound);
  }
  // Bookings are typed in by hand; accept " Paid " the same way the Flutter
  // client (Booking.fromMap) does, so it never shows a download that fails.
  // Ad hoc sessions need no payment.
  const status =
    typeof booking.status === "string"
      ? booking.status.trim().toLowerCase()
      : undefined;
  if (status !== "paid" && status !== "adhoc") {
    throw new HttpsError("failed-precondition", MESSAGES.notPaid);
  }
  if (booking.photosReady !== true) {
    throw new HttpsError("failed-precondition", MESSAGES.notReady);
  }

  const prefix = `${GALLERY_PREFIX}${bookingId}/`;
  const [listed] = await deps.bucket.getFiles({prefix});
  const photos = selectPhotos(listed, prefix);
  if (photos.length === 0) {
    throw new HttpsError("failed-precondition", MESSAGES.notReady);
  }

  const fingerprint = computeFingerprint(photos);
  const zipObject = deps.bucket.file(`${ZIP_PREFIX}${bookingId}.zip`);
  // From the listing, so a cached zip reports the same size as a new one.
  const totalBytes = totalSize(photos);
  if (!(await isCachedZipCurrent(zipObject, fingerprint))) {
    const started = deps.now().getTime();
    const elapsed = (): number => deps.now().getTime() - started;
    const log = (message: string): void =>
      deps.log?.(elapsed() >= SLOW_BUILD_MS ? "warning" : "info", message);
    const who = `booking ${bookingId} (uid ${caller.uid})`; // Never the email.
    let photosDone = 0;
    const send = stream ? progressSender(stream, deps.now) : undefined;
    // The build goes on without the caller, so a retry finds it cached (best
    // effort: Cloud Run doesn't promise CPU to a request whose caller has
    // gone). A timeout may show up as the caller leaving too.
    const left = (): void =>
      log(
        `getGalleryDownloadUrl's caller left ${elapsed()} ms into building ` +
          `the zip for ${who}, with ${photosDone} of ${photos.length} photos ` +
          "in; finishing it anyway",
      );
    stream?.signal.addEventListener("abort", left, {once: true});
    if (stream?.signal.aborted) left(); // A listener added after the abort never fires.
    try {
      await buildZip(zipObject, photos, fingerprint, deps.now(), (done) => {
        photosDone = done;
        send?.({
          stage: "zipping",
          photosDone: done,
          photoCount: photos.length,
          totalBytes,
        });
      });
    } finally {
      // The signal also aborts when a normal response ends: don't log that
      // as leaving.
      stream?.signal.removeEventListener("abort", left);
    }
    log(
      `getGalleryDownloadUrl built the zip for ${who}: ${photos.length} photos, ` +
        `${totalBytes ?? "unknown"} bytes, in ${elapsed()} ms`,
    );
  }

  const expires = new Date(deps.now().getTime() + SIGNED_URL_TTL_MS);
  const [url] = await zipObject.getSignedUrl({
    version: "v4",
    action: "read",
    expires,
    responseDisposition: contentDisposition(
      zipFileName(booking.date, bookingId),
    ),
  });
  return {url, photoCount: photos.length, expiresAt: expires.toISOString(), totalBytes};
}

/**
 * Sends progress to the caller: the first chunk and the last (photosDone >=
 * photoCount) always, others at most once per intervalMs. Never throws or
 * rejects; silent once the caller has left.
 */
export function progressSender(
  stream: ProgressStream,
  now: () => Date,
  intervalMs = PROGRESS_INTERVAL_MS,
): (progress: GalleryProgress) => void {
  let lastSent: number | undefined;
  return (progress) => {
    if (stream.signal.aborted) return;
    const time = now().getTime();
    const last = progress.photosDone >= progress.photoCount;
    if (!last && lastSent !== undefined && time - lastSent < intervalMs) return;
    lastSent = time;
    // Not awaited: a slow browser must never slow the zip. Never left
    // unhandled either: an unhandled rejection crashes the instance.
    try {
      stream.sendChunk({...progress}).catch(() => undefined);
    } catch {
      // A response that's already gone.
    }
  };
}

// ---------------------------------------------------------------------------
// Helpers (exported for tests).
// ---------------------------------------------------------------------------

/**
 * Whether the caller may download this booking's photos: it carries their
 * uid, or it's an ad hoc session (status exactly "adhoc", as only the admin
 * pages write it) shared with the email the caller verified with Google.
 * Like the bookings read rule in firestore.rules, which compares the stored
 * email (saved lowercase) with the token's email lowercased.
 *
 * Booking fields and claims are checked with typeof first, so odd values
 * typed into the console mean "not theirs", never a TypeError ('internal').
 */
export function canDownload(
  booking: Record<string, unknown>,
  caller: CallerAuth,
): boolean {
  if (booking.uid === caller.uid) return true;
  const email = caller.token?.email;
  return (
    booking.status === "adhoc" &&
    caller.token?.email_verified === true &&
    typeof email === "string" &&
    typeof booking.email === "string" &&
    booking.email === email.toLowerCase()
  );
}

export function parseBookingId(data: unknown): string {
  const bookingId =
    typeof data === "object" && data !== null
      ? (data as {bookingId?: unknown}).bookingId
      : undefined;
  if (typeof bookingId !== "string" || !BOOKING_ID_PATTERN.test(bookingId)) {
    throw new HttpsError("invalid-argument", MESSAGES.invalidArgument);
  }
  return bookingId;
}

export interface Photo {
  file: SourceFileLike;
  /** Full object name, e.g. galleries/abc/IMG_0001.jpg. */
  name: string;
  /** Sanitized, unique path inside the zip. */
  entryName: string;
  generation: string;
  /** Byte size from the listing, if known. */
  size: number | undefined;
  mtime: Date | undefined;
}

/**
 * Keeps real photo files under `prefix`, sorted by object name, and gives
 * each a safe, unique zip entry name. Skips folder placeholders (names ending
 * in '/') and hidden files (basename starting with '.', e.g. .DS_Store).
 */
export function selectPhotos(
  files: readonly SourceFileLike[],
  prefix: string,
): Photo[] {
  const candidates = files
    .filter((file) => file.name.startsWith(prefix))
    .filter((file) => !file.name.endsWith("/"))
    .filter((file) => {
      const basename = file.name.split(/[\\/]/).pop() ?? "";
      return basename !== "" && !basename.startsWith(".");
    })
    .sort((a, b) => compareStrings(a.name, b.name));

  const used = new Set<string>();
  return candidates.map((file) => {
    const entryName = uniqueEntryName(
      sanitizeEntryName(file.name.slice(prefix.length)),
      used,
    );
    const mtime = file.metadata.updated
      ? new Date(file.metadata.updated)
      : undefined;
    return {
      file,
      name: file.name,
      entryName,
      generation: String(file.metadata.generation ?? ""),
      size: parseSize(file.metadata.size),
      mtime: mtime && !Number.isNaN(mtime.getTime()) ? mtime : undefined,
    };
  });
}

/** The photos' total size from the listing, or null if one wasn't listed. */
export function totalSize(photos: readonly Pick<Photo, "size">[]): number | null {
  let total = 0;
  for (const photo of photos) {
    if (photo.size === undefined) return null;
    total += photo.size;
  }
  return total;
}

function parseSize(size: string | number | undefined): number | undefined {
  const value = typeof size === "string" && /^\d+$/.test(size) ? Number(size) : size;
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0
    ? value
    : undefined;
}

/**
 * Makes a relative object path safe as a zip entry name: backslashes become
 * '/', empty, '.' and '..' segments are dropped (so nothing can start with '/'
 * or climb out of the extraction folder), and control characters and
 * characters Windows forbids in file names become '_'.
 */
export function sanitizeEntryName(relativePath: string): string {
  const segments = relativePath
    .replace(/\\/g, "/")
    .split("/")
    .filter((segment) => segment !== "" && segment !== "." && segment !== "..")
    // eslint-disable-next-line no-control-regex
    .map((segment) => segment.replace(/[\u0000-\u001f\u007f<>:"|?*]/g, "_"));
  return segments.length > 0 ? segments.join("/") : "photo";
}

/**
 * Appends " (2)", " (3)", ... before the extension when a name is already
 * used. Case-insensitive, because macOS and Windows file systems are.
 */
function uniqueEntryName(name: string, used: Set<string>): string {
  let candidate = name;
  for (let n = 2; used.has(candidate.toLowerCase()); n++) {
    const slash = name.lastIndexOf("/");
    const dot = name.lastIndexOf(".");
    const hasExtension = dot > slash + 1;
    candidate = hasExtension
      ? `${name.slice(0, dot)} (${n})${name.slice(dot)}`
      : `${name} (${n})`;
  }
  used.add(candidate.toLowerCase());
  return candidate;
}

/**
 * sha256 over the sorted `name\ngeneration\nsize` of every source file. Any
 * upload, replacement or deletion changes it.
 */
export function computeFingerprint(
  photos: readonly Pick<Photo, "name" | "generation" | "size">[],
): string {
  const hash = createHash("sha256");
  hash.update(`${ZIP_FORMAT_VERSION}\n`);
  // Object names cannot contain '\n', so the lines are unambiguous.
  for (const photo of [...photos].sort((a, b) => compareStrings(a.name, b.name))) {
    hash.update(`${photo.name}\n${photo.generation}\n${photo.size ?? ""}\n`);
  }
  return hash.digest("hex");
}

async function isCachedZipCurrent(
  zipObject: ZipObjectLike,
  fingerprint: string,
): Promise<boolean> {
  const [exists] = await zipObject.exists();
  if (!exists) return false;
  const [metadata] = await zipObject.getMetadata();
  return metadata.metadata?.sourceFingerprint === fingerprint;
}

/**
 * Streams every photo from Storage through yazl straight back into Storage,
 * one photo at a time, so memory use doesn't grow with the gallery size.
 *
 * Storage only creates an object when its upload finishes, so on any error
 * the upload is destroyed (never finished): no zip carrying this
 * fingerprint appears, and a previously cached zip is left untouched.
 *
 * `onProgress` hears how many photos are in the zip: each time yazl opens the
 * next one, and photos.length once the whole zip has left yazl (a build that
 * fails first never gets there). It's called synchronously from yazl and the
 * output stream, so it must not throw; throttling is left to the caller.
 */
export async function buildZip(
  zipObject: ZipObjectLike,
  photos: readonly Photo[],
  fingerprint: string,
  now: Date,
  onProgress?: (photosDone: number) => void,
): Promise<void> {
  const zipfile = new yazl.ZipFile();
  const output = zipfile.outputStream as Readable;
  const upload = zipObject.createWriteStream({
    metadata: {
      contentType: "application/zip",
      metadata: {sourceFingerprint: fingerprint},
    },
  });

  let currentSource: Readable | undefined;
  let failure: Error | undefined;
  const fail = (error: unknown): void => {
    if (failure) return;
    failure = error instanceof Error ? error : new Error(String(error));
    // yazl doesn't watch its input streams and reports its own problems
    // (e.g. a size mismatch) as 'error' on the ZipFile, not on outputStream,
    // so the pipeline below would otherwise wait forever.
    upload.destroy(failure);
    output.destroy(failure);
    currentSource?.destroy();
  };
  zipfile.on("error", fail);

  photos.forEach((photo, index) => {
    // Lazy: each download starts only when yazl reaches that entry, so at
    // most one source stream is open at a time.
    zipfile.addReadStreamLazy(
      photo.entryName,
      {
        compress: false, // JPEGs don't compress; storing is much faster.
        mtime: photo.mtime ?? now,
        // Lets yazl check the bytes read against the listing.
        ...(photo.size !== undefined ? {size: photo.size} : {}),
      },
      (callback) => {
        if (failure) return; // Already failing; don't start another download.
        // yazl opens a photo only once every earlier one has been read into
        // the zip. The first getter runs synchronously inside
        // addReadStreamLazy.
        onProgress?.(index);
        const source = photo.file.createReadStream();
        currentSource = source;
        source.on("error", fail);
        callback(null, source);
      },
    );
  });
  zipfile.end();
  // The last chunk: every byte has left yazl, and Storage is finishing the
  // upload. An 'end' listener doesn't start the stream flowing (never add
  // 'data' or call resume(): that would read ahead of Storage). A failed
  // build destroys `output`, which emits no 'end'.
  output.once("end", () => onProgress?.(photos.length));

  try {
    await pipeline(output, upload);
  } catch (error) {
    fail(error);
  }
  if (failure) throw failure;
}

export function zipFileName(date: unknown, bookingId: string): string {
  const label =
    typeof date === "string" && date.trim() !== "" ? date.trim() : bookingId;
  const safe = label
    .replace(/[^A-Za-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);
  return `brooke-stapleton-photography-${safe || bookingId}.zip`;
}

function contentDisposition(fileName: string): string {
  return `attachment; filename="${fileName}"`;
}

/** Locale-independent ordering (code units), stable across runtimes. */
function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
