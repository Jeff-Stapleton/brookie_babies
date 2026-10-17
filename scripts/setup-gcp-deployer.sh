#!/usr/bin/env bash
# One-time, idempotent setup for KEYLESS deploys (Workload Identity Federation)
# from GitHub Actions to the Firebase project "brookie-babies".
#
# Who can get credentials: only jobs in GitHub repository id 893674274
# (Jeff-Stapleton/brookie_babies, owner id 7402383) that run in the GitHub
# environment "production", on refs/heads/main, triggered by push or
# workflow_dispatch. They impersonate one dedicated deployer service account.
#
# Run once as the project owner, from the repository root (see README,
# "Automatic backend deploys"):
#   brew install --cask gcloud-cli      # (the old cask name google-cloud-sdk now points here)
#   gcloud auth login
#   bash scripts/setup-gcp-deployer.sh
#
# Safe to re-run: anything that exists is kept; a soft-deleted pool/provider is
# restored; the provider's mapping and condition and the custom role's
# permissions are re-applied so they always match this file. It never deletes
# anything, and it never creates a service account key.
set -euo pipefail

# Never stop to ask; this script decides everything explicitly.
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# ---------------------------------------------------------------------------
# Values. The GitHub ids were read from the GitHub API on 2026-10-17:
#   gh api repos/Jeff-Stapleton/brookie_babies --jq '{id, owner_id: .owner.id}'
# ---------------------------------------------------------------------------
PROJECT_ID="brookie-babies"
PROJECT_NUMBER="375587092017"

GITHUB_REPO="Jeff-Stapleton/brookie_babies" # for messages only; trust uses the numeric ids
GITHUB_REPO_ID="893674274"
GITHUB_OWNER_ID="7402383"
GITHUB_ENVIRONMENT="production" # case-sensitive; must match `environment:` in the workflow
DEPLOY_REF="refs/heads/main"

# Pool and provider ids: 4-32 chars of [a-z0-9-], no "gcp-" prefix.
POOL_ID="github-actions"
PROVIDER_ID="brookie-babies-prod"
# Service account id: 6-30 chars, [a-z][a-z0-9-]*.
SA_ID="github-deployer"
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

ISSUER_URI="https://token.actions.githubusercontent.com"

POOL_NAME="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}"
PROVIDER_NAME="${POOL_NAME}/providers/${PROVIDER_ID}"

# Every claim the condition reads must be mapped (Google requirement).
# attribute.repository_id_environment ("893674274/production") is what the
# service account binding below trusts, so the binding itself is pinned to
# this repo AND environment, even if another provider is ever added to the pool.
# google.subject = sub is only used for audit logs; nothing trusts it, so a
# repo rename or GitHub's immutable-subject format change can't break or widen access.
ATTRIBUTE_MAPPING="google.subject=assertion.sub"
ATTRIBUTE_MAPPING+=",attribute.repository_id=assertion.repository_id"
ATTRIBUTE_MAPPING+=",attribute.repository_owner_id=assertion.repository_owner_id"
ATTRIBUTE_MAPPING+=",attribute.repository=assertion.repository"
ATTRIBUTE_MAPPING+=",attribute.environment=assertion.environment"
ATTRIBUTE_MAPPING+=",attribute.ref=assertion.ref"
ATTRIBUTE_MAPPING+=",attribute.event_name=assertion.event_name"
ATTRIBUTE_MAPPING+=",attribute.actor=assertion.actor"
ATTRIBUTE_MAPPING+=",attribute.repository_id_environment=assertion.repository_id + '/' + assertion.environment"

# GitHub sends the ids as strings ("repository_id": "74"), so compare to strings.
# The environment claim only exists when the job declares `environment:`;
# a token without it fails this condition and is rejected.
ATTRIBUTE_CONDITION="assertion.repository_id == '${GITHUB_REPO_ID}'"
ATTRIBUTE_CONDITION+=" && assertion.repository_owner_id == '${GITHUB_OWNER_ID}'"
ATTRIBUTE_CONDITION+=" && assertion.environment == '${GITHUB_ENVIRONMENT}'"
ATTRIBUTE_CONDITION+=" && assertion.ref == '${DEPLOY_REF}'"
ATTRIBUTE_CONDITION+=" && (assertion.event_name == 'push' || assertion.event_name == 'workflow_dispatch')"

