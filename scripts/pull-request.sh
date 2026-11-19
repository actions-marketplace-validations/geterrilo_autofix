# Step "pull-request": no agent here. Pushes the agent's commits to errilo/fix-<id>, never to the
# default branch and never with --force, then opens the pull request.
# shellcheck source=lib.sh
source "$GITHUB_ACTION_PATH/scripts/lib.sh"

require_issue_id
require_errilo_org
require_errilo_url
require_max_prs
[ "$BRANCH" != "$DEFAULT_BRANCH" ] || fail "Refusing to push to the default branch."

patch_dir="$RUNNER_TEMP/errilo-patch"
compgen -G "$patch_dir/*.patch" > /dev/null || fail "No patch in the errilo-fix artifact."

# The cap again, just before opening: runs for different issues work in parallel.
opened=$(prs_opened_last_24h)
if [ "$opened" -ge "$MAX_PRS_PER_DAY" ]; then
  echo "::warning::Daily cap reached ($MAX_PRS_PER_DAY): the fix stays in the errilo-fix artifact of this run."
  exit 0
fi

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git switch --create "$BRANCH"
git am --3way "$patch_dir"/*.patch
# Without --force: if the branch appeared meanwhile, the push fails instead of replacing it.
git push origin "refs/heads/$BRANCH:refs/heads/$BRANCH"

link="$ERRILO_URL/$ERRILO_ORG/issues/$ISSUE_ID"
body="$RUNNER_TEMP/errilo-pr-body.md"
{
  if [ -s "$patch_dir/summary.md" ]; then cat "$patch_dir/summary.md"; echo; fi
  echo "---"
  echo "Opened by [Errilo auto-fix]($GITHUB_SERVER_URL/$GH_REPO/actions/runs/$GITHUB_RUN_ID) for [Errilo issue $ISSUE_ID]($link). Review it like any other change."
} > "$body"

if ! url=$(gh pr create --base "$DEFAULT_BRANCH" --head "$BRANCH" \
  --title "fix: Errilo issue $ISSUE_ID" --body-file "$body"); then
  # Remove the branch pushed above, otherwise the next run for this issue would skip it.
  git push origin --delete "$BRANCH" || true
  fail "Could not open the pull request. If GitHub Actions may not create pull requests, pass a fine-grained token or a GitHub App token as github-token (see the README). The fix is in the errilo-fix artifact of this run."
fi
echo "url=$url" >> "$GITHUB_OUTPUT"
echo "Pull request: $url" >> "$GITHUB_STEP_SUMMARY"
