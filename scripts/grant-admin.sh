#!/usr/bin/env bash
# Makes a Google account an admin of the site, or with --revoke stops it
# being one, by setting the Firebase Auth custom claim `admin: true` on it.
# Admins see the Admin page: they add ad hoc sessions, upload and delete
# photos and choose the home page photos. firestore.rules and storage.rules
# check the claim on every request; nothing in the app can set it.
#
#   - The account must already exist (they signed in to the site with Google
#     once), be the only account with that email, and, to be granted, sign in
#     with Google with a verified email.
#   - Other custom claims on the account are kept.
#   - Granting shows once they refresh the site (the app then fetches a new
#     ID token). Revoking also signs them out everywhere (validSince), but a
#     sign-in they already have keeps admin access until its ID token
#     expires, within an hour.
#
# It never prints the access token or the account record Firebase returns
# (it can hold personal details and password hashes): only the uid, email,
# sign-in providers and the claims before and after. Safe to re-run.
#
# Run as the project owner, from the repository root:
#   gcloud auth login
#   bash scripts/grant-admin.sh brooke@example.com
#   bash scripts/grant-admin.sh brooke@example.com --revoke
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="brookie-babies"
API="https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}"

log() { printf '\n==> %s\n' "$*"; }
usage() { echo "Usage: bash scripts/grant-admin.sh <email> [--revoke]" >&2; exit 2; }

EMAIL=""
REVOKE=false
for arg in "$@"; do
  case "${arg}" in
    --revoke) REVOKE=true ;;
    -*) usage ;;
    *) [[ -z "${EMAIL}" ]] || usage; EMAIL="${arg}" ;;
  esac
done
[[ -n "${EMAIL}" ]] || usage
[[ "${EMAIL}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] \
  || { echo "Not an email address: ${EMAIL}" >&2; exit 2; }

command -v gcloud >/dev/null || { echo "gcloud not found: brew install --cask gcloud-cli" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found: brew install jq" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
[[ -n "${ACCOUNT}" ]] || { echo "No active gcloud account. Run: gcloud auth login" >&2; exit 1; }
echo "gcloud account: ${ACCOUNT}"

# Only ever piped to curl by printf (a builtin), so it never shows up in this
# script's output, the process list or a temporary file.
TOKEN="$(gcloud auth print-access-token)"

# POSTs a JSON body to accounts:<method> and leaves the response in RESPONSE,
# unprinted. A user's gcloud credentials need a quota project, hence
# x-goog-user-project.
api() {
  local method="$1" body="$2" out status message
  out="$(printf 'Authorization: Bearer %s\n' "${TOKEN}" \
    | curl -sS -X POST "${API}/accounts:${method}" \
      -H @- \
      -H "x-goog-user-project: ${PROJECT_ID}" \
      -H "Content-Type: application/json" \
      --data-binary "${body}" \
      -w '\n%{http_code}')"
  status="${out##*$'\n'}"
  RESPONSE="${out%$'\n'*}"
  if [[ "${status}" != 2?? ]]; then
    # Error bodies carry only a code and a message.
    message="$(response -r '.error.message // empty' 2>/dev/null || true)"
    echo "accounts:${method} failed (HTTP ${status}): ${message:-no error message}" >&2
    exit 1
  fi
}

# jq over RESPONSE, through a pipe: bash 3.2 (macOS) writes here-strings to a
# temporary file, and RESPONSE can hold the whole account record.
response() { printf '%s' "${RESPONSE}" | jq "$@"; }

log "Account for ${EMAIL}"
api lookup "$(jq -cn --arg email "${EMAIL}" '{email: [$email]}')"
COUNT="$(response '.users // [] | length')"
if [[ "${COUNT}" == 0 ]]; then
  echo "No account uses ${EMAIL}. Ask them to sign in to the site with Google once, then run this again." >&2
  exit 1
elif [[ "${COUNT}" != 1 ]]; then
  echo "${COUNT} accounts use ${EMAIL}, so it's unclear which one is theirs." >&2
  echo "Remove the duplicates in the Firebase console (Authentication, Users), then run this again." >&2
  exit 1
fi
# Only the fields used below; the rest of the record goes no further.
RECORD="$(response -c '.users[0] | {localId, email, emailVerified, customAttributes,
  providers: [.providerUserInfo[]?.providerId]}')"
USER_ID="$(jq -r '.localId' <<<"${RECORD}")"
BEFORE="$(jq -r '.customAttributes // "{}" | fromjson | tojson' <<<"${RECORD}")"
echo "    uid:       ${USER_ID}"
echo "    email:     $(jq -r '.email // "(none)"' <<<"${RECORD}")"
echo "    providers: $(jq -r '.providers | if length == 0 then "(none)" else join(", ") end' <<<"${RECORD}")"
echo "    claims:    ${BEFORE}"

if [[ "${REVOKE}" == true ]]; then
  # No identity checks here: whoever holds the claim, it must always be
  # possible to take it away.
  log "Revoking admin access"
  BODY="$(jq -c --arg since "$(date +%s)" '{
    localId,
    customAttributes: ((.customAttributes // "{}" | fromjson) | del(.admin) | tojson),
    validSince: $since
  }' <<<"${RECORD}")"
else
  # The rules trust the claim alone, so only grant it to an account that
  # proves the email with Google, the site's only way to sign in.
  jq -e '.emailVerified == true' <<<"${RECORD}" >/dev/null \
    || { echo "This account's email isn't verified, so it can't be made an admin." >&2; exit 1; }
  jq -e '.providers | index("google.com") != null' <<<"${RECORD}" >/dev/null \
    || { echo "This account doesn't sign in with Google, so it can't be made an admin." >&2; exit 1; }
  log "Granting admin access"
  BODY="$(jq -c '{
    localId,
    customAttributes: ((.customAttributes // "{}" | fromjson) + {admin: true} | tojson)
  }' <<<"${RECORD}")"
fi
api update "${BODY}"

# Read the claims back rather than trusting what was sent.
api lookup "$(jq -cn --arg uid "${USER_ID}" '{localId: [$uid]}')"
AFTER="$(response -r '.users[0].customAttributes // "{}" | fromjson | tojson')"

log "Result"
echo "    claims before: ${BEFORE}"
echo "    claims after:  ${AFTER}"
echo
if [[ "${REVOKE}" == true ]]; then
  jq -e 'has("admin") | not' <<<"${AFTER}" >/dev/null \
    || { echo "The admin claim is still set; check the account in the Firebase console." >&2; exit 1; }
  echo "${EMAIL} is no longer an admin and is signed out everywhere."
  echo "A sign-in they already have keeps admin access until it expires, within an hour."
else
  jq -e '.admin == true' <<<"${AFTER}" >/dev/null \
    || { echo "The admin claim didn't stick; check the account in the Firebase console." >&2; exit 1; }
  echo "${EMAIL} is now an admin. Ask them to refresh the site."
fi