# Principal set allowed to impersonate the deployer (principalSet = every
# federated identity carrying this attribute value; principal:// would name a
# single google.subject, i.e. the name-based `sub`, which changes on a rename).
WIF_MEMBER="principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository_id_environment/${GITHUB_REPO_ID}/${GITHUB_ENVIRONMENT}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '\n==> %s\n' "$*"; }
run() { printf '    $'; printf ' %q' "$@"; printf '\n'; "$@"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# lookup FORMAT CMD... : prints the formatted value, or nothing if NOT_FOUND.
# Any other error (permissions, API disabled, ...) stops the script.
lookup() {
  local format="$1"; shift
  local out err rc=0
  err="$(mktemp)"
  out="$("$@" --format="${format}" 2>"${err}")" || rc=$?
  if [[ ${rc} -eq 0 ]]; then
    rm -f "${err}"; printf '%s' "${out}"; return 0
  fi
  if grep -qE 'NOT_FOUND|not found|does not exist' "${err}"; then
    rm -f "${err}"; return 0
  fi
  cat "${err}" >&2; rm -f "${err}"; return 1
}

# retry N SECONDS CMD... : new service accounts take a few seconds to appear.
retry() {
  local tries="$1" delay="$2"; shift 2
  local i
  for ((i = 1; i <= tries; i++)); do
    if "$@"; then return 0; fi
    if [[ ${i} -lt ${tries} ]]; then
      echo "    (attempt ${i}/${tries} failed; retrying in ${delay}s)" >&2
      sleep "${delay}"
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# 0. Preflight
# ---------------------------------------------------------------------------
log "Preflight"
command -v gcloud >/dev/null || die "gcloud not found. Install it with: brew install --cask gcloud-cli"
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
[[ -n "${ACCOUNT}" ]] || die "No active gcloud account. Run: gcloud auth login"
echo "    gcloud account: ${ACCOUNT}"
echo "    project:        ${PROJECT_ID} (${PROJECT_NUMBER})"
echo "    GitHub repo:    ${GITHUB_REPO} (repository_id ${GITHUB_REPO_ID}, owner_id ${GITHUB_OWNER_ID})"

# ---------------------------------------------------------------------------
# 1. APIs (enabling an enabled API is a no-op)
#    iam: pools/providers/SAs; sts: token exchange; iamcredentials: SA
#    impersonation; cloudresourcemanager: needed by firebase-tools;
#    cloudbilling: every functions deploy checks the project's billing (and
#    the deployer must not be able to enable APIs itself).
# ---------------------------------------------------------------------------
log "Enabling APIs"
run gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  cloudbilling.googleapis.com \
  --project="${PROJECT_ID}"

ACTUAL_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
[[ "${ACTUAL_NUMBER}" == "${PROJECT_NUMBER}" ]] \
  || die "Project ${PROJECT_ID} has number ${ACTUAL_NUMBER}, expected ${PROJECT_NUMBER}"

# ---------------------------------------------------------------------------
# 2. Workload identity pool
# ---------------------------------------------------------------------------
log "Workload identity pool ${POOL_ID}"
POOL_STATE="$(lookup 'value(state)' gcloud iam workload-identity-pools describe "${POOL_ID}" \
  --project="${PROJECT_ID}" --location=global)"
case "${POOL_STATE}" in
  "")
    run gcloud iam workload-identity-pools create "${POOL_ID}" \
      --project="${PROJECT_ID}" --location=global \
      --display-name="GitHub Actions" \
      --description="GitHub Actions OIDC for ${GITHUB_REPO} production deploys. Keep this pool for production only."
    ;;
  ACTIVE) echo "    already exists (ACTIVE)" ;;
  DELETED)
    echo "    soft-deleted; restoring it (a deleted id can't be reused for ~30 days)"
    run gcloud iam workload-identity-pools undelete "${POOL_ID}" \
      --project="${PROJECT_ID}" --location=global
    ;;
  *) die "pool ${POOL_ID} is in unexpected state ${POOL_STATE}" ;;
