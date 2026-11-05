---
description: Orchestrator that turns "implementation looks done" into a reviewed, test-green branch with its pull request body drafted — runs the full suite first and hard-gates on it, reviews the branch once with the same review agents /gaffer:review-pr uses, fixes the confirmed findings its rules table calls for, checks those fixes once, commits them on a green re-run, then drafts and checks the PR body. Stops short of the pull request. Runs unattended, so it can drive a loop.
---

Read `CLAUDE.md` for project context, and the conventions and review criteria as *Repository conventions* below says, before proceeding.

`/gaffer:verify` is the stage between `/gaffer:build` and `/gaffer:raise-pr`: it turns a feature branch into a **formatted, test-green, reviewed, fully-committed** branch with a clean working tree, and a drafted **pull request body** that `/gaffer:raise-pr` opens the PR with. It does not push, open a PR, or merge — `/gaffer:raise-pr` owns all of that, and you run it yourself afterwards.

`/gaffer:verify` composes the project's existing commands behind one hard gate: **the full test suite gates everything downstream, and no review happens unless it is green.** The gate is structural — the review step is downstream of the step-1 exit code, so it cannot begin against un-verified or red code. Do not add a hook to police this ordering; the exit code *is* the gate. The one step that precedes the suite is formatting (step 1a), which is cosmetic and is itself covered by the gate that follows it.

**The aim is a pull request `/gaffer:review-pr` finds little or nothing on.** So Review A, here, judges the branch by the same standard Review B, on the PR, will: the same review agents, the same repository criteria, the same severity scale, and the same independent check that a finding is real before anything acts on it. What it deliberately leaves unfixed it says so in the PR body, with the reason, so a reader meets a stated trade-off rather than a surprise.

**The review is one round.** A fix written in response to a review is new code. Re-reviewing it in full inside `/gaffer:verify` was tried and fed itself (step 2 says how), so the fixes get one narrow check instead — for a Critical or Major problem the fix itself introduced, and nothing else (step 3) — and Review B reads the whole PR diff, fix commit included.

`/gaffer:verify` is designed to run to completion **without prompting**, so it can be driven by an automated loop (e.g. verifying many features back-to-back) as well as invoked directly. Reflection (`/gaffer:capture-learnings`) is deliberately **not** a step: it needs human curation and batches better across many features, so it belongs at a supervised checkpoint after a batch — not inside each verify, where it would either block the loop or be auto-skipped to nothing.

Raising the pull request is deliberately **not** a step either. It is the one irreversible, outward-facing act in the chain: everything `/gaffer:verify` does is safe to re-run, and pushing a branch and opening a PR is not. Keeping it a separate deliberate `/gaffer:raise-pr` invocation is what makes the rest of the chain freely repeatable. The body `/gaffer:verify` drafts sits in a git-ignored scratch file until then.

**Stop-on-failure is global:** if any step fails — the tree is dirty, a suite run is not green, the format tool errors, a review agent errors, a confirmed finding that must be fixed cannot be — STOP at that step, report it to the invoker, and do not run any later step. Every such report says what state the working tree is in: clean, or holding uncommitted edits, and whose they are.

## Repository conventions

The steps in this file are generic. The conventions they run on — the formatter, the build-and-test command, the commit-message form, the hooks and plugins around them, where scratch files go — live in two files, read section by section: the plugin's defaults in `${CLAUDE_PLUGIN_ROOT}/defaults/CONVENTIONS.md`, and the repository's own `CONVENTIONS.md` at the root of the repository this command runs in, written as additions to the defaults. Read both before step 0; each step then applies its own rule together with the two sections under the matching heading — the default first, then the repository's, which wins where they conflict, and stands alone where its first line is `Replaces the default.`. Wherever this file says `CONVENTIONS.md` → *Heading*, it means those two sections read that way. The headings this command reads:

| Heading | Supplies |
|---|---|
| `Build, test and format` | the formatter steps 1a and 3 run, and the build-and-test command steps 1b, 3 and 4 run |
| `Commit messages` | the commit-message form steps 1a and 3 use |
| `Hooks, scripts and plugins` | the pull-request hook step 1b weighs, the hooks that can block a commit, and the plugin the simplifier comes from |
| `Scratch files` | the git-ignored file step 4 writes the pull request body to |
| `Pull requests` | what the repository asks of a pull request body, which step 4 applies |
| `Change-intent records` | where the records step 4 links from the body live |

