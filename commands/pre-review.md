---
description: Review the current branch's open pull request with /gaffer:review-pr --dry-run, fix what that review confirms once, push the fix, and mark the pull request ready if it was a draft. Posts no review. Runs unattended, so the chain can run it as the stage after raise-pr.
argument-hint: ""
---

Read `CLAUDE.md` for project context, and the conventions as *Repository conventions* below says, before proceeding.

`/gaffer:pre-review` runs the repository's own review over a pull request before that review is posted, and fixes what it finds while fixing is cheapest. It runs `/gaffer:review-pr --dry-run` against the current branch's open pull request, makes **one** fix pass over what that review confirms, pushes the fix once the suite is green, corrects the pull request body where a finding is about the body, and then marks the pull request ready for review if it was a draft. Marking it ready is what starts the repository's usual review, so the posted review then runs on a pull request whose verified findings are already dealt with.

It is the stage the chain runs after `/gaffer:raise-pr --draft` when a repository opts in ([`docs/chain.md`](../docs/chain.md)), and it runs the same way by hand: to pre-review a pull request you raised yourself, or to finish a draft a failed chain run left open. A pull request that is already ready for review stays as it is — only a draft is marked ready.

**It is not `/gaffer:verify`'s review.** Verify's reviewers ask generic quality questions of a branch before any pull request exists. This one asks the repository's own: `/gaffer:review-pr` judges against `REVIEW.md`. Both run; neither replaces the other.

**The fix pass runs once, and its fix is read on the pull request.** Do not review your own fix, here or by running the dry-run review again: `/gaffer:verify` reviewed its own fixes for up to four rounds once, and the later rounds only ever reviewed text the stage had just written. The posted review reads the fix commit, as it reads verify's.

**Nothing from this review reaches the posted one.** The dry run posts nothing — no review, comment, reply or label — and nothing it found is written to the pull request body, a commit message, a comment or a file the posted review reads. The posted review judges the pull request on what it sees, as verify's hand-off already requires. The one record of what this review found, fixed and left is this command's own report.

**Stop-on-failure is global:** if any step fails, STOP at that step, report it, and run no later step. A stop never marks the pull request ready, and never pushes anything the suite has not passed. Every stop report says what state the working tree is in, whether anything was pushed, and that the pull request is still a draft where it was one.

## Repository conventions

The steps in this file are generic. The conventions they run on live in two files, read section by section: the plugin's defaults in `${CLAUDE_PLUGIN_ROOT}/defaults/CONVENTIONS.md`, and the repository's own `CONVENTIONS.md` at the root of the repository this command runs in, written as additions to the defaults. Each step applies its own rule together with the two sections under the matching heading — the default first, then the repository's, which wins where they conflict, and stands alone where its first line is `Replaces the default.`. Wherever this file says `CONVENTIONS.md` → *Heading*, it means those two sections read that way. The headings this command reads:

| Heading | Supplies |
|---|---|
| `Build, test and format` | the formatter and the build-and-test command step 3 runs against the fix |
| `Commit messages` | the commit-message form step 3 uses |
| `Scratch files` | the git-ignored file step 4 writes a corrected body to |

A section under any other heading is read too, and applied where its text says. Where neither file has a heading, the step concerned runs on its generic rule alone, and the final report names each heading found in neither. A step whose convention is the thing itself — the command to run, the file to write — has no generic rule and no default, so where the repository supplies none the command STOPS rather than invent one, with the reason `conventions missing: <heading>`; the one exception is the formatter, whose default is none. The review criteria are `/gaffer:review-pr`'s, read by it from `REVIEW.md`. The harness itself is not a repository convention: the verdict protocol, whatever drives the chain by reading it, and the sibling commands stay named in the steps.

## Steps

**Every STOP below ends its report with the failure verdict, and nothing after it.** Where a step names the reason, report it verbatim; where it does not, write a short reason of your own that names the finding or the failing step. Whatever else the stop has to say goes *above* the verdict.

0. **Preconditions (before the review).** Each is a failure, so each STOPS with the failure verdict.
   - `git rev-parse --abbrev-ref HEAD` is not `main`. Reason: `/gaffer:pre-review was run on main, not a feature branch`.
   - `git status --porcelain` is empty. Reason: `the working tree has uncommitted changes`. A clean tree is what lets step 3 treat everything in it as the fix and nothing else.
   - `gh pr view --json number,url,state,isDraft,headRefName,headRefOid` names an open pull request for this branch. Reason: `no open pull request for this branch`.
   - `git rev-parse HEAD` equals the pull request's `headRefOid`, so the review reads exactly what is pushed, in this checkout, and the fix lands on top of it. Reason: `the branch and its pull request are at different commits`.

   Note whether the pull request is a draft (`isDraft`); step 5 reads it. Note `headRefOid` as the starting HEAD; step 3 reads it.

