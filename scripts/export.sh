# Step "export": runs after the agent, in the same job. Exports the agent's commits as a patch, so
# that a job without agent pushes them. Refuses a branch not based on the default branch, and any
# change under .github/.
# shellcheck source=lib.sh
source "$GITHUB_ACTION_PATH/scripts/lib.sh"

require_issue_id

base="origin/$DEFAULT_BRANCH"
patch_dir="$RUNNER_TEMP/errilo-patch"
summary="$RUNNER_TEMP/errilo/summary.md"
mkdir -p "$patch_dir"
if [ -s "$summary" ]; then cp "$summary" "$patch_dir/summary.md"; fi

if ! git rev-parse --verify --quiet "refs/heads/$BRANCH" > /dev/null \
  || [ "$(git rev-list --count "$base..$BRANCH")" = "0" ]; then
  echo "::notice::No fix for issue $ISSUE_ID. The agent's reason is in the job summary."
  { echo "## No fix for Errilo issue $ISSUE_ID"; echo; cat "$patch_dir/summary.md" 2> /dev/null || true; } >> "$GITHUB_STEP_SUMMARY"
  echo "has-fix=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

git merge-base --is-ancestor "$base" "$BRANCH" || fail "$BRANCH is not based on $base."
if git diff --name-only "$base...$BRANCH" | grep -q '^\.github/'; then
  fail "The fix changes files under .github/: refused."
fi

git format-patch --binary --output-directory "$patch_dir" "$base..$BRANCH" > /dev/null
echo "has-fix=true" >> "$GITHUB_OUTPUT"
