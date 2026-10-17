#!/usr/bin/env bash
# One-time, idempotent: restrict the GitHub environment "production" of
# Jeff-Stapleton/brookie_babies to deployments from the branch main only.
# Run once from the repository root: bash scripts/setup-github-production.sh
# Needs: gh auth login as a repo admin (classic token scope "repo").
#
# Between step 1 and step 2 no branch may deploy to production (a push to main
# landing in that window would fail its deploy jobs), so run it when nothing
# is being merged. Re-running it changes nothing.
set -euo pipefail

REPO="Jeff-Stapleton/brookie_babies"
ENV_NAME="production"
BRANCH="main"

log() { printf '\n==> %s\n' "$*"; }

command -v gh >/dev/null || { echo "gh not found: brew install gh" >&2; exit 1; }
gh auth status >/dev/null

# 1. "Selected branches and tags" (custom_branch_policies). Only PUT when not
#    already set: the PUT body below carries no reviewers or wait timer, and
#    the environment has none today.
log "Environment ${ENV_NAME}: deployment branches = selected branches"
if gh api "repos/${REPO}/environments/${ENV_NAME}" >/dev/null 2>&1; then
  CUSTOM="$(gh api "repos/${REPO}/environments/${ENV_NAME}" \
    --jq '.deployment_branch_policy.custom_branch_policies // false')"
else
  CUSTOM="missing"
fi
if [[ "${CUSTOM}" == "true" ]]; then
  echo "    already restricted to selected branches"
else
  echo "    current: ${CUSTOM}; setting custom_branch_policies=true"
  gh api --method PUT "repos/${REPO}/environments/${ENV_NAME}" \
    -H "Accept: application/vnd.github+json" \
    --input - --jq '.deployment_branch_policy' <<'JSON'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
fi

# 2. Allow exactly the branch "main" (type branch, so a tag named main doesn't match).
log "Deployment branch policy: ${BRANCH}"
EXISTING_ID="$(gh api --paginate "repos/${REPO}/environments/${ENV_NAME}/deployment-branch-policies" \
  --jq ".branch_policies[] | select(.name == \"${BRANCH}\" and .type == \"branch\") | .id")"
if [[ -n "${EXISTING_ID}" ]]; then
  echo "    already present (id ${EXISTING_ID})"
else
  gh api --method POST "repos/${REPO}/environments/${ENV_NAME}/deployment-branch-policies" \
    -H "Accept: application/vnd.github+json" \
    -f name="${BRANCH}" -f type=branch \
    --jq '{id, name, type}'
fi

# 3. Show the result. Expect exactly one policy: main / branch.
log "Result"
gh api "repos/${REPO}/environments/${ENV_NAME}" \
  --jq '{name, deployment_branch_policy, protection_rules: [.protection_rules[].type], can_admins_bypass}'
gh api --paginate "repos/${REPO}/environments/${ENV_NAME}/deployment-branch-policies" \
  --jq '.branch_policies[] | "    policy: \(.name) (\(.type))"'
OTHERS="$(gh api --paginate "repos/${REPO}/environments/${ENV_NAME}/deployment-branch-policies" \
  --jq ".branch_policies[] | select(.name != \"${BRANCH}\" or .type != \"branch\") | \"\(.id) \(.name) \(.type)\"")"
if [[ -n "${OTHERS}" ]]; then
  echo "WARNING: other branch/tag patterns can also deploy to ${ENV_NAME}:"
  printf '%s\n' "${OTHERS}" | sed 's/^/    /'
  echo "Delete with: gh api --method DELETE repos/${REPO}/environments/${ENV_NAME}/deployment-branch-policies/<id>"
fi

# OIDC subject format in use (informational; the Google-side trust does not use `sub`).
log "OIDC sub customization"
gh api "repos/${REPO}/actions/oidc/customization/sub"
echo