The review criteria are read the same way, from the plugin's `${CLAUDE_PLUGIN_ROOT}/defaults/REVIEW.md` and the repository's `REVIEW.md` — the same two files `/gaffer:review-pr` reads, so the two reviews hold the branch to one standard. Wherever this file says `REVIEW.md` → *Heading*, it means those two sections read that way. The headings this command reads:

| Heading | Supplies |
|---|---|
| `Severity` | what else counts as Critical, Major or Minor here, pasted into every review agent's brief (step 2) |
| `What not to flag` | the checks CI already gates and what the repository has settled, pasted into every brief |
| `Contracts` | what a user, script or consumer touches here, pasted into the contracts agent's brief |
| `Tests` | the test conventions, pasted into the tests agent's brief |
| `Context to load` | the documents the conventions agent reads for the layers the branch touches |
| `Where it runs` | how Review B runs, named in the final report |

A section under any other heading, in either pair of files, is read too, and applied where its text says. Where neither file has a heading, the step concerned runs on its generic rule alone, and the final report names each heading found in neither. A step whose convention is the thing itself — the command to run, the file to write — has no generic rule and no default, so where the repository supplies none the command STOPS rather than invent one, with the reason `conventions missing: <heading>`; the one exception is the formatter, whose default is none (step 1a). The repository's `CONVENTIONS.md` and `REVIEW.md` are read from the root of the repository this command runs in, and trusted as this command file is. The harness itself is not a repository convention: the verdict protocol, whatever drives the chain by reading it, the review agents and the sibling commands stay named in the steps, so whoever edits the protocol sees what consumes it.

## Steps

**Every STOP below ends its report with the failure verdict, and nothing after it.** Where a step names the reason (`formatting failed`), report that reason verbatim; where it does not, write a short reason of your own. Whatever else the stop has to say — which finding was raised and by whom, what state the tree is in, what the recovery is — goes *above* the verdict, however naturally it reads to close on it. This is stated once here because it governs all of them: a stop message whose last line is not the verdict reaches whatever drives the chain as the far less useful `no readable verdict` instead of the reason, and a runner that parks a failed issue then parks it with that non-reason — losing a two-hour stage's diagnosis to a formatting slip.

0. **Preconditions (before any suite run or review).** Each of the three is a **failure**, so each STOPS with the *Final report*'s failure verdict as the report's last line and nothing after it. Report the reason below verbatim; the explanatory sentence for a human goes *above* the verdict.
   - Run `git rev-parse --abbrev-ref HEAD`. If it is `main`, STOP immediately. Reason: `/gaffer:verify was run on main, not a feature branch`. Do not run the format pass or the suite, do not start reviewers.
   - Run `git log main..HEAD --oneline`. If empty, STOP immediately. Reason: `no commits on this branch over main`. Do not run the suite or start reviewers.
   - Require a **clean working tree**. Run `git status --porcelain`; if it is non-empty, STOP, adding that committing or stashing them is the recovery. Reason: `the working tree has uncommitted changes`. A clean tree is what makes step 3 simple and correct: after the review, *anything* that shows up in the tree is a review edit and nothing else, so there is no need to separate review edits from pre-existing local changes.

   The first two checks run up front purely on cost grounds: a full format, a full suite run and a full review are minutes of work, and on `main` or an empty branch every one of those minutes is spent to reach a conclusion a cheap `git` call already had. The clean-tree check earns its place differently — it is the invariant that makes step 3 correct, as described above.

   Once all three pass, note the time (`date +%s`): step 4's evidence budget is counted from here.

