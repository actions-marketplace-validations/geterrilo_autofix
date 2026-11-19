# Step "check": decides whether the issue should be fixed. No agent, read-only token.
# shellcheck source=lib.sh
source "$GITHUB_ACTION_PATH/scripts/lib.sh"

if [ "$EVENT_NAME" = "repository_dispatch" ]; then
  if [ "${IS_TEST:-}" = "true" ]; then skip "test alert received, the dispatch reaches this workflow."; fi
  # A spike is a known issue occurring more often: nothing new to fix.
  case "${TRIGGER:-}" in
    new_issue|regression) ;;
    *) skip "alert trigger '${TRIGGER:-}' is not new_issue or regression." ;;
  esac
fi

require_issue_id
require_errilo_token
require_errilo_org
require_errilo_url
require_max_prs

# Deduplication: one branch per issue. It exists while its pull request is open, and after it if
# the branch was not deleted.
refs=$(gh api "repos/$GH_REPO/git/matching-refs/heads/$BRANCH" \
  --jq "[.[] | select(.ref == \"refs/heads/$BRANCH\")] | length")
[ "$refs" = "0" ] || skip "branch $BRANCH already exists (pull request open, or branch not deleted after merge)."

opened=$(prs_opened_last_24h)
[ "$opened" -lt "$MAX_PRS_PER_DAY" ] || skip "$opened auto-fix pull requests in the last 24 hours (cap: $MAX_PRS_PER_DAY)."

# The issue, read with the project token: a 404 also covers an issue of another project.
issue_json="$RUNNER_TEMP/errilo-issue.json"
status=$(curl -sS -o "$issue_json" -w '%{http_code}' \
  -H "Authorization: Bearer $ERRILO_TOKEN" -H 'Accept: application/json' \
  "$ERRILO_URL/api/v1/organizations/$ERRILO_ORG/issues/$ISSUE_ID")
case "$status" in
  200) ;;
  404) skip "issue $ISSUE_ID not found in the project of the Errilo token." ;;
  401|403) fail "Errilo refused the token (HTTP $status)." ;;
  *) fail "Errilo answered HTTP $status." ;;
esac
issue_status=$(jq -r '.issue.status' "$issue_json")
[ "$issue_status" = "unresolved" ] || skip "issue $ISSUE_ID is $issue_status."

# Only dependency frames (node_modules, Node.js internals): nothing to fix in this repository.
# Same classification as the Errilo stack trace.
frames=$(jq -r '
  [(.latestEvent.exception // [])[].frames[]] as $frames
  | if ($frames | length) == 0 then "none"
    elif any($frames[];
      ((.filename // .absPath // "") as $path
       | ($path | test("(^|/)node_modules/") | not)
         and ($path | test("^(node:|internal/)") | not)
         and .inApp != false))
    then "app" else "dependencies" end' "$issue_json")
[ "$frames" != "dependencies" ] || skip "the stack trace only has dependency frames."

echo "issue-id=$ISSUE_ID" >> "$GITHUB_OUTPUT"
echo "proceed=true" >> "$GITHUB_OUTPUT"
echo "Errilo issue $ISSUE_ID will be fixed." >> "$GITHUB_STEP_SUMMARY"