esac
POOL_DISABLED="$(lookup 'value(disabled)' gcloud iam workload-identity-pools describe "${POOL_ID}" \
  --project="${PROJECT_ID}" --location=global)"
case "${POOL_DISABLED}" in
  True | true) die "pool ${POOL_ID} is disabled. Re-enable it in the console (IAM & Admin > Workload Identity Federation), then re-run." ;;
esac

# ---------------------------------------------------------------------------
# 3. OIDC provider for GitHub Actions (created, or re-converged on every run)
# ---------------------------------------------------------------------------
log "OIDC provider ${PROVIDER_ID}"
echo "    issuer:    ${ISSUER_URI}"
echo "    condition: ${ATTRIBUTE_CONDITION}"
echo "    mapping:   ${ATTRIBUTE_MAPPING//,/$'\n'               }"
PROVIDER_STATE="$(lookup 'value(state)' gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
  --project="${PROJECT_ID}" --location=global --workload-identity-pool="${POOL_ID}")"
case "${PROVIDER_STATE}" in
  "")
    run gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
      --project="${PROJECT_ID}" --location=global \
      --workload-identity-pool="${POOL_ID}" \
      --display-name="brookie_babies prod deploys" \
      --description="GitHub Actions: repo id ${GITHUB_REPO_ID}, environment ${GITHUB_ENVIRONMENT}, ${DEPLOY_REF}" \
      --issuer-uri="${ISSUER_URI}" \
      --attribute-mapping="${ATTRIBUTE_MAPPING}" \
      --attribute-condition="${ATTRIBUTE_CONDITION}"
    ;;
  ACTIVE | DELETED)
    if [[ "${PROVIDER_STATE}" == "DELETED" ]]; then
      echo "    soft-deleted; restoring it"
      run gcloud iam workload-identity-pools providers undelete "${PROVIDER_ID}" \
        --project="${PROJECT_ID}" --location=global --workload-identity-pool="${POOL_ID}"
    else
      echo "    already exists; re-applying issuer, mapping and condition"
    fi
    run gcloud iam workload-identity-pools providers update-oidc "${PROVIDER_ID}" \
      --project="${PROJECT_ID}" --location=global \
      --workload-identity-pool="${POOL_ID}" \
      --display-name="brookie_babies prod deploys" \
      --description="GitHub Actions: repo id ${GITHUB_REPO_ID}, environment ${GITHUB_ENVIRONMENT}, ${DEPLOY_REF}" \
      --issuer-uri="${ISSUER_URI}" \
      --attribute-mapping="${ATTRIBUTE_MAPPING}" \
      --attribute-condition="${ATTRIBUTE_CONDITION}"
    ;;
  *) die "provider ${PROVIDER_ID} is in unexpected state ${PROVIDER_STATE}" ;;
esac
PROVIDER_DISABLED="$(lookup 'value(disabled)' gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
  --project="${PROJECT_ID}" --location=global --workload-identity-pool="${POOL_ID}")"
case "${PROVIDER_DISABLED}" in
  True | true) die "provider ${PROVIDER_ID} is disabled. Re-enable it in the console, then re-run." ;;
esac

# ---------------------------------------------------------------------------
# 4. Dedicated deployer service account (no keys are ever created for it)
# ---------------------------------------------------------------------------
log "Service account ${SA_EMAIL}"
SA_FOUND="$(lookup 'value(email)' gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}")"
if [[ -z "${SA_FOUND}" ]]; then
  run gcloud iam service-accounts create "${SA_ID}" \
    --project="${PROJECT_ID}" \
    --display-name="GitHub Actions deployer" \
    --description="Impersonated via WIF by ${GITHUB_REPO} (environment ${GITHUB_ENVIRONMENT}) to deploy functions and rules. No keys."
  sa_visible() {
    gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" --format='value(email)' >/dev/null 2>&1
  }
  retry 12 5 sa_visible || die "service account ${SA_EMAIL} did not become visible"
else
  echo "    already exists"
fi
SA_DISABLED="$(lookup 'value(disabled)' gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}")"
if [[ "${SA_DISABLED}" == "True" || "${SA_DISABLED}" == "true" ]]; then
  run gcloud iam service-accounts enable "${SA_EMAIL}" --project="${PROJECT_ID}"