1. **Review, posting nothing.** Run `/gaffer:review-pr <number> --dry-run` in this session (the Skill tool, `gaffer:review-pr`), with the pull request's number, and follow it to its end. With HEAD at the pull request's head it reviews this checkout in place. `--dry-run` is not optional: the run must post no review, comment, reply or label, and if you see that it posted anything, STOP. Reason: `the dry-run review posted to the pull request`.

   From what it prints, take every **finding** (Critical or Major, verified) and every **note** (Minor or mechanical, verified), each with its `file:line`, claim and any **Pre-existing** tag. If the review stops before it composes a review, STOP with its reason.

   `/gaffer:review-pr` reads `REVIEW.md` from this checkout, so on a branch that edits `REVIEW.md` this review judges by the branch's copy where the posted review in CI uses the default branch's. The report says so when the branch touches it.

2. **Decide and fix.** The table is the only statement of what happens to an item:

   | Item | Outcome |
   |---|---|
   | Critical or Major finding | **Fix it** |
   | Mechanical note | **Fix it** |
   | Minor note | **Left** |
   | Anything tagged **Pre-existing** | **Left** |

   - **Fix it** — fix it in the working tree with the smallest change that removes the defect: correct the one fact, change the lines that misbehave, add the missing test where the finding is that a test is missing. Do not restructure around it; anything larger belongs in an issue of its own. Findings and notes were both verified by the review, so do not re-judge either, and do not re-rate a finding down or a mechanical note up to Minor. If one that must be fixed genuinely cannot be, STOP, naming it, and say that the edits already in the tree are uncommitted and unverified and that discarding them is the recovery.
   - **A finding about the pull request body** — missing evidence, an unstated breaking change, a body that disagrees with the diff — is fixed in the body, not the code: write the corrected body in full and hold it for step 4. Correct what the finding names and nothing else, and leave no trace of this review in it.
   - **Left** — not fixed and not carried anywhere: a Minor note needs the author's judgement, and a Pre-existing item is work the branch did not cause, so fixing it would fold an unrelated mission into the branch. Name each in the report.

   If a subagent this step starts errors, STOP.

3. **Verify, commit and push the fix.** If the tree is clean and `git rev-parse HEAD` still equals the starting HEAD from step 0, there is no fix commit: go to step 4. Otherwise — the tree is dirty, or something committed during steps 1–2 — every bullet below runs, and the commit bullet commits whatever is uncommitted:
   - **Format** with the project's formatter (`CONVENTIONS.md` → *Build, test and format*); skip where it names none. A non-zero exit ⇒ STOP. Reason: `formatting failed`.
   - **Run** the project's build-and-test command. Not green ⇒ STOP, with the failing suite as the reason, and say that the tree holds the fix uncommitted, that nothing was pushed, and that discarding the edits is the recovery — or, where HEAD has moved, resetting to the starting HEAD. Do not commit a red fix.
   - **Commit** whatever the tree holds with `git add -A`, immediately (skip where nothing is uncommitted), in the project's form (`CONVENTIONS.md` → *Commit messages*) — e.g. `Refs #<N>: apply pre-review findings`, with the issue number read off the branch name, and no prefix where it carries none. The message names no finding.
   - **Push** with `git push`. A failed push ⇒ STOP, saying that the fix is committed locally and not pushed.

   Do not review the commit you just made.

4. **Correct the body**, where step 2 held a corrected body. Write it to `pre-review-body.md` in the scratch directory (`CONVENTIONS.md` → *Scratch files*) with the native `Write` tool, never a shell heredoc, and run `gh pr edit <number> --body-file <scratch file>`. A failure ⇒ STOP; say what was pushed.

5. **Mark it ready**, only if step 0 found a draft: `gh pr ready <number>`. A failure ⇒ STOP, saying the fix is pushed and the pull request is still a draft. A pull request that was already ready is left alone.

## Final report

Report, in this order:

- The pull request, and whether it was a draft and is now ready.
- What the review found: the counts of findings by severity, of Minor notes and of mechanical notes, and the risk tier and no-human verdict it gave.
- What was fixed: each finding and mechanical note fixed, by `file:line` and claim; the fix commit, and that the suite passed against it; and whether the body was corrected. Or that there was nothing to fix and no commit was added.
- What was left: each Minor note, each Pre-existing item, and each mechanical note whose claim did not hold, by `file:line` and claim. This report is the only place they are recorded — do not raise an issue for one, write it to a file, or put it in the pull request.
- Whether the branch edits `REVIEW.md` (step 1).

**Close the report with the verdict as its last line** — one JSON object on one line, at column 1, nothing else on that line and nothing after it. Exactly one of:

- `{"schema": 1, "outcome": "pre-reviewed", "pr": "<url>"}` — the review ran, every item the table says to fix is fixed and pushed, and the pull request is ready for review.
- `{"schema": 1, "outcome": "failed", "reason": "<short reason>"}` — on any failure.

The schema is [`docs/verdict-schema.md`](../docs/verdict-schema.md) in the plugin (`${CLAUDE_PLUGIN_ROOT}/docs/verdict-schema.md`). Whatever drives the chain reads only what ends the report: nothing may follow the verdict; the `pr` URL must be bare, not an autolink or a markdown link; and nothing else may share the line. A code fence around the verdict is tolerated, a sentence after the fence is not.

Never report `pre-reviewed` over a red suite, an unfixed item the table says to fix, an unpushed commit, or a pull request still a draft.
