# Running unattended and in CI

For whoever wires a gaffer command into a chain script, a scheduled runner or a CI workflow. The command prompts are authoritative; this is what to know before letting one run with nobody watching.

## What each touches

| Command | Outward-facing acts, and when |
|---|---|
| `init` | None. It writes the setup files into the checkout as it stands, on whatever branch that is, and stages, commits and pushes nothing. With `--git-ignore` it adds lines to the clone's `.git/info/exclude` and changes no tracked file. It lists the states the commands need the tracker to have and says which are missing; it creates none. |
| `build` | Fast-forwards local `main` to `origin/main`, then creates `feature/<N>-<slug>` from it and commits to it — only from a clean `main` with no unpushed commits, for an open issue with no linked PR. Recreates a leftover branch of that name only if it holds nothing uninspected. |
| `verify` | Commits formatting, then the review's fixes after a green re-run, or after a failure that did not reproduce in a test file the branch left untouched, or whose file the output did not show, which the report names. A fix it cannot land is left uncommitted and named in the report. |
| `raise-pr` | Pushes the branch and opens the PR — as a draft when passed `--draft`, titled in the form `CONVENTIONS.md` → *Pull requests* names where it names one — adding the line that closes the issue (on GitHub `Closes #<N>`) only when the tracker's `pr-reference` confirms that open issue in this repository. |
| `pre-review` | Runs `review-pr --dry-run` on the current branch's open PR, posting nothing; commits and pushes its fix only after a green suite, edits the PR body where a finding is about the body, never the title, and marks the PR ready if it was a draft. A failure pushes nothing failing and leaves a draft a draft. |
| `review-pr` | Posts one PR review — verified Critical and Major findings inline, and a summary marked `<!-- review-pr -->` that also lists verified Minor observations as notes, split into Minor and mechanical — unless `--dry-run`. |
| `review-followup` | Replies in, resolves and re-opens review threads, and posts the next round; at most three rounds. |
| `reviewissue` | Posts the review comment carrying the tracker's review marker (on GitHub `<!-- speckit:review -->`) and puts the issue in `needs-answers` (on GitHub the label `needs answers`); a re-run edits that comment in place. |
| `confirmissue` | Rewrites the issue body with `## Confirmed decisions`, swaps `needs-answers` for `ready`, then deletes the review comment — only after reading both changes back. |
| `audit-codebase` | Opens one issue, in no tracker state. |
| `chain/chain.sh` | Nothing of its own: build, verify, raise-pr and pre-review, in order, stopping at the first that fails. |
| `chain/chain-local.sh` | Nothing of its own: the chain, then `review-pr` on the pull request it opened — only when that is the checked-out branch's pull request on origin's repository — which posts a review under the caller's `gh` account. Succeeds only on the review-pr post-condition below, met by a submitted review from that account. |
| `chain/chain-next.sh` | Resets its own dedicated clone, runs the chain there, and on failure labels the issue `parked` with a comment, naming any draft PR a failed pre-review left open. Never pushes, merges or deletes on GitHub. |

No command merges a PR, closes an issue by commit message, edits a source document it drew from, or edits the plugin's own files. Every chain stage stops with `conventions missing: <heading>` rather than invent a convention it needs, the build-and-test command above all.

## Permissions a headless run meets

- **`ask` rules are denied silently.** A headless `claude -p` cannot prompt, so an `ask`-matched call is refused and the run carries on degraded. If an unattended stage needs a command, give it an `allow` rule. `ask` rules outrank every permission mode, `bypassPermissions` included, and subagents inherit the parent's mode.
- **The tracker skill's calls.** A command reaches the tracker by loading the `gaffer:tracker` skill and making the calls it describes — on GitHub, `git remote get-url origin`, `gh repo view`, `gh issue`, `gh label` and `gh api` calls, and `jq`. Nothing allows them on a stage's behalf, `chain.sh` included: a headless run needs each one allowed by the repository's rules, the user's, or its `--allowedTools`, or the call is denied ([`tracker.md`](tracker.md) → *What a headless stage needs allowed*).
- **`chmod`** is the case the `no-chmod` hook exists for: it refuses the executable-bit forms and names `bash script.sh`, so the run is redirected rather than degraded.
- **Reads outside the working directory.** The defaults live in the plugin's install directory, outside the repository. A headless run that is not bypassing permissions denies that read, and the command stops with a failure verdict saying so. Pass `--add-dir <plugin directory>`, or allow such reads for the runner.
- **The rules files are trusted like the commands.** `CONVENTIONS.md` and `REVIEW.md` are read from the root of the repository the command runs in, never from a review worktree, and in CI from the default branch's copy.