fi

# ---------------------------------------------------------------------------
# 5. Let ONLY the principal set impersonate the deployer
#    (adding a binding that already exists is a no-op)
# ---------------------------------------------------------------------------
log "Allowing ${WIF_MEMBER} to impersonate ${SA_EMAIL}"
retry 6 10 run gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="${WIF_MEMBER}" \
  --condition=None \
  --format=none \
  || die "could not add the workloadIdentityUser binding"

echo "    Current IAM policy ON the deployer SA (who may act as it). Expect exactly one"
echo "    member: the principalSet above with roles/iam.workloadIdentityUser."
gcloud iam service-accounts get-iam-policy "${SA_EMAIL}" --project="${PROJECT_ID}" \
  --flatten='bindings[].members' --format='table(bindings.role, bindings.members)'
SA_POLICY_ROWS="$(gcloud iam service-accounts get-iam-policy "${SA_EMAIL}" --project="${PROJECT_ID}" \
  --flatten='bindings[].members' --format='csv[no-heading](bindings.role,bindings.members)')"
OTHER_IMPERSONATORS="$(printf '%s\n' "${SA_POLICY_ROWS}" \
  | grep -E '^roles/iam\.(workloadIdentityUser|serviceAccountTokenCreator|serviceAccountUser|serviceAccountKeyAdmin|serviceAccountAdmin),' \
  | grep -vxF "roles/iam.workloadIdentityUser,${WIF_MEMBER}" || true)"
if [[ -n "${OTHER_IMPERSONATORS}" ]]; then
  echo "    WARNING: these bindings on the SA also let someone act as (or manage) the deployer:"
  printf '%s\n' "${OTHER_IMPERSONATORS}" | sed 's/^/      /'
  echo "    Remove them unless intended (gcloud iam service-accounts remove-iam-policy-binding ...)."
fi

# ---------------------------------------------------------------------------
# 6. What the deployer may do: exactly what
#      firebase deploy --only functions,firestore:rules,storage --non-interactive --force
#    needs (worked out from firebase-tools 15.34.0's source). Deliberately NOT
#    granted directly: enabling or disabling APIs, reading Firestore or
#    Storage data, reading secret values, or changing project IAM.
#
#    That is not a sandbox: deploying functions means running code as their
#    runtime service account, and deploying rules can open up any data. Anyone
#    who can get a deploy token effectively has what that account has. The
#    real boundary is who can get a token (this repo's production environment
#    on main), so keep push access to main tight.
# ---------------------------------------------------------------------------
CUSTOM_ROLE_ID="firebaseDeployExtras"
# firebase.projects.get: the deploy reads the project's Firebase config. The
#   predefined roles that include it can also read Firestore and Storage data.
# run.services.setIamPolicy: makes a NEW callable function publicly callable.
#   Without it a new function is created but stays private, and later deploys
#   don't repair that.
CUSTOM_ROLE_PERMISSIONS="firebase.projects.get,run.services.setIamPolicy"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

log "Custom role ${CUSTOM_ROLE_ID} (${CUSTOM_ROLE_PERMISSIONS})"
ROLE_NAME="$(lookup 'value(name)' gcloud iam roles describe "${CUSTOM_ROLE_ID}" --project="${PROJECT_ID}")"
if [[ -z "${ROLE_NAME}" ]]; then
  run gcloud iam roles create "${CUSTOM_ROLE_ID}" --project="${PROJECT_ID}" \
    --title="Firebase deploy extras" \
    --description="GitHub Actions deployer: read the Firebase project config; make new callable functions public." \
    --permissions="${CUSTOM_ROLE_PERMISSIONS}" --stage=GA --format=none
else
  if [[ "$(gcloud iam roles describe "${CUSTOM_ROLE_ID}" --project="${PROJECT_ID}" --format='value(deleted)')" =~ ^([Tt]rue)$ ]]; then
    echo "    soft-deleted; restoring it"
    run gcloud iam roles undelete "${CUSTOM_ROLE_ID}" --project="${PROJECT_ID}" --format=none
  fi
  echo "    already exists; re-applying it (also re-enables it if it was disabled)"
  run gcloud iam roles update "${CUSTOM_ROLE_ID}" --project="${PROJECT_ID}" \
    --title="Firebase deploy extras" \
    --description="GitHub Actions deployer: read the Firebase project config; make new callable functions public." \
    --permissions="${CUSTOM_ROLE_PERMISSIONS}" --stage=GA --format=none
