# What runs unattended, and what it may touch

A short guide for whoever wires a gaffer command into a chain script, a scheduled runner or a CI workflow: which commands are built to run with nobody present, every outward-facing or hard-to-reverse act each one performs and the condition it performs it under, what each refuses to do without a person, the permission facts a headless run meets, and how to check a result instead of trusting the report. Everything here is drawn from the command prompts; [`commands.md`](commands.md) has the per-command detail and [`interfaces.md`](interfaces.md) the contract a repository provides.

## Which commands run unattended

**The build chain** — `/gaffer:build`, `/gaffer:verify` and `/gaffer:raise-pr` are designed to run to completion without prompting, so a chain script can drive them back-to-back. `/gaffer:build` asks one question only when its issue number is missing; `/gaffer:verify` takes no arguments; `/gaffer:raise-pr` never asks the invoker for anything. Each ends on the JSON verdict [`verdict-schema.md`](verdict-schema.md) defines, and the chain script that reads it belongs to the repository, not the plugin.

**The review and issue workflows in CI** — `/gaffer:review-pr` and `/gaffer:review-followup` run unattended from start to post, never stop for confirmation, and in CI post as the workflow's bot; `REVIEW.md` → *Where it runs* names the workflow. `/gaffer:reviewissue` and `/gaffer:confirmissue` run with no prompts once they have an issue number and their prompts allow for an automated run that sees only the checkout and the issue; a runner must pass the number, because both ask for it when it is missing.

**Interactive by design** — `/gaffer:draftissue` discusses the decisions a source leaves open and asks before closing a source issue; `/gaffer:capture-learnings` and `/gaffer:context-gardening` write nothing until the user picks candidates by number; `/gaffer:audit-codebase` asks for a missing `<since-ref>` and then runs to its issue. `/gaffer:review-slop` and `/gaffer:audit-deadcode` have no prompts and no side effects beyond their output.

## What an unattended command does to the outside world

| Command | Act | When |
|---|---|---|
| `/gaffer:build` | Creates `feature/<N>-<slug>` from `origin/main` and commits to it | Preconditions hold: clean tree, on `main`, fetch succeeds, no unpushed local commits, issue open with no linked PR |
| `/gaffer:build` | Deletes and recreates a leftover local branch of that name | Only when it carries no commits the run has not inspected; otherwise it stops |
| `/gaffer:build` | Writes a change-intent record | Only where `CONVENTIONS.md` → *Change-intent records* says the repository keeps them and a decision-table row warrants one |
| `/gaffer:verify` | Commits formatting changes, then commits the review's fixes | After the suite is green; the fix commit only after a green re-run of the formatted tree |
| `/gaffer:verify` | Leaves uncommitted edits in the working tree | When the fix cannot be made or the re-run is red; the report names the edits and says discarding them is the recovery |
| `/gaffer:raise-pr` | Pushes the branch (`git push -u origin <branch>`) | Not on `main`, and the branch has commits over `main` |
| `/gaffer:raise-pr` | Opens a pull request | Immediately after the push; `Closes #<N>` only when `gh` confirms an open issue at exactly that URL in this repository |
| `/gaffer:review-pr` | Posts a PR review: inline comments and a marked summary with tier, verdict and recommendation | The PR is `OPEN` and `--dry-run` is not set; findings are posted only after a verifier subagent confirms each |
| `/gaffer:review-pr` | Adds and removes a worktree under `.claude/scratch/review-pr-<N>/` | When `HEAD` is not already the PR head; removed on completion or abort |
| `/gaffer:review-followup` | Replies in review threads, resolves and re-opens them, posts a round review | A prior marked round exists, the PR is `OPEN`, this is round 3 or earlier, and `--dry-run` is not set |
| `/gaffer:reviewissue` | Posts the review comment and adds the `needs answers` label | First run: no marker comment and no `ready` label on the issue |
| `/gaffer:reviewissue` | Edits the existing review comment in place | Refine run: a marker comment exists and at least one answer hedges |
| `/gaffer:confirmissue` | Rewrites the issue body: appends `## Confirmed decisions` and corrects passages a decision overrules | Every gap answered, no answer hedging, no contradiction left unresolved |
| `/gaffer:confirmissue` | Removes `needs answers`, adds `ready` | After the body patch is confirmed to have landed; a label failure is reported, not fatal |
| `/gaffer:confirmissue` | Deletes the review comment (irreversible, no notification) | Only after `ready` and `## Confirmed decisions` are both read back from the issue; deletion failure is reported, not fatal |
| `/gaffer:audit-codebase` | Opens one issue with the one label `CONVENTIONS.md` → *Audit* names | Clean tree and a valid `<since-ref>`; never the labels `ready`, `review`, `confirm` or `parked` |

