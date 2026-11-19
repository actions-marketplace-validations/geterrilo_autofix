# Errilo Auto-fix

A GitHub Action that fixes production errors on its own. When [Errilo](https://errilo.com) reports a new issue or a regression, an AI agent ([Claude Code](https://github.com/anthropics/claude-code-action) by default) reads it through the Errilo MCP server, reproduces it with a failing test and fixes it. The action then opens a pull request and marks the issue "resolved in the next release" in Errilo.

```
Errilo alert ──repository_dispatch──▶ check ──▶ fix ──────────────────────────▶ pull-request ──▶ Errilo issue
                                        │        prepare → agent → export        pushes errilo/fix-<id>   comment +
                                        │        read-only token                 opens the PR             resolved in next release
                                        └─ skips: test alert, spike, branch exists, daily cap,
                                           issue not unresolved, dependency-only stack trace
```

If the error comes back once the fix is deployed, Errilo reopens the issue as a regression and alerts again, which starts a new run.

The agent is yours, on your Anthropic account (or another agent that supports MCP). Errilo charges nothing for the MCP server or for this action, on every plan.

## Why three jobs

The agent reads text that comes from your users: error messages, breadcrumbs, tags. So it never holds a token that can write to your repository. The action runs in three jobs, each with its own permissions:

| Step           | Job          | GitHub token | What it does                                                                    |
| -------------- | ------------ | ------------ | ------------------------------------------------------------------------------- |
| `check`        | check        | read         | Decides whether the issue should be fixed. No agent.                            |
| `prepare`      | fix          | read         | Writes the agent's MCP configuration and instructions.                          |
| `export`       | fix          | read         | After the agent: exports its local commits as a patch artifact.                 |
| `pull-request` | pull-request | write        | No agent. Pushes `errilo/fix-<id>`, opens the PR, comments the Errilo issue.    |

## Usage

Copy [`examples/errilo-autofix.yml`](examples/errilo-autofix.yml) to `.github/workflows/errilo-autofix.yml` on your **default branch** (GitHub only starts `repository_dispatch` workflows from there), and replace the setup steps of the `fix` job with your project's:

```yaml
- uses: geterrilo/autofix@v1
  with:
    step: check
    errilo-token: ${{ secrets.ERRILO_TOKEN }}
    errilo-org: ${{ vars.ERRILO_ORG }}
```

The agent needs to install your dependencies and run your tests: without a working test setup, it cannot reproduce the error and stops.

## Setup

You need an Errilo project that receives errors from your app, admin access to the GitHub repository, and either an [Anthropic API key](https://console.anthropic.com/settings/keys) or a Claude subscription (Pro or Max).

### 1. Send releases with their commit

The agent fixes the code at the version that crashed. Errilo knows that version when your SDK sends a `release` and the release has a commit:

- a release that is a commit SHA (`release: process.env.GIT_SHA`) is enough;
- otherwise, run `sentry-cli releases set-commits <release> --auto` against Errilo when you deploy.

Without a release, the agent works from the default branch, and Errilo cannot mark the issue "resolved in the next release" (the pull request is still opened).

### 2. Create an Errilo token for the project

In Errilo, **Settings → API tokens → New token**: limited to the project of this repository, scopes `issues:read` and `issues:write`. The token only sees this project.

### 3. Secrets and variables

In the repository, **Settings → Secrets and variables → Actions**:

| Name                          | Kind     | Value                                                                                             |
| ----------------------------- | -------- | ------------------------------------------------------------------------------------------------- |
| `ANTHROPIC_API_KEY`           | Secret   | Your Anthropic API key. Or `CLAUDE_CODE_OAUTH_TOKEN`, created with `claude setup-token`, passed as `claude_code_oauth_token`. |
| `ERRILO_TOKEN`                | Secret   | The token from step 2.                                                                            |
| `ERRILO_ORG`                  | Variable | Your organization slug: the first path segment of your Errilo URLs (`app.errilo.com/<slug>/...`). |
| `ERRILO_AUTOFIX_GITHUB_TOKEN` | Secret   | Recommended. See "Pull request token" below.                                                      |

Also turn on **Settings → General → Automatically delete head branches**. The action skips an issue while its `errilo/fix-<id>` branch exists, so a branch left after a merge would block the next attempt on a regression.

#### Pull request token

By default, the `pull-request` step uses the workflow's `GITHUB_TOKEN`. It has two limits:

- GitHub refuses to let it open pull requests ("GitHub Actions is not permitted to create or approve pull requests") unless **Settings → Actions → General → Allow GitHub Actions to create and approve pull requests** is on, in the repository and, for an organization, in the organization's settings first;
- GitHub does not start workflows for a pull request it opened, so your CI does not run on the fix.

Pass an `ERRILO_AUTOFIX_GITHUB_TOKEN` secret as `github-token` to avoid both: a fine-grained token on this repository only, with **Contents** and **Pull requests** in read and write, or a GitHub App token. Only the `pull-request` job receives it, never the agent.

### 4. Connect the Errilo alert

Create a fine-grained personal access token on GitHub: **only this repository**, permission **Contents: read and write** (required by GitHub to send a `repository_dispatch`), short expiry. For a repository of an organization, choose the organization as **Resource owner**, and check that an organization admin approved the token if the organization requires it. Otherwise GitHub answers 404 and Errilo shows "The service responded 404".

In Errilo, open the project, then **Alerts → Create a rule**, channel **GitHub**: the repository (`owner/name`), the token, and the triggers **New issue** and **Regression**. Spikes are ignored.

Click **Send a test alert**: a run appears in the Actions tab and stops at once with "test alert received". The wiring works.

### 5. Try it on one issue

**Actions → Errilo auto-fix → Run workflow**, with the id of an issue (the number at the end of its Errilo URL). The run opens a pull request named `fix: Errilo issue <id>`, and the issue shows a comment with the link and the status "resolved in the next release".

## Inputs

| Input             | Steps                 | Default                                   | Description                                                                 |
| ----------------- | --------------------- | ----------------------------------------- | --------------------------------------------------------------------------- |
| `step`            | all                   | required                                  | `check`, `prepare`, `export` or `pull-request`.                              |
| `errilo-token`    | check, pull-request   |                                           | Errilo project token, scopes `issues:read` and `issues:write`.               |
| `errilo-org`      | check, pull-request   |                                           | Errilo organization slug.                                                    |
| `errilo-url`      | all                   | `https://app.errilo.com`                  | Errilo origin, without a path.                                               |
| `issue-id`        | all                   | the alert's, or `inputs.issue_id`         | For `prepare`, `export` and `pull-request`: the `issue-id` output of `check`. |
| `max-prs-per-day` | check, pull-request   | `3`                                       | Cap on auto-fix pull requests opened in 24 hours.                            |
| `github-token`    | check, pull-request   | `github.token`                            | Reads the repository (`check`), pushes and opens the PR (`pull-request`).    |

## Outputs

| Output             | Step         | Description                                                                         |
| ------------------ | ------------ | ----------------------------------------------------------------------------------- |
| `proceed`          | check        | `true` when the issue should be fixed.                                              |
| `issue-id`         | check        | The validated issue id.                                                             |
| `prompt`           | prepare      | The prompt for the agent: the `fix_issue` prompt of the Errilo MCP server.          |
| `claude-args`      | prepare      | Arguments for `anthropics/claude-code-action`: MCP config, instructions, tools.     |
| `mcp-config`       | prepare      | Path of the MCP configuration file, for another agent.                              |
| `instructions`     | prepare      | Path of the CI instructions to append to the agent's system prompt.                 |
| `has-fix`          | export       | `true` when the agent committed a fix.                                              |
| `pull-request-url` | pull-request | URL of the pull request opened.                                                     |

## Safeguards

- **Pull request only.** The agent runs with a read-only GitHub token: it cannot push or open a pull request. It commits on a local branch; `export` turns the commits into a patch, and the `pull-request` job, without agent, pushes them to `errilo/fix-<id>` (never with `--force`, never to the default branch) and opens the pull request. Protect your default branch as well.
- **No change to workflows.** A fix that touches `.github/` is refused.
- **One run per issue.** Errilo delivers alerts "at least once", so the same issue can arrive twice. Runs are grouped by issue id (`concurrency`), and `check` stops if the issue's branch already exists: a duplicate never opens a second pull request.
- **Daily cap.** At most `max-prs-per-day` pull requests (3 by default) in 24 hours, checked before the agent starts and again before the pull request is opened.
- **Untrusted payload.** The alert's `client_payload` contains text from production events (the issue title, the release). The action never writes it into a script: it reads the payload through environment variables, and only uses the issue id, after checking that it is a number.
- **Untrusted event content.** Error messages, breadcrumbs and tags come from your users, possibly from an attacker. The Errilo MCP server marks them as untrusted data, and the `fix_issue` prompt tells the agent never to follow instructions found in them. The read-only token and the review of the pull request limit what an injection could achieve.
- **Only your code.** No fix is attempted when the stack trace only has frames from `node_modules` or Node.js internals.
- **Only real issues.** Test alerts, spikes, and issues that are no longer unresolved (resolved, ignored) are skipped.
- **The agent can say no.** If it cannot reproduce the error with a failing test, or the fix is uncertain, no pull request is opened; the reason is in the run summary.

## Cost

With an API key, each run is billed by Anthropic according to the tokens used; follow it in the [Anthropic Console](https://console.anthropic.com/usage). With a subscription token, runs count toward your plan's usage limits. For scale: on a small demo bug (an unknown discount code that crashes a cart function), a run took 7 agent turns, 30 seconds, and $0.08. A real code base costs more: the agent reads more code and runs a longer test suite.

Three settings bound the cost: `max-prs-per-day`, `--max-turns` in `claude_args` (80 in the example), and the `timeout-minutes` of the `fix` job. Runs also use GitHub Actions minutes.

## Limits

- **Review every pull request.** The agent writes a test that reproduces the error, but a test that passes does not prove the fix is right.
- **Bots cannot trigger Claude Code.** `claude-code-action` only runs for a human GitHub user: the dispatch token must belong to a person, not a GitHub App.
- **One issue per run.** An alert that groups several issues sends one dispatch per issue (10 at most); each one starts its own run.
- **GitHub.com only.** Errilo sends `repository_dispatch` to `api.github.com`; GitHub Enterprise Server is not supported.

## Another agent

`check`, `export` and `pull-request` do not depend on the agent. To use another agent that supports MCP, give it the files from the `mcp-config` and `instructions` outputs of `prepare` (the agent reads `ERRILO_TOKEN` from its environment), the `prompt` output, and keep the read-only token. Choose the Claude model with `--model` in `claude_args`.

## Versions

`@v1` follows the latest `v1.x.y` release. Pin a full commit SHA if your policy requires it.

## License

[MIT](LICENSE)