1. **Format (1a), then the full test run (1b).**

   **1a — Format the tree.** Run the project's formatter, exactly as `CONVENTIONS.md` → *Build, test and format* gives it. Where the conventions name no formatter — the plugin's default — there is no format pass: skip 1a and the format pass in step 3, and say so in the final report.

   - Formatting runs **once here, and once more in step 3 if the review led to edits** — never per commit. It is cosmetic work at a cadence that already costs minutes. This pass exists to bring the branch as `/gaffer:build` left it into line; step 3's exists because a review fix written after this pass would otherwise reach the pull request unformatted.
   - **If formatting changed files, commit them now** — `git add -A` and a message in the same `Refs #<N>: <imperative>` form step 3 uses (`CONVENTIONS.md` → *Commit messages*), e.g. `Refs #328: apply formatting` — *before* running the suite. This restores the clean working tree step 0 established, which is what keeps step 3's "anything in the tree is a review edit" invariant true. Do not carry format edits forward into the review commit; they are a separate concern and belong in their own commit.
   - **If formatting changed nothing, make no commit.** A branch already in format reaches step 2 with the commits `/gaffer:build` left and no format commit.
   - A **non-zero exit** from the formatter is a real failure (bad workspace argument, unparseable source) ⇒ **STOP and report**, with the reason `formatting failed`. A clean run that merely rewrote files is not a failure — that is the tool doing its job, and the distinction is the exit code, not whether `git status` is dirty afterwards.
   - Formatting deliberately precedes 1b so that any change it makes is verified by the suite below, rather than landing after the gate has already passed.

   **1b — Full test run (always).** Run the project's build-and-test command (`CONVENTIONS.md` → *Build, test and format*) — always, including docs-only branches. Do not add a skip path for docs-only branches: the suite is fast, and this is the first whole-suite gate after `/gaffer:build`, whose run precedes formatting and review fixes. A hook `CONVENTIONS.md` → *Hooks, scripts and plugins* names re-runs the suite when the PR is created, but that hook fires inside a separately invoked `/gaffer:raise-pr` that may not happen for a long while, or at all — so skipping here would leave a branch reported verified that no suite ever ran against.
   - Gate on the run's **exit code**, not on any stored marker.
   - **Not green ⇒ STOP:** report the failures to the invoker and do nothing else — no review agents.
   - **Green ⇒ continue.**

