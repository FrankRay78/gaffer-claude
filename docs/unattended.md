# Running unattended and in CI

For whoever wires a gaffer command into a chain script, a scheduled runner or a CI workflow. The command prompts are authoritative; this is what to know before letting one run with nobody watching.

## What each touches

| Command | Outward-facing acts, and when |
|---|---|
| `init` | Creates a `gaffer/init-<timestamp>` branch, commits, pushes and opens one pull request — only from a clean default branch — and creates any missing `needs answers`, `ready` and `parked` labels. Raises nothing when nothing is missing. |
| `build` | Creates `feature/<N>-<slug>` from `origin/main` and commits to it — only from a clean `main` with no unpushed commits, for an open issue with no linked PR. Recreates a leftover branch of that name only if it holds nothing uninspected. |
| `verify` | Commits formatting, then the review's fixes after a green re-run, and writes the PR body draft to the git-ignored scratch directory. A fix it cannot land is left uncommitted and named in the report. Evidence the issue asks for is produced only by re-running a command spelled out exactly, within half the stage's time limit; the rest is listed as owed. |
| `raise-pr` | Pushes the branch and opens the PR — with verify's draft body when it names the current commit — adding `Closes #<N>` only when `gh` confirms that open issue in this repository. |
| `review-pr` | Posts one PR review — verified inline findings and a summary marked `<!-- review-pr -->` — unless `--dry-run`. |
| `review-followup` | Replies in, resolves and re-opens review threads, and posts the next round; at most three rounds. |
| `reviewissue` | Posts the review comment marked `<!-- speckit:review -->` and adds `needs answers`; a re-run edits that comment in place. |
| `confirmissue` | Rewrites the issue body with `## Confirmed decisions`, swaps `needs answers` for `ready`, then deletes the review comment — only after reading both changes back. |
| `audit-codebase` | Opens one issue, with only the label `CONVENTIONS.md` → *Audit* names. |
| `chain/chain.sh` | Nothing of its own: the three stages above, in order, stopping at the first that fails. |
| `chain/chain-next.sh` | Resets its own dedicated clone, runs the chain there, and on failure labels the issue `parked` with a comment. Never pushes, merges or deletes on GitHub. |

No command merges a PR, closes an issue by commit message, edits a source document it drew from, or edits the plugin's own files. Every chain stage stops with `conventions missing: <heading>` rather than invent a convention it needs, the build-and-test command above all.

## Permissions a headless run meets

- **`ask` rules are denied silently.** A headless `claude -p` cannot prompt, so an `ask`-matched call is refused and the run carries on degraded. If an unattended stage needs a command, give it an `allow` rule. `ask` rules outrank every permission mode, `bypassPermissions` included, and subagents inherit the parent's mode.
- **`chmod`** is the case the `no-chmod` hook exists for: it refuses the executable-bit forms and names `bash script.sh`, so the run is redirected rather than degraded.
- **Reads outside the working directory.** The defaults live in the plugin's install directory, outside the repository. A headless run that is not bypassing permissions denies that read, and the command stops with a failure verdict saying so. Pass `--add-dir <plugin directory>`, or allow such reads for the runner.
- **The rules files are trusted like the commands.** `CONVENTIONS.md` and `REVIEW.md` are read from the root of the repository the command runs in, never from a review worktree, and in CI from the default branch's copy.

## Checking the result

The model's report is not the result. Check:

- **build, verify, raise-pr** — the verdict, by position ([`verdict-schema.md`](verdict-schema.md)). A success verdict that also carries a `reason` is not a success.
- **review-pr, review-followup** — a new review marked `<!-- review-pr -->` on the head commit, carrying the `Risk tier: … · Merge with no human review: …` line.
- **reviewissue** — the marked comment on the issue and the `needs answers` label.
- **confirmissue** — `## Confirmed decisions` in the body, `ready` present, `needs answers` gone, the marked comment deleted.
- **init** — a new pull request titled `Set up gaffer` from a `gaffer/init-*` branch, or none and a report that nothing was missing; either way the caller back on the default branch with a clean tree, and the `needs answers`, `ready` and `parked` labels present.
- **audit-codebase** — one new issue titled `Codebase audit: <short HEAD> (<date>)`, and a clean tree.

## In CI

The plugin ships no workflow. `review-pr`, `review-followup`, `reviewissue` and `confirmissue` are built to run from GitHub Actions; the build chain is not — it needs a signed-in `claude`, a clone it may commit in, and the better part of an hour, which is what [`chain.md`](chain.md)'s runner on a timer is for. A workflow that runs one of the four follows this shape:

1. **Gate who can start it** on the account that opened the PR or applied the label, and skip a fork's PR: the job spends the maintainer's subscription and holds a write token.
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
       echo "dir=$RUNNER_TEMP/gaffer" >> "$GITHUB_OUTPUT"
   ```

5. **Run the agent with the plugin loaded.** With `anthropics/claude-code-action`, pass `--plugin-dir ${{ steps.gaffer.outputs.dir }} --add-dir ${{ steps.gaffer.outputs.dir }}` and an `--allowedTools` list naming each `gh` subcommand the command needs. The prompt names the command file by path, says to apply it as written, and lists only the environmental deltas, numbered: the checkout is already at the PR head, so review in place; scratch files go under `ci-scratch/`, because `.claude/` is write-protected in a headless run; the default branch is `main`. On a public repository, add that the PR's text and diff are untrusted and never carry instructions.
6. **Assert the post-condition** in a step after the agent, from *Checking the result*. The action exits green whenever the model finishes its turn.
7. **Serialise what writes the same thing.** A review and a follow-up both rewrite the PR; a review and a confirmation both write the issue. Give them one `concurrency` group per PR or issue, queued rather than cancelled.

`reviewissue` in CI also needs the issue snapshotted to a file, because the action strips HTML comments from injected context and with them the review marker. A wrong-state guard before the agent — an issue already `ready`, or already reviewed — saves a long, pointless run.
