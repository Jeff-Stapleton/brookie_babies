#!/usr/bin/env bash
# One-time, idempotent: give the Cloud Functions' runtime service account
# exactly what getGalleryDownloadUrl needs, and nothing project-wide beyond
# reading Firestore and writing logs.
#
#   - read bookings:            roles/datastore.viewer (project)
#   - read photos, save zips:   roles/storage.objectUser on the default bucket only
#   - sign download links:      roles/iam.serviceAccountTokenCreator on ITSELF only
#
# The same account also BUILDS the functions: since 2024, Cloud Build uses the
# default compute account for projects like this one (no organization, so the
# old Cloud Build account can't be chosen). Every deploy fails with "missing
# permission on the build service account" without:
#
#   - fetch the uploaded source: roles/storage.objectViewer on the gcf-v2-sources bucket only
#   - save the built image:      roles/artifactregistry.writer on the gcf-artifacts repository only
#   - write build logs:          roles/logging.logWriter (project; it can't be granted lower)
#
# These are Google's documented minimum for a build account, each as narrow as
# it can be. Never fix a failed build with Editor or the project-wide Cloud
# Build roles instead: this account also runs the function, and those would
# reach every bucket, including families' photos.
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
# Where Cloud Functions keeps each deploy's source and its built images. Both
# are created by the first deploy in the region.
REGION="us-central1"
SOURCE_BUCKET="gs://gcf-v2-sources-${PROJECT_NUMBER}-${REGION}"
ARTIFACT_REPO="gcf-artifacts"

log() { printf '\n==> %s\n' "$*"; }
run() { printf '    $'; printf ' %q' "$@"; printf '\n'; "$@"; }
# Runs a describe command: 0 if the resource exists, 1 if it doesn't. Any
# other failure (no access, an expired sign-in) stops the script rather than
# skipping a grant the build needs.
exists() {
  local out
  if out="$("$@" --format=none 2>&1)"; then return 0; fi
  if printf '%s' "${out}" | grep -qiE 'NOT_FOUND|404|not found'; then return 1; fi
  printf '%s\n' "${out}" >&2
  echo "Couldn't check whether that exists (see above)." >&2
  exit 1
}

command -v gcloud >/dev/null || { echo "gcloud not found: brew install --cask gcloud-cli" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found: brew install jq" >&2; exit 1; }
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
[[ -n "${ACCOUNT}" ]] || { echo "No active gcloud account. Run: gcloud auth login" >&2; exit 1; }
echo "gcloud account: ${ACCOUNT}"
echo "runtime account: ${RUNTIME_SA}"

ACTUAL_SA="$(gcloud functions describe getGalleryDownloadUrl --region="${REGION}" \
  --project="${PROJECT_ID}" --format='value(serviceConfig.serviceAccountEmail)' 2>/dev/null || true)"
if [[ -n "${ACTUAL_SA}" && "${ACTUAL_SA}" != "${RUNTIME_SA}" ]]; then
  echo "getGalleryDownloadUrl runs as ${ACTUAL_SA}, not ${RUNTIME_SA}; update RUNTIME_SA first." >&2
  exit 1
fi
# Reported as projects/<project>/serviceAccounts/<email>.
BUILD_SA="$(gcloud functions describe getGalleryDownloadUrl --region="${REGION}" \
  --project="${PROJECT_ID}" --format='value(buildConfig.serviceAccount)' 2>/dev/null || true)"
if [[ -n "${BUILD_SA}" && "${BUILD_SA##*/}" != "${RUNTIME_SA}" ]]; then
  echo "getGalleryDownloadUrl is built as ${BUILD_SA##*/}, not ${RUNTIME_SA}: the build grants below" >&2
  echo "would go to the wrong account. Grant them to ${BUILD_SA##*/} instead." >&2
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

log "Builds: fetch the source from ${SOURCE_BUCKET} only"
if exists gcloud storage buckets describe "${SOURCE_BUCKET}"; then
  run gcloud storage buckets add-iam-policy-binding "${SOURCE_BUCKET}" \
    --member="${MEMBER}" --role=roles/storage.objectViewer --format=none
else
  echo "    ${SOURCE_BUCKET} doesn't exist yet: deploy the functions once, then run this again."
fi

log "Builds: save images in the ${ARTIFACT_REPO} repository only"
if exists gcloud artifacts repositories describe "${ARTIFACT_REPO}" --location="${REGION}" \
  --project="${PROJECT_ID}"; then
  run gcloud artifacts repositories add-iam-policy-binding "${ARTIFACT_REPO}" --location="${REGION}" \
    --project="${PROJECT_ID}" --member="${MEMBER}" --role=roles/artifactregistry.writer --format=none
else
  echo "    ${ARTIFACT_REPO} doesn't exist yet: deploy the functions once, then run this again."
fi

log "Builds: write build logs"
run gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="${MEMBER}" --role=roles/logging.logWriter --condition=None --format=none

log "Result"
echo "    Project roles of ${RUNTIME_SA}:"
gcloud projects get-iam-policy "${PROJECT_ID}" --flatten='bindings[].members' \
  --filter="bindings.members:${MEMBER}" --format='value(bindings.role)' | sed 's/^/      /'
echo "    On ${BUCKET}:"
# (gcloud storage has no --filter, hence jq.)
gcloud storage buckets get-iam-policy "${BUCKET}" --format=json \
  | jq -r --arg m "${MEMBER}" '.bindings[] | select(.members | index($m)) | .role' | sed 's/^/      /'
echo "    On ${SOURCE_BUCKET}:"
gcloud storage buckets get-iam-policy "${SOURCE_BUCKET}" --format=json 2>/dev/null \
  | jq -r --arg m "${MEMBER}" '.bindings[] | select(.members | index($m)) | .role' | sed 's/^/      /' \
  || echo '      (could not read its policy)'
echo "    On the ${ARTIFACT_REPO} repository:"
gcloud artifacts repositories get-iam-policy "${ARTIFACT_REPO}" --location="${REGION}" \
  --project="${PROJECT_ID}" --format=json 2>/dev/null \
  | jq -r --arg m "${MEMBER}" '(.bindings // [])[] | select(.members | index($m)) | .role' | sed 's/^/      /' \
  || echo '      (could not read its policy)'
echo "    On the runtime account itself:"
gcloud iam service-accounts get-iam-policy "${RUNTIME_SA}" --project="${PROJECT_ID}" \
  --flatten='bindings[].members' --format='value(bindings.role,bindings.members)' | sed 's/^/      /'
echo
echo "IAM changes can take a few minutes to take effect."