2. **Review (synchronous — this is Review A).** One round, over the whole branch diff, `git diff main...HEAD`. Note `git rev-parse HEAD` before starting anyone; step 3 opens by checking it.

   **There is no second round.** `/gaffer:verify` used to review its own fix commit, and then the fix to that, for up to four rounds. The later rounds fed themselves: every one reviewed only text `/gaffer:verify` had just written, the fix commits did not shrink from round to round, and most runs never reached a round that found nothing. What the fixes get now is step 3's narrow check, which looks for one thing and never starts another round, and Review B on the pull request, which reads the whole PR diff. So do not go back over your own fixes with another set of reviewers, however short the fix.

   **Gather the brief first.** Read the issue the branch implements — the number off the branch name, `gh issue view <N> --json title,body` — for its intent, acceptance criteria and confirmed decisions; where the branch name carries no number or the lookup fails, say so in the final report and brief without it. Read the `REVIEW.md` sections in the second table above, and the documents `REVIEW.md` → *Context to load* names for the layers the diff touches. Every review agent's brief then carries: the checkout path (the repository root); the diff range `main...HEAD`; the issue's text as the change's intent, with the instruction that **no PR body exists yet**, so findings about what the body states or records — a contract change it should state, evidence it should carry — are not reported now: step 4c checks the body once it exists; and the `REVIEW.md` sections it applies, **pasted into the brief as text** rather than named for the agent to go and read — *Severity* and *What not to flag* for every agent, *Contracts* for the contracts agent, *Tests* for the tests agent, and the *Context to load* documents for the conventions agent.

   **Who reviews, in three waves.** The review agents are gaffer's own, the ones `/gaffer:review-pr` starts on the pull request; each one's definition states what it looks for, how it investigates, the severity scale and what it returns. Start them by their `gaffer:` names — the prefix is required.
   - **Wave 1 — the reporters, in parallel.** Start `gaffer:review-correctness`, `gaffer:review-security`, `gaffer:review-contracts`, `gaffer:review-tests` and `gaffer:review-conventions` together, leaving out any whose dimension the diff genuinely does not touch (security on a diff with no input handling, workflow, script or secret; contracts on a diff that changes nothing a user, script or consumer touches). Start `gaffer:review-call-chain` with them, telling it no units are named so it identifies them from the diff, unless every changed file is a test, a document or generated. Run `/gaffer:review-slop` (which emits a cleaned diff) while they work.
   - **Wave 2 — verification, in parallel, after every wave-1 agent and `/gaffer:review-slop` have returned.** Start one `gaffer:review-verifier` per candidate finding, each briefed with the checkout path, the diff range, the candidate as reported, and the *Severity* and *What not to flag* sections pasted as above. The hunks of `/gaffer:review-slop`'s cleaned diff go to **one** verifier together, as a batch of Minor candidates. Only CONFIRMED findings go on; a REJECTED one is *Not acted on*. The verifier's severity and Pre-existing call stand; you do not re-rate them (below).
   - **Wave 3 — `pr-review-toolkit:code-simplifier`, alone, only after every verifier has returned.** It is the one reviewer that **edits files directly**, so it must not run while anything is still reading the tree. If the diff has no code it could simplify, skip wave 3. While it runs you may plan the fixes, but make no edit to the working tree until it has returned. Wave-1 findings and the cleaned diff are anchored to HEAD: before applying one, relocate it in the current file, and drop any the simplifier's edits already resolved. **Before you make any edit of your own, save the simplifier's edits as a patch** — `git add -A && git diff --cached --binary > <scratch dir>/verify-simplifier.patch && git reset -q`, in the directory `CONVENTIONS.md` → *Scratch files* names — so step 3 can take them back as one unit, files the simplifier created or deleted included.
   - **Keep the waves — never run `code-simplifier` alongside the reporters or the verifiers.** They share one working tree, so a concurrent simplifier rewrites files the others are still reading, and their `file:line` anchors silently drift between the edited file and HEAD. Do not fix this instead by giving the simplifier its own worktree: step 3 finds review edits through `git status --porcelain`, and edits made in another worktree never show up there, so they would never be committed.

   **Keep a record as you go**: every agent you started, by name; every confirmed finding, with its severity and the reviewer that raised it; and, for each fix you make, the files and hunks it touched. The final report lists the agents, and step 3 needs the hunks.

   **What to do with the confirmed findings.** Find each one's row in the table below by severity and scope. **The table and the definitions under it are the only statement of which outcome a finding gets.**

   | Finding | Outcome |
   |---|---|
   | Rejected by its verifier | Not acted on |
   | **Critical** or **Major**, in scope | **Fix it** |
   | **Minor**, in scope, a sentence the branch wrote or changed that states something false or overstated | **Fix it** |
   | **Minor**, in scope, otherwise | **Fix it, unless** the smallest fix means restructuring — then *Deliberately not done* |
   | Any severity, out of scope | *Deliberately not done* |

   What the table's words mean:

   - **Severity** — Critical, Major or Minor, on the scale the review agents state, as the verifier settled it. A hunk of the cleaned diff is a Minor. Neither you nor anything else in this command re-rates it afterwards: the scale is the one `/gaffer:review-pr` posts on, so a finding is fixed here at the severity it would be posted at there.
   - **In scope** — the finding concerns the branch's own new or edited code or text, or breakage that code causes elsewhere. **Out of scope** — it concerns code the branch did not touch, *and* you have checked that the problem is there on `main`, unchanged by this branch. A finding you have not shown that for is in scope, wherever the file is. A finding its verifier called **Pre-existing** is out of scope only once you have made that same check.
   - **Fix it** — fix it in the working tree, with the smallest change that removes the defect (see below). A false or overstated sentence is fixed by correcting the one fact or deleting the sentence, never by writing a fuller account in its place. If a confirmed Critical or Major genuinely cannot be fixed, **STOP and report**, naming the finding, the edits already applied for other findings, and that those edits are uncommitted and unverified. Discarding them is the recovery: committing them to satisfy step 0 on a later run would put untested code on the branch. Declining to fix one and leaving the tree empty is not a clean review. A Minor that genuinely cannot be fixed goes under *Deliberately not done* with the reason instead.
   - **Restructuring** — a fix that would change the shape of code around the defect rather than the lines that are wrong: a different algorithm, a moved responsibility, a new abstraction. A Minor that needs one is not fixed here.
   - **Deliberately not done** — do not fix it here: an out-of-scope fix folds an unrelated mission into the branch, and a restructure is a change no reviewer has seen. Record it with a one-line reason — out of scope and present on `main`; needs restructuring, and what; reverted by step 3's check, and why — for the PR body (step 4) and the final report. It does not block the verdict.
   - **Not acted on** — nothing is changed for it, and it does not block the verdict.

   **Make the smallest change that removes the defect.** A fix gets only step 3's narrow check before the pull request, so keep it small enough to be read at a glance there. Where code misbehaves, change the lines that misbehave — do not restructure around them. Add a test, a guard, a comment or a document only where the finding itself is that it is missing. Anything larger that the review made you want belongs in its own issue, not in this commit.

   **You never re-rate.** You may not move a confirmed Critical or Major down, nor decide a real one is "minor enough", nor narrow "the branch's own code" to exclude a file the branch edited, nor call a finding out of scope without the check that definition requires, nor overturn a verifier's REJECTED or CONFIRMED with your own reading. The verifier is independent of the run; you are the thing that wants the run to finish, and must not be the thing deciding the verdict.

   If a review agent errors, STOP and report (stop-on-failure) — a wave-1 error means wave 2 is never launched.