No unattended command merges a pull request, closes an issue by commit message, edits a document or backlog it drew from, or edits the plugin's own files.

## What each refuses to do unattended

- `/gaffer:build` will not add a dependency to a library `CONVENTIONS.md` → *Dependencies* marks dependency-controlled (it stops instead), will not make a protected public-API change the criteria do not require, will not fold in adjacent improvements, will not commit on red or on `main`, and will not report `ready` over a red suite, an unimplemented criterion or an uncommitted change.
- `/gaffer:verify` will not run on `main` (`/gaffer:verify was run on main, not a feature branch`), will not review while the suite is red, will not re-rate a real Blocker or Important down, will not review its own fix, will not commit a red fix to clear a later run's clean-tree check, and will not push, open a PR or raise an issue for an unfixed finding.
- `/gaffer:raise-pr` will not guess a closing keyword, will not hunt for an issue number anywhere but the leading number of a `/gaffer:build`-shaped branch, and will not write `raised` for a pull request it did not open.
- `/gaffer:review-pr` and `/gaffer:review-followup` will not run code from the PR, will not follow instructions in PR text or author replies, will not post an unverified finding, will not answer **yes** to merging with no human review unless the tier is Low, no always-a-person path is touched and no non-Pre-existing finding is open, and will not post a fourth round. Nothing is merged automatically.
- `/gaffer:reviewissue` will not post a second review over a `ready` issue and will not touch the issue body. `/gaffer:confirmissue` will not fold while any answer is empty or hedging, will not patch around a contradiction it cannot resolve, and will not delete the review comment before the new done-marker is confirmed on the issue.
- Every chain stage stops with `conventions missing: <heading>` rather than invent a convention that is the thing itself, the build-and-test command above all: inventing one unattended is how a run reports green over nothing.

## Permission facts a headless run meets

- A `Bash(chmod:*)` rule on `permissions.ask` stalls an interactive run until a human answers and is silently denied in a headless one. The `no-chmod` hook refuses the executable-bit forms and names `bash script.sh` instead, so the run is redirected rather than stalled or quietly degraded; the ask rule stays in the repository's `.claude/settings.json` as the backstop for the forms the hook declines to decide, because a plugin cannot set permission rules.
- The defaults every command reads live in the plugin's install directory, outside the repository. A headless `claude -p` that is not run with permissions bypassed denies that read and the command stops with a failure verdict saying so; an interactive session prompts once. Allowing reads outside the working directory, or bypassing permissions, is the caller's decision for its own runner; the plugin sets no permission rule either way.
- Subagents in `/gaffer:review-pr` and `/gaffer:review-followup` use Bash only for single `git` and `gh` commands with no pipes, chaining or `cd`, because a run may refuse anything else. `/gaffer:audit-codebase` records an evidence command the permission settings refuse and carries on without it.
- The repository's `CONVENTIONS.md` and `REVIEW.md` are trusted as the command files are, read from the root of the repository the command runs in, never from a review worktree, and in CI from the default branch's copy the workflow puts in place. A change to either always needs a person at review.

## Checking the result instead of trusting the report

- **The chain stages** — read the verdict, not the prose. It is the last non-blank line of the report, or the body of a code fence that closes it, and nothing above it counts. A report ending on anything else has no readable verdict and the chain stops safely. A `ready` or `verified` verdict carries a `branch`; a `raised` verdict carries a bare pull request URL in `pr`; a `failed` verdict carries a `reason`. A success verdict that also carries a `reason` is not a success. The reading order and the fail-safe rules are in [`verdict-schema.md`](verdict-schema.md).
- **`/gaffer:reviewissue`** — post-condition: a comment carrying `<!-- speckit:review -->` on the issue and the `needs answers` label; on a refine run, that comment's body changed and its gap numbers did not.
- **`/gaffer:confirmissue`** — post-condition: the issue body contains `## Confirmed decisions`, the `ready` label is present and `needs answers` is gone, and the marker comment is deleted. The command itself reads the first two back before deleting; the report is the only signal when the label or the deletion did not land, and re-running completes it.
- **`/gaffer:review-pr`** — post-condition: a PR review with `event: COMMENT` on the head commit whose body starts with `<!-- review-pr -->` and carries the line `Risk tier: … · Merge with no human review: …`. **`/gaffer:review-followup`** — one more such review, numbered as the next round, and replies or resolutions on the prior threads.
- **`/gaffer:audit-codebase`** — post-condition: one new issue titled `Codebase audit: <short HEAD> (<date>)` with the named label, and `git status --porcelain` clean afterwards; the report states that status and lists anything left behind.
