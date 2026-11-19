# Shared helpers, sourced by the step scripts.

set -euo pipefail

BRANCH_PREFIX="errilo/fix-"

skip() { echo "::notice::Skipped: $1"; echo "proceed=false" >> "$GITHUB_OUTPUT"; exit 0; }
fail() { echo "::error::$1"; exit 1; }

# Sets ISSUE_ID and BRANCH from RAW_ISSUE_ID, after checking it is a positive integer: it is the
# only value of the alert used, and it ends up in a branch name and a prompt.
require_issue_id() {
  [[ "${RAW_ISSUE_ID:-}" =~ ^[1-9][0-9]{0,15}$ ]] || fail "issue-id must be a positive integer, got '${RAW_ISSUE_ID:-}'."
  ISSUE_ID="$RAW_ISSUE_ID"
  # shellcheck disable=SC2034 # used by the step scripts
  BRANCH="$BRANCH_PREFIX$ISSUE_ID"
}

require_errilo_url() {
  [[ "${ERRILO_URL:-}" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || fail "errilo-url must be an https origin, without a path."
}

require_errilo_org() {
  [[ "${ERRILO_ORG:-}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail "errilo-org is missing or is not an organization slug."
}

require_errilo_token() {
  [ -n "${ERRILO_TOKEN:-}" ] || fail "errilo-token is missing (an Errilo project token, usually secrets.ERRILO_TOKEN)."
}

require_max_prs() {
  [[ "${MAX_PRS_PER_DAY:-}" =~ ^[0-9]{1,4}$ ]] || fail "max-prs-per-day must be a number."
}

# Number of auto-fix pull requests opened in the last 24 hours, in any state.
prs_opened_last_24h() {
  local since
  since=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
  gh api "repos/$GH_REPO/pulls?state=all&sort=created&direction=desc&per_page=100" \
    --jq "[.[] | select((.head.ref | startswith(\"$BRANCH_PREFIX\")) and .created_at >= \"$since\")] | length"
}
