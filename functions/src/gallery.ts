// Core logic of the getGalleryDownloadUrl callable: checks that the caller
// owns a paid booking whose photos are ready, zips the photos in
// galleries/{bookingId}/ into gallery-zips/{bookingId}.zip (reusing the zip
// while the photos are unchanged) and returns a short-lived signed URL for it.
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

export const MESSAGES = {
  unauthenticated: "Please sign in to download your photos.",
  invalidArgument: "A valid booking ID is required.",
  notFound: "We couldn't find that booking.",
  notPaid: "This session isn't paid for yet.",
  notReady: "Your photos aren't ready yet.",
  internal: "We couldn't prepare your photos. Please try again in a few minutes.",
} as const;

/** Response of the callable, shared with the Flutter client. */
export interface GalleryDownload {
  url: string;
  photoCount: number;
  /** ISO 8601. */
  expiresAt: string;
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
}

// ---------------------------------------------------------------------------
// Callable entry points.
// ---------------------------------------------------------------------------

export interface CallableRequestLike {
  auth?: {uid: string} | null;
  data: unknown;
}

/**
 * Thin wrapper used by the onCall handler: requires sign-in, passes
 * HttpsErrors through and turns anything else into a logged 'internal' error
 * with a customer-friendly message.
 */
export async function handleGalleryDownloadRequest(
  deps: GalleryDeps & {logError: (message: string, error: unknown) => void},
  request: CallableRequestLike,
): Promise<GalleryDownload> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", MESSAGES.unauthenticated);
  }
  try {
    return await getGalleryDownload(deps, uid, request.data);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    // Only reachable after the booking ID passed validation.
    const bookingId = (request.data as {bookingId?: unknown} | null)?.bookingId;
    deps.logError(
      `getGalleryDownloadUrl failed for booking ${String(bookingId)} (uid ${uid})`,
      error,
    );
    throw new HttpsError("internal", MESSAGES.internal);
  }
}

/**
 * Returns a signed download URL for the zip of all photos of the caller's
 * booking, building (or rebuilding) the zip if needed.
 */
export async function getGalleryDownload(
  deps: GalleryDeps,
  uid: string,
  data: unknown,
): Promise<GalleryDownload> {
  const bookingId = parseBookingId(data);

  const snapshot = await deps.db.doc(`bookings/${bookingId}`).get();
  const booking = snapshot.exists ? snapshot.data() : undefined;
  // Same error for "doesn't exist" and "someone else's", so booking IDs
  // can't be probed.
  if (!booking || booking.uid !== uid) {
    throw new HttpsError("not-found", MESSAGES.notFound);
  }
  if (booking.status !== "paid") {
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
  if (!(await isCachedZipCurrent(zipObject, fingerprint))) {
    await buildZip(zipObject, photos, fingerprint, deps.now());
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
  return {url, photoCount: photos.length, expiresAt: expires.toISOString()};
}

// ---------------------------------------------------------------------------
// Helpers (exported for tests).
// ---------------------------------------------------------------------------

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
 */
export async function buildZip(
  zipObject: ZipObjectLike,
  photos: readonly Photo[],
  fingerprint: string,
  now: Date,
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

  for (const photo of photos) {
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
        const source = photo.file.createReadStream();
        currentSource = source;
        source.on("error", fail);
        callback(null, source);
      },
    );
  }
  zipfile.end();

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
  return `brookie-babies-photos-${safe || bookingId}.zip`;
}

function contentDisposition(fileName: string): string {
  return `attachment; filename="${fileName}"`;
}

/** Locale-independent ordering (code units), stable across runtimes. */
function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