3. **Check the fixes, then re-verify and commit them.** Step 0 required a clean tree and step 1a committed its own formatting, so `git status --porcelain` now shows exactly what the review changed — from *any* source (your own fixes **and** the simplifier's edits) — and nothing else.
   - **If the tree is clean and HEAD is where step 2 noted it:** the review changed nothing and the branch is verified. Skip the check, the format pass, the re-run and the commit — go to step 4. (No spurious second suite run.) The last suite run was against exactly the committed code.
   - **Otherwise** — the tree has edits, or HEAD has moved because a reviewer committed something itself:
     - **The narrow check, once, before anything is committed.** Start `gaffer:review-correctness` and `gaffer:review-tests` together over the uncommitted diff (`git diff`, plus any untracked files), each briefed as in step 2 but scoped to those edits alone and told to **report only Critical or Major problems the edits introduce** — not problems in code the edits did not change, and nothing Minor. Confirm each candidate with a `gaffer:review-verifier`, as in wave 2. Then, for each confirmed one:
       - **Undo the fix it sits in** — the hunks your record from step 2 gives for that fix — rather than fixing it again. Where the failing edit is the simplifier's, undo all of the simplifier's edits together by reverse-applying the patch step 2 saved (`git apply -R`). Where an undo cannot be made cleanly — the hunks overlap another fix — STOP and report, naming both fixes and saying the tree holds uncommitted, unverified review edits that discarding is the recovery from.
       - **Record the original finding under *Deliberately not done*** with the reason `fix reverted: <what the check found>`, whatever its severity, and go on. Where it is a Critical or Major, the final report names it first, above everything else, and the PR body's *Deliberately not done* entry says plainly that it is open and must be fixed before merge: the PR then carries a known open finding, stated, rather than a fix nobody reviewed.
       The check never starts a second review: whatever it finds is undone, never re-fixed.
     - **Format, before the suite re-run** — the project's formatter, the same command as step 1a. A review fix is written fast and is routinely off-format, and this is the only pass that ever sees it: step 1a ran before the fix existed. A non-zero exit is a real failure ⇒ **STOP and report**, with the reason `formatting failed`; the tool merely rewriting files is not.
     - Re-run the project's build-and-test command. Not green ⇒ STOP and report — and say that the tree is dirty, that the edits in it are the review's failed fix (and its formatting), and that discarding them is the recovery. Do **not** commit them to satisfy step 0's clean-tree precondition on a later run: that would put a red fix on the branch, which is the one thing this step exists to stop. If HEAD had moved, name the commits from the noted value to HEAD as well: they are a reviewer's own, and they are in the red run too.
     - Once green, **commit whatever the tree holds** with `git add -A` and a message in the project's `Refs #<N>: <imperative>` form — e.g. `Refs #328: apply /gaffer:verify review findings`, with the issue number read off the branch name, not left as a placeholder. If the branch name carries no issue number, drop the `Refs #<N>: ` prefix and keep the rest; the project requires it only where an issue applies. Commit immediately, with no further edit in between, so the suite run above was against exactly the code the commit contains. This is what makes the fixes reach the eventual PR — `/gaffer:raise-pr` pushes *commits*, so uncommitted or untracked working-tree edits would silently never leave this machine. `git add -A` is correct and complete here precisely because the tree started clean: it stages every review edit and its formatting (including new untracked files and deletions) with no risk of sweeping in unrelated local changes. The simplifier's patch is in the scratch directory, which is git-ignored, so it is not swept in. If the undo and the format pass together put every edit back and the tree is clean, there is nothing to commit.
     - Go to step 4 — **do not review the commit you just made.**

4. **Evidence and the pull request body.** The branch is now committed and green. What is left is the body `/gaffer:raise-pr` opens the pull request with, so the reader of the PR — and Review B — find what was proven and what was left out stated there, rather than discovering it.

   **4a — Evidence the issue asks for.** Read the issue's acceptance criteria and confirmed decisions (step 2 fetched them) for anything they ask to be **recorded on the pull request** — a number of consecutive green suite runs, a command's output, a check done by hand. For each:
   - **Produce it** where it means running a command the issue or `CONVENTIONS.md` spells out exactly — the build-and-test command, a named script — and the run fits the budget: it must finish within half the verify stage's time limit, counted from the time step 0 noted. That limit is `CHAIN_STAGE_TIMEOUT`, in seconds, where that is set in the environment, and otherwise the chain's default verify limit of two hours — so one hour from verify's start. Estimate from the runs this verify already made, and stop producing it the moment it would overrun. Record what ran and its result for the body. A red run here means the suite is not reliably green on the committed code, which is exactly what such evidence exists to show: STOP and report, naming the run that failed and its output, with the tree clean and every commit in place. Producing evidence changes no file; if anything appears in the tree, STOP and report it.
   - **Otherwise list it as owed** — a check by hand, a command the issue does not spell out, one that would overrun the budget — with the exact command or action that would produce it. Owed evidence does not fail verify.

   **4b — Draft the body.** Read `git log main..HEAD` and `git diff main...HEAD` so the body describes what actually changed, not what the branch name suggests. Write a description sized to the change. **Do not follow a fixed template**: decide which sections earn their place for this PR. Don't repeat what GitHub already shows — the changed files and their diffs, the commit list, line counts, the author, branches and CI status. Use the body for what a reviewer can't easily get from the code or the history:
   - **Why** — motivation not already obvious from the commits. Skip where the title says it.
   - **What changes** — a short summary of observable changes, grouped by theme rather than by file.
   - **What breaks, and for whom** — any change to something a user, script or consumer touches (`REVIEW.md` → *Contracts*), and who it breaks; include it whenever the branch changes one, and whatever `CONVENTIONS.md` → *Pull requests* asks for.
   - **Non-obvious things a reviewer should know** — caveats, deliberate trade-offs, anything in the diff that looks odd but is intentional. Where the branch adds a change-intent record (`CONVENTIONS.md` → *Change-intent records*), link it here and do not restate it.
   - **How to verify** — a markdown checklist of concrete actions a reviewer can perform, each one followable on this branch as written, each saying the result to expect. Omit for a pure-documentation change.
   - **Evidence** — each item step 4a produced, with its result, and each item owed, with the command or action that would produce it. Include it whenever the issue asks for evidence.
   - **Deliberately not done** — every confirmed finding step 2 or step 3 recorded there, each as one line: what it is, its severity, and its reason. Include it whenever there is one. It is the reader's record that the finding was seen and why it was left, so a reviewer who disagrees argues with a stated reason.
   - **Related** — links to prior PRs or issues that give context. Do **not** write a closing keyword (`Closes #<N>`): `/gaffer:raise-pr` settles and verifies that against GitHub itself, and adds it.

   **4c — Check the body against the branch.** Start `gaffer:review-conventions` and `gaffer:review-contracts` together, briefed as in step 2 but scoped to **the draft body alone**, which now exists: every claim in it against the diff and the code, every *How to verify* step as one a reader can follow on this branch and see the result it promises, every contract change stated with who it breaks, and the evidence the issue asks for recorded or listed as owed. Confirm their candidates with one `gaffer:review-verifier`, as a batch. Correct, add or delete the sentences each confirmed finding names — this is prose, so no suite run is needed — and do not start them again.

   **4d — Write it.** Write the body to `raise-pr-body.md` in the directory `CONVENTIONS.md` → *Scratch files* names, with the native `Write` tool, its **first line** exactly `<!-- gaffer:verify <sha> -->`, where `<sha>` is the full `git rev-parse HEAD` the body describes. `/gaffer:raise-pr` uses the body only while the branch is still at that commit, and strips the line. The scratch directory is git-ignored, so the tree stays clean.

5. **Stop here.** Do **not** push, open a PR, merge, or run `/gaffer:raise-pr`. Leave the working tree clean — everything committed to the branch, the body in its scratch file — because that is exactly `/gaffer:raise-pr`'s entry condition, so the two compose by hand with nothing in between.

## The two reviews (Review A vs Review B)

- **Review A** — steps 2 and 3, synchronous, in-`/gaffer:verify`: gaffer's review agents and `/gaffer:review-slop`, each finding confirmed by a verifier, then the simplifier, run once over the branch diff; then the narrow check of the fixes. Its findings drive the fixes step 3 commits, and what it leaves unfixed goes in the PR body under *Deliberately not done*.
- **Review B** — asynchronous, on the PR: `/gaffer:review-pr`, which the project runs when the PR opens — `REVIEW.md` → *Where it runs* says how, and names any gate on it. It starts the same review agents against the same criteria, reads the whole PR diff, fix commit included, and reads the body, *Deliberately not done* included — so where it disagrees with a reason given there, it says so against a stated trade-off. It is outside `/gaffer:verify` entirely, and nothing here waits on it. Review B is for a human to read at merge; when you later run `/gaffer:capture-learnings` at a supervised checkpoint, that command's own best-effort PR-review fetch picks it up then.

The two reviews use the same agents on purpose: the measured gap between them was mostly standard, not luck — Review A applied generic reviewers and never loaded the repository's criteria, while Review B applied both. What still differs is sampling, the simplifier and the slop pass, and Review B's sight of the fix commit and the final body.

## Final report

Report, in this order:

- Whether formatting changed anything, and the commit if it did — step 1a's, and step 3's if its commit carried formatting alongside the fix.
- The suite result(s).
- Every review agent started, by name and wave — wave 1's reporters, wave 2's verifiers (as a count), the simplifier, step 3's check and step 4c's body checks — and every one left out, with why. Then the commit step 3 made, if the review led to one. If HEAD had moved by step 3 because a reviewer committed itself, name each such commit by hash and say which reviewer made it: it is on the branch, but nothing in `/gaffer:verify` judged it against step 2's rules.
- Which review findings were fixed-and-committed, by name and severity; how many candidates the verifiers rejected; and each fix step 3's check undid, with what it found.
- Every finding under *Deliberately not done*, by name, severity and reason — the same list the PR body carries.
- The evidence: each item produced, with its result, and each item owed, with the command or action that would produce it. Say plainly that owed evidence must be supplied on the PR before it merges.
- Where the PR body was written, and the commit its first line names.
- On the way to a `verified` verdict, add this **above the verdict** — it is boilerplate this command mandates, and appending it below the verdict is the commonest way to lose the verdict: "Run `/gaffer:raise-pr` to push the branch and open the PR with the body drafted here — it derives `Closes #<N>` from this branch name and verifies it before use, then reports what it settled; check that line to confirm the link was made. If you commit again first, raise-pr will set the drafted body aside as stale. Review B posts async on the raised PR, and `/gaffer:capture-learnings` folds it in when you next review the batch."

**Close the report with the verdict as its last line** — one JSON object on one line, at column 1, nothing else on that line and nothing after it. Exactly one of:

- `{"schema": 1, "outcome": "verified", "branch": "<branch>"}` — on success.
- `{"schema": 1, "outcome": "failed", "reason": "<short reason>"}` — on any failure.

The schema — its fields, what each outcome carries, and how it is read — is [`docs/verdict-schema.md`](../docs/verdict-schema.md) in the plugin (`${CLAUDE_PLUGIN_ROOT}/docs/verdict-schema.md`). The fixed reasons this command emits are `formatting failed` (step 1a or step 3), step 0's three precondition reasons and `conventions missing: <heading>` (*Repository conventions*). Anything else is a short reason of your own.

What ends the report is the whole of what the chain reads, which is what makes it safe and what makes it strict:

- **Nothing may follow it.** Not a closing sentence, not a blank-line-and-a-postscript. A report whose last line is anything but the verdict stops the chain as unreadable — a safe stop, but a wasted run. A code fence around the verdict is tolerated; a sentence after the fence is not.
- **Nothing above it can be mistaken for it.** Quote either verdict as often as the report needs to — a failure verdict a reviewer raised, a table of both — and it changes nothing.
- **The verdict carries nothing but its fields.** `Verdict: {…}` is not a verdict, because the line must be the object and nothing else; neither is a success verdict with a hedge after it — `{…} (2 Major deferred)` is read as no verdict at all, not as a pass — nor one that carries a `reason`, which contradicts itself. A deferred finding or owed evidence belongs in the report above, and in the PR body, not in the verdict.

Never report verified over a red suite or evidence run, a confirmed Critical or Major in scope left neither fixed nor recorded as reverted by step 3's check, a confirmed Minor left neither fixed nor under *Deliberately not done*, or an uncommitted change.
