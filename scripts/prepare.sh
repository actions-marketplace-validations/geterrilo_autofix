# Step "prepare": writes the agent's MCP configuration and CI instructions, and the arguments for
# anthropics/claude-code-action. Runs before the agent, with a read-only token.
# shellcheck source=lib.sh
source "$GITHUB_ACTION_PATH/scripts/lib.sh"

require_issue_id
require_errilo_url

dir="$RUNNER_TEMP/errilo"
mkdir -p "$dir"
mcp_config="$dir/mcp.json"
instructions="$dir/ci.md"
summary="$dir/summary.md"

# The token is not written here: the agent reads ${ERRILO_TOKEN} from its environment.
jq -n --arg url "$ERRILO_URL/mcp" \
  '{mcpServers: {errilo: {type: "http", url: $url, headers: {Authorization: "Bearer ${ERRILO_TOKEN}"}}}}' \
  > "$mcp_config"

cat > "$instructions" <<EOF
You run in a GitHub Actions workflow, without anyone to answer questions. Steps 5 to 7 of the
fix_issue method change here, because the workflow opens the pull request itself:

- Do not push, do not open a pull request, do not call add_comment or update_issue.
- Commit the fix (the test and the code change) on a local branch named $BRANCH, created from
  origin/$DEFAULT_BRANCH without tracking (git switch --no-track -c $BRANCH origin/$DEFAULT_BRANCH).
  If you worked from the release commit, apply the fix on top of origin/$DEFAULT_BRANCH and check
  that the test still passes.
- Do not change files under .github/.
- Write the pull request description, in Markdown, to $summary: the diagnosis, the fix and the
  test you added, in a few lines. The workflow copies it into the pull request and into an Errilo
  comment.
- If you cannot reproduce or fix the error, or the fix is uncertain, do not create the branch:
  write the reason to $summary and stop.
EOF

read_tools="mcp__errilo__get_issue,mcp__errilo__get_event,mcp__errilo__get_tag_distribution,mcp__errilo__get_release,mcp__errilo__search_issues,mcp__errilo__list_projects"

{
  # The fix_issue prompt of the Errilo MCP server: read, check out the release commit, reproduce
  # with a failing test, fix.
  echo "prompt=/mcp__errilo__fix_issue $ISSUE_ID"
  echo "mcp-config=$mcp_config"
  echo "instructions=$instructions"
  echo "claude-args<<ERRILO_EOF"
  echo "--mcp-config $mcp_config"
  echo "--append-system-prompt-file $instructions"
  echo "--add-dir $dir"
  echo "--allowedTools $read_tools"
  echo "--disallowedTools mcp__errilo__update_issue,mcp__errilo__add_comment"
  echo "ERRILO_EOF"
} >> "$GITHUB_OUTPUT"
