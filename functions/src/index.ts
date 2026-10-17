// Cloud Functions for Brookie Babies. Deploy with
// `firebase deploy --only functions` (see README, "Deploying the backend").

import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {setGlobalOptions} from "firebase-functions";
import {onCall} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {handleGalleryDownloadRequest, type GalleryDeps} from "./gallery";

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
  };
}

/**
 * Callable: {bookingId} -> {url, photoCount, expiresAt}, a signed URL (valid
 * for 60 minutes) to a zip of every photo of the caller's paid booking.
 *
 * Signing uses the IAM signBlob API, so the runtime service account needs
 * "Service Account Token Creator" on itself and the IAM Service Account
 * Credentials API must be enabled.
 */
export const getGalleryDownloadUrl = onCall(
  // Zipping a large gallery can take minutes; the Flutter client waits 9.
  {memory: "1GiB", timeoutSeconds: 540},
  (request) =>
    handleGalleryDownloadRequest(
      {
        ...realDeps(),
        logError: (message, error) => logger.error(message, error),
      },
      request,
    ),
);