## Checking the result

The model's report is not the result. Check:

- **build, verify, raise-pr, pre-review** — the verdict, by position ([`verdict-schema.md`](verdict-schema.md)). A success verdict that also carries a `reason` is not a success.
- **review-pr, review-followup** — a new review marked `<!-- review-pr -->` on the commit it reviewed (even where the pull request's head has moved since): count the marked reviews on that commit before the run and require one more after, since a round on an unchanged head finds the last round's review there already. The review carries the `Risk tier: … · Human review: …` line.
- **reviewissue** — the marked comment on the issue and the `needs answers` label.
- **confirmissue** — `## Confirmed decisions` in the body, `ready` present, `needs answers` gone, the marked comment deleted.
- **init** — the setup files in the working tree, uncommitted, or a report that nothing was missing; either way the branch, the history and the tracker untouched.
- **audit-codebase** — one new issue titled `Codebase audit: <short HEAD> (<date>)`, and a clean tree.

## In CI

The plugin ships no workflow. `review-pr`, `review-followup`, `reviewissue` and `confirmissue` are built to run from GitHub Actions — this repository's own [`review-pr.yml`](../.github/workflows/review-pr.yml) and [`review-followup.yml`](../.github/workflows/review-followup.yml) are working examples of the first two; the build chain is not — it needs a signed-in `claude`, a clone it may commit in, and the better part of an hour, which is what [`chain.md`](chain.md)'s runner on a timer is for. A workflow that runs one of the four follows this shape:

1. **Gate who can start it** on the account that opened the PR or applied the label, and skip a fork's PR: the job spends the maintainer's subscription and holds a write token. Trigger a review on `pull_request` events only, not `workflow_dispatch`: on a `pull_request` event `anthropics/claude-code-action` restores `.claude/` and `CLAUDE.md` from the base branch and refuses a fork, and on a dispatch it does neither, so the checkout's own hooks run with the secrets loaded. Re-run a failed review by re-running its run.

   A label Claude applies on the maintainer's request counts as the maintainer's, so one `@claude` comment can ask for a change and then the stage the label starts. Accept the Claude app's bot login (`claude[bot]`) as the label's sender alongside the maintainer's, and keep the PR-author gate and the fork rule as they are. That is safe only while two things hold, and the workflow should say so where it gates: the mention workflow answers only the maintainer's comments, and it is the only workflow that acts as the Claude app — every other workflow hands the action `github_token`, whose events start no workflow at all. A workflow that exchanges OIDC for the app's token, or a mention workflow that answers anyone's comments, widens the gate with it. What stays open is an injected label: one a mention run applies because text anyone can write — a PR body, another account's comment, an issue — asked for it. The stage still runs only where the other gates allow, on the default branch's commands and rules, so the cost is one unrequested run. Where the request is for a change and then a review, tell the mention run to push before it labels: the review reads the PR head when it starts.
2. **Check out** the PR head for a review (inline comments anchor to its lines), or the default branch for an issue.
3. **Put the default branch's rules in place**: `git show origin/main:REVIEW.md > REVIEW.md`, the same for `CONVENTIONS.md`, and remove the PR's copy where `main` has none — so a PR cannot write the rules it is judged by.
4. **Load gaffer from `main`**, in a step of its own, printing the commit. Nothing in the checkout may choose which gaffer runs:

   ```yaml
   - name: Load gaffer from its main
     id: gaffer
     run: |
       set -euo pipefail
       git clone -q --depth 1 --branch main https://github.com/FrankRay78/gaffer-claude.git "$RUNNER_TEMP/gaffer"
       echo "gaffer $(git -C "$RUNNER_TEMP/gaffer" rev-parse HEAD)"
       chmod -R a-w "$RUNNER_TEMP/gaffer"
       echo "dir=$RUNNER_TEMP/gaffer" >> "$GITHUB_OUTPUT"
   ```

   The clone is made read-only before the agent starts: `--add-dir` makes it one of the agent's working directories, and the plugin's hook runs from it on every Bash call, so a writable clone would let text the agent was handed get a script run with the job's token.

5. **Run the agent with the plugin loaded.** With `anthropics/claude-code-action`, pass `--plugin-dir ${{ steps.gaffer.outputs.dir }} --add-dir ${{ steps.gaffer.outputs.dir }}` and an `--allowedTools` list naming each `gh` subcommand the command needs, the tracker skill's among them ([`tracker.md`](tracker.md) → *What a headless stage needs allowed*). Nothing the agent may run should be able to write a file a later command reads as config: git's config names programs a later `git diff` runs, with the job's tokens in reach. Three settings hold that, and each closes a hole the others leave:
   - **`--permission-mode default`.** The action otherwise starts the agent in auto mode, where a safety review can pass a command no rule allows, so the list is a floor rather than a ceiling. In `default` mode what no rule allows is denied, because a workflow has no one to approve it.
   - **`Edit(./ci-scratch/*.json)` rather than a bare `Write`.** A bare `Write` rule lets the agent write any path the runner user can, outside the workspace too, `~/.config/git/config` among them. Name the files the command writes, flat and with an extension, as `*.json` and `*.md` are: a pattern that reaches subfolders, or names with no extension, lets the agent lay out a bare repository (`HEAD`, `config`, `objects/`) whose config a git call run inside it reads.
   - **`--disallowedTools "Bash(git *--output*)"`** where the list allows `Bash(git diff:*)`, `git log:*` or `git show:*`. All three take `--output=<path>`, which writes anywhere; the deny rule outranks the allow, and catches the option however it is quoted.

   None of the three limits what the agent can read. An allowed call can read any file the runner user can: `git diff <path> /dev/null` with a path outside the work tree, or `gh api -F body=@<path>`, which also posts it. That takes in `/proc/<pid>/environ`, where the job's token and `CLAUDE_CODE_OAUTH_TOKEN` are. So the tokens are only as safe as the text the agent reads: a pull request's text and diff, and in a follow-up the replies on its review threads, which anyone can post on a public repository. Where someone other than the maintainers can write that text, set `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: '1'` in the agent step's `env`, install `bubblewrap` in a step before it, and deny `Read(//proc/**)`. The scrub keeps the OAuth token out of every subprocess's environment and runs each in its own PID namespace; the deny rule covers the Read tool, which runs in Claude's own process. Check that the command's `gh` calls still work once you do.

   The prompt names the command file by path, says to apply it as written, and lists only the environmental deltas, numbered: the checkout is already at the PR head, so review in place; scratch files go under `ci-scratch/`, because `.claude/` is write-protected in a headless run; the default branch is `main`. On a public repository, add that the PR's text and diff are untrusted and never carry instructions.
6. **Assert the post-condition** in a step after the agent, from *Checking the result*. The action exits green whenever the model finishes its turn.
7. **Serialise what writes the same thing.** A review and a follow-up both rewrite the PR; a review and a confirmation both write the issue. Give them one `concurrency` group per PR or issue, queued rather than cancelled: `cancel-in-progress: false` and `queue: max`. Without `queue: max`, GitHub cancels a pending run when another joins the group, and a cancelled run that never started never runs its clean-up steps.

`reviewissue` in CI also needs the issue snapshotted to a file, because the action strips HTML comments from injected context and with them the review marker. A wrong-state guard before the agent — an issue already `ready`, or already reviewed — saves a long, pointless run.
