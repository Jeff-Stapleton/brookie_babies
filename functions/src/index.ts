// Cloud Functions for Brookie Babies. Deploy with
// `firebase deploy --only functions` (see README, "Deploying the backend").

import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {setGlobalOptions} from "firebase-functions";
import {onCall} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {
  handleGalleryDownloadRequest,
  type GalleryDeps,
  type GalleryDownload,
  type GalleryProgress,
} from "./gallery";

setGlobalOptions({region: "us-central1", maxInstances: 5});

// No arguments: Application Default Credentials (the function's runtime
// service account) and the project's default Storage bucket. Never use a key
// file; this repository is public.
initializeApp();

function realDeps(): GalleryDeps {
  return {
    db: getFirestore(),
    bucket: getStorage().bucket(),
    now: () => new Date(),
    log: (level, message) =>
      level === "warning" ? logger.warn(message) : logger.info(message),
  };
}

/**
 * Callable: {bookingId} -> {url, photoCount, expiresAt, totalBytes}, a signed
 * URL (valid for 60 minutes) to a zip of every photo of the caller's paid
 * booking, or of an ad hoc session shared with the caller's verified Google
 * email. While it builds a zip, streaming callers (the site) get
 * GalleryProgress chunks; others get only the result. A caller who leaves
 * doesn't stop the build, so the next download can reuse it.
 *
 * Signing uses the IAM signBlob API, so the runtime service account needs
 * "Service Account Token Creator" on itself and the IAM Service Account
 * Credentials API must be enabled.
 */
export const getGalleryDownloadUrl = onCall<
  unknown,
  Promise<GalleryDownload>,
  GalleryProgress
>(
  // Zipping a large gallery can take minutes. The site shows progress and
  // gives up after 10 (readGalleryDownload): keep that above timeoutSeconds.
  // The default heartbeat (every 30 s) keeps a quiet stream open.
  {memory: "1GiB", timeoutSeconds: 540},
  (request, response) =>
    handleGalleryDownloadRequest(
      {
        ...realDeps(),
        logError: (message, error) => logger.error(message, error),
      },
      request,
      response,
    ),
);
