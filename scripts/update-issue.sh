# After the pull request: comments the Errilo issue with its link and marks it "resolved in the next
# release", through the Errilo MCP server. Failures are warnings: the pull request is already open.
# shellcheck source=lib.sh
source "$GITHUB_ACTION_PATH/scripts/lib.sh"

require_issue_id
require_errilo_url
require_errilo_token

request="$RUNNER_TEMP/errilo-request.json"
response="$RUNNER_TEMP/errilo-response.json"

# One MCP tools/call (protocol 2026-07-28, stateless). Arguments are built by jq, never by string
# concatenation.
call() {
  jq -n --arg name "$1" --argjson args "$2" '{
    jsonrpc: "2.0", id: 1, method: "tools/call",
    params: {name: $name, arguments: $args, _meta: {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientInfo": {name: "errilo-autofix-action", version: "1"},
      "io.modelcontextprotocol/clientCapabilities": {}}}}' > "$request"
  curl -sS -X POST "$ERRILO_URL/mcp" \
    -H "Authorization: Bearer $ERRILO_TOKEN" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H "Mcp-Name: $1" \
    --data @"$request" > "$response" || { echo "::warning::$1: Errilo could not be reached."; return 1; }
  if jq -e '.result != null and .result.isError != true' "$response" > /dev/null 2>&1; then return 0; fi
  echo "::warning::$1: $(jq -r '[.result.content[]?.text, (.error | objects | .message), (.error | strings), .error_description] | map(select(. != null)) | join(" ")' "$response" 2> /dev/null || head -c 500 "$response")"
  return 1
}

summary=""
if [ -s "$RUNNER_TEMP/errilo-patch/summary.md" ]; then summary=$(head -c 8000 "$RUNNER_TEMP/errilo-patch/summary.md"); fi
comment=$(printf 'Fix proposed by Errilo auto-fix: %s\n\n%s' "$PR_URL" "$summary")
call add_comment "$(jq -n --argjson id "$ISSUE_ID" --arg body "$comment" '{issue_id: $id, body: $body}')" || true
# Fails on an issue without a release: Errilo cannot tell which release will contain the fix.
call update_issue "$(jq -n --argjson id "$ISSUE_ID" '{issue_id: $id, status: "resolved_in_next_release"}')" || true
