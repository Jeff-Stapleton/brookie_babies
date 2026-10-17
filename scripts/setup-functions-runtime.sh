#!/usr/bin/env bash
# One-time, idempotent: give the Cloud Functions' runtime service account
# exactly what getGalleryDownloadUrl needs, and nothing project-wide beyond
# reading Firestore.
#
#   - read bookings:            roles/datastore.viewer (project)
#   - read photos, save zips:   roles/storage.objectUser on the default bucket only
#   - sign download links:      roles/iam.serviceAccountTokenCreator on ITSELF only
#
# It also removes a project-wide Token Creator grant for this account if one
# exists: that would let the functions act as every service account in the
# project (including the CI deployer), not just sign their own links.
#
# Run once as the project owner, from the repository root:
#   gcloud auth login
#   bash scripts/setup-functions-runtime.sh
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="brookie-babies"
PROJECT_NUMBER="375587092017"
BUCKET="gs://brookie-babies.firebasestorage.app"
# 2nd-gen functions run as the default compute service account unless
# functions/src sets another one (setGlobalOptions({serviceAccount})).
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
MEMBER="serviceAccount:${RUNTIME_SA}"

log() { printf '\n==> %s\n' "$*"; }
run() { printf '    $'; printf ' %q' "$@"; printf '\n'; "$@"; }

command -v gcloud >/dev/null || { echo "gcloud not found: brew install --cask gcloud-cli" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found: brew install jq" >&2; exit 1; }
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
[[ -n "${ACCOUNT}" ]] || { echo "No active gcloud account. Run: gcloud auth login" >&2; exit 1; }
echo "gcloud account: ${ACCOUNT}"
echo "runtime account: ${RUNTIME_SA}"

ACTUAL_SA="$(gcloud functions describe getGalleryDownloadUrl --region=us-central1 \
  --project="${PROJECT_ID}" --format='value(serviceConfig.serviceAccountEmail)' 2>/dev/null || true)"
if [[ -n "${ACTUAL_SA}" && "${ACTUAL_SA}" != "${RUNTIME_SA}" ]]; then
  echo "getGalleryDownloadUrl runs as ${ACTUAL_SA}, not ${RUNTIME_SA}; update RUNTIME_SA first." >&2
  exit 1
fi

log "Firestore: read bookings"
run gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="${MEMBER}" --role=roles/datastore.viewer --condition=None --format=none

log "Storage: read photos and write zips in ${BUCKET} only"
run gcloud storage buckets add-iam-policy-binding "${BUCKET}" \
  --member="${MEMBER}" --role=roles/storage.objectUser --format=none

log "Signing download links: Token Creator on the runtime account itself"
run gcloud iam service-accounts add-iam-policy-binding "${RUNTIME_SA}" --project="${PROJECT_ID}" \
  --member="${MEMBER}" --role=roles/iam.serviceAccountTokenCreator --condition=None --format=none

log "Removing any project-wide Token Creator grant for the runtime account"
HAS_PROJECT_WIDE="$(gcloud projects get-iam-policy "${PROJECT_ID}" --flatten='bindings[].members' \
  --filter="bindings.role=roles/iam.serviceAccountTokenCreator AND bindings.members:${MEMBER}" \
  --format='value(bindings.role)')"
if [[ -n "${HAS_PROJECT_WIDE}" ]]; then
  run gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
    --member="${MEMBER}" --role=roles/iam.serviceAccountTokenCreator --condition=None --format=none
else
  echo "    none"
fi

log "Result"
echo "    Project roles of ${RUNTIME_SA}:"
gcloud projects get-iam-policy "${PROJECT_ID}" --flatten='bindings[].members' \
  --filter="bindings.members:${MEMBER}" --format='value(bindings.role)' | sed 's/^/      /'
echo "    On ${BUCKET}:"
# (gcloud storage has no --filter, hence jq.)
gcloud storage buckets get-iam-policy "${BUCKET}" --format=json \
  | jq -r --arg m "${MEMBER}" '.bindings[] | select(.members | index($m)) | .role' | sed 's/^/      /'
echo "    On the runtime account itself:"
gcloud iam service-accounts get-iam-policy "${RUNTIME_SA}" --project="${PROJECT_ID}" \
  --flatten='bindings[].members' --format='value(bindings.role,bindings.members)' | sed 's/^/      /'
echo
echo "IAM changes can take a few minutes to take effect."
