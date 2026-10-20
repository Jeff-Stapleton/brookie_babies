#!/usr/bin/env bash
# Checks firestore.rules and storage.rules, as they are in this checkout,
# against the cases in rules-tests/ with the Firebase Rules API's test
# endpoint (projects/brookie-babies:test). Run it before deploying a rules
# change.
#
# It's read-only: each request carries the rules and the documents or files
# it asks about, so nothing is deployed and no live data is read or written.
# It never prints the access token. Exits 1 if any case fails.
#
# Run as anyone who can deploy the rules, from anywhere in the repository:
#   gcloud auth login
#   bash scripts/test-rules.sh
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="brookie-babies"
ENDPOINT="https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}:test"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v gcloud >/dev/null || { echo "gcloud not found: brew install --cask gcloud-cli" >&2; exit 1; }
command -v node >/dev/null || { echo "node not found: brew install node@24" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
[[ -n "${ACCOUNT}" ]] || { echo "No active gcloud account. Run: gcloud auth login" >&2; exit 1; }
echo "gcloud account: ${ACCOUNT}"

# Only ever piped to curl by printf (a builtin), so it never shows up in this
# script's output, the process list or a temporary file.
TOKEN="$(gcloud auth print-access-token)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

failed=0
for kind in firestore storage; do
  node "${ROOT}/rules-tests/payload.mjs" "${kind}" "${WORK}/${kind}.json"
  # A user's gcloud credentials need a quota project, hence
  # x-goog-user-project.
  status="$(printf 'Authorization: Bearer %s\n' "${TOKEN}" \
    | curl -sS -X POST "${ENDPOINT}" \
      -H @- \
      -H "x-goog-user-project: ${PROJECT_ID}" \
      -H "Content-Type: application/json" \
      --data-binary @"${WORK}/${kind}.json" \
      -o "${WORK}/${kind}-result.json" \
      -w '%{http_code}')" || status="000"
  node "${ROOT}/rules-tests/report.mjs" "${kind}" "${WORK}/${kind}-result.json" "${status}" || failed=1
done
exit "${failed}"