fi

PROJECT_ROLES=(
  roles/cloudfunctions.developer         # create/update/list functions, upload their source
  roles/serviceusage.serviceUsageConsumer # call APIs on this project; check that they're enabled
  roles/firebaserules.admin              # test and release firestore.rules and storage.rules
  roles/firebasestorage.viewer           # find the default Storage bucket (no access to files)
  "projects/${PROJECT_ID}/roles/${CUSTOM_ROLE_ID}"
)
# "TARGET_SA_EMAIL ROLE": the deployer must be able to run functions as their
# runtime service account (and as the build service account).
SA_ROLE_GRANTS=(
  "${COMPUTE_SA} roles/iam.serviceAccountUser"
)

# Projects created before mid-2024 may still build functions with the legacy
# Cloud Build service account; the deployer needs to act as that one too.
log "Default Cloud Build service account"
BUILD_SA="$(gcloud builds get-default-service-account --project="${PROJECT_ID}" \
  --format='value(serviceAccountEmail)' 2>/dev/null || true)"
BUILD_SA="${BUILD_SA##*/}"
if [[ -z "${BUILD_SA}" ]]; then
  echo "    WARNING: couldn't read it. If deploys fail with an actAs error for"
  echo "    ${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com, grant the deployer"
  echo "    roles/iam.serviceAccountUser on that account."
elif [[ "${BUILD_SA}" == "${COMPUTE_SA}" ]]; then
  echo "    ${BUILD_SA} (the runtime account; already covered)"
else
  echo "    ${BUILD_SA}"
  SA_ROLE_GRANTS+=("${BUILD_SA} roles/iam.serviceAccountUser")
fi

log "Role grants for ${SA_EMAIL}"
for role in "${PROJECT_ROLES[@]}"; do
  # A brand-new custom role can take a few seconds to become grantable.
  retry 6 10 run gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" --role="${role}" --condition=None --format=none \
    || die "could not grant ${role}"
done
for grant in "${SA_ROLE_GRANTS[@]}"; do
  read -r target_sa role <<<"${grant}"
  retry 6 10 run gcloud iam service-accounts add-iam-policy-binding "${target_sa}" --project="${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" --role="${role}" --condition=None --format=none \
    || die "could not grant ${role} on ${target_sa}"
done

echo "    Project roles the deployer now holds:"
gcloud projects get-iam-policy "${PROJECT_ID}" --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:${SA_EMAIL}" --format='value(bindings.role)' \
  | sed 's/^/      /'

# The deployer can run code as the functions' runtime account, so whatever that
# account can do is what a deploy can reach.
log "What the functions' runtime account (${COMPUTE_SA}) can do"
COMPUTE_ROLES="$(gcloud projects get-iam-policy "${PROJECT_ID}" --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:${COMPUTE_SA}" --format='value(bindings.role)')"
printf '%s\n' "${COMPUTE_ROLES:-    (no project roles)}" | sed 's/^/      /'
if grep -qxE 'roles/(editor|owner)' <<<"${COMPUTE_ROLES}"; then
  echo "    WARNING: it has broad project access (Editor or Owner), and so, through"
  echo "    deploys, does CI. Consider giving the functions a dedicated runtime"
  echo "    service account with only what they need (see TODO.md)."
fi

# ---------------------------------------------------------------------------
# 7. Values for .github/workflows/ci.yml
# ---------------------------------------------------------------------------
log "Done. Values for the workflow (not secrets; safe to commit):"
echo "    workload_identity_provider: ${PROVIDER_NAME}"
echo "    service_account:            ${SA_EMAIL}"
echo
echo "    Provider as stored by Google:"
gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
  --project="${PROJECT_ID}" --location=global --workload-identity-pool="${POOL_ID}" \
  --format='yaml(name,state,disabled,oidc.issuerUri,attributeCondition,attributeMapping)'
echo
echo "    New pools, providers and IAM bindings can take up to 5 minutes to take effect."
