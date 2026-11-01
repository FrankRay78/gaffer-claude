# The workflow

What the commands implement, how the stages fit together, where the human checkpoints are, and why it is built this way. A repository that installs the plugin gets this workflow; what it adds of its own goes in its `CONVENTIONS.md` and `REVIEW.md` ([`interfaces.md`](interfaces.md)) and in a short companion document of its own, not here.

## Introduction

Draft an issue focused on outcomes and acceptance criteria before touching code, lock the failing tests before writing the implementation, and **enforce both mechanically**. The result is a *harness*: an agent constrained by context, feedback loops and automated quality gates, so the agent does the work and the engineer reviews it.

**The workflow in one line:** draft, review and confirm an issue → build it → verify → raise the PR → merge.

*Inspired by:*
- [Coding with AI](https://www.chrismdp.com/coding-with-ai/) — Chris Parsons, 2026.
- [Harness Engineering](https://openai.com/index/harness-engineering/) — OpenAI, 2026.
- [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Anthropic, 2025.
- Field notes — Andrej Karpathy (Dec 2025) and Boris Cherny (Feb 2026).

## Why a harness, not better prompts

When an agent struggles with trivial work, treat it as a **context/harness failure, not a prompt failure** (chrismdp). The model is rarely the bottleneck: the wrapper — context selection, the agent loop, the gates — matters as much as the model.

A useful frame is the **five duties of a harness** (OpenAI): **constrain** what the agent may do, **inform** it of what it should do, **verify** its work, **correct** its mistakes, and **keep humans in the loop at high-stakes decisions.** Every section below maps to one of these; the one teams most often under-build is *verify*.

**The bottleneck has moved from generation to verification** (chrismdp): not "how fast can we build?" but "how fast can we tell if it's right?" Two consequences run through this workflow:
- If verifying an AI change takes as long as writing it, present it differently, move the verification to an automated gate, or don't delegate it.
- **Give the agent a way to verify its own work** — a test loop, a type checker, a browser check. Output quality rises sharply with one (Boris Cherny: ~2–3×).

## The stages, in order

Every feature goes through the same four stages: the issue stage on the main branch, then build, verify and raise.

### The issue stage (on `main`)
1. `/gaffer:draftissue` ← optional; turn an idea, a document or a backlog item into a needs-first issue and raise it
2. `/gaffer:reviewissue` ← pre-build gate; posts gaps + recommendations as an issue comment
3. `/gaffer:confirmissue` ← fold the answered review into a `## Confirmed decisions` section and label the issue `ready`

The confirmed issue **is** the specification. There is no separate spec, test plan or task list: the acceptance criteria the issue stage settles are what the build stage implements and the verify stage checks. Design work that would once have gone into a planning document goes into the issue, where the review gate cross-checks it against the codebase before any branch exists.

### The build stage
- `/gaffer:build <issue>` ← branch, RED, GREEN, refactor, docs, all committed. Unattended; ends at a green, committed branch (see *The build stage*).

### Verify, then raise
- `/gaffer:verify` ← one orchestrator: **format → full suite (the gate) → clean-context review → fix → format → re-run suite → commit**. One review, and the commit of its fixes is read by Review B on the pull request. Unattended, so it can drive a loop. Ends at a green, reviewed, fully-committed branch; it does **not** raise the PR.
- `/gaffer:raise-pr` ← push the branch and open the PR; opening it triggers Review B. A separate stage because it is the one irreversible, outward-facing act; everything before it stays freely re-runnable.

### Periodic (not per-feature)
- `/gaffer:capture-learnings` — fold corrections back into memory and skills. Not part of verify: it needs human curation and batches better, so run it at a supervised checkpoint after several features.
- `/gaffer:audit-deadcode` — every few features or before a release; **not per-PR**.
- `/gaffer:audit-codebase` — after a batch of merges or before a release; **not per-PR**. The whole-tree counterpart to the diff-shaped reviewers, which have nothing to read once a branch has merged: several independent lenses over the committed tree, every finding challenged by a separate agent given the claim alone, and the survivors raised as one issue. It records findings and changes nothing.
- `/gaffer:context-gardening` — quarterly or after a big architectural shift.

## The build stage

`/gaffer:build` turns one issue into a green, committed feature branch and stops. Formatting, review, pushing and the PR belong to later stages.

- **The issue is the spec.** It reads the issue, not a spec folder, and implements every item of its acceptance-criteria checklist. Without a checklist, it derives the criteria from what the issue says (e.g. a bug's observed and expected behaviour) and writes them into its report for a reviewer to check. It never invents scope.
- **It decides alone, and writes each decision down.** Once it has an issue, it never prompts. Where the issue is ambiguous, it picks the reading that fits the existing code and the issue's intent, and records the assumption in its report — where a reviewer finds every judgement call.
- **Two named cases are handled specially.** A **public-API change** goes ahead only when the criteria require it, and is flagged in the report; a merely convenient one is not made. A **new dependency** to a library the repository marks as dependency-controlled is never added unattended: if the issue needs one, the stage stops and says so. Both have costs beyond the branch.
- **RED first, proven by the real tool.** For production code, it writes the failing tests first and must see them fail; tests that pass first time mean the behaviour exists already or the test misses the criterion. For a configuration, tooling or CI change, RED is the real tool failing before and passing after. Never a stand-in test that reimplements a tool's check: it covers less and can pass when its own matching logic is wrong.
- **Issue labels become test markers.** Each `**Scenario: X**` label on the issue gets at least one test with a matching `SCENARIO: X` marker, in that test file's own comment syntax, keeping label → test traceability in a single hop from the issue. No labels, no markers: an invented label looks like a traceability key but traces to nothing. The pairing is gated pre-merge where the repository has a check, rather than trusted to this stage — see *Mechanical enforcement layer*.
- **Check the starting point before branching.** A clean tree and `main` checked out, the remote `main` fetched, and a refusal if local `main` has unpushed commits — the branch is cut from the remote, so they would silently be missing. A closed issue, or one with an open PR, also stops the run.
- **Name the branch after the issue.** `feature/<N>-<slug>`, the issue number first, so later stages can read it from the branch: the PR stage adds the closing keyword, and a traceability check reads the issue it must trace. A leftover branch from an earlier attempt is recreated, unless it holds commits the stage has not inspected.
- **Commits reference the issue but never close it.** A closing keyword in a commit (`Fixes #N`, `Closes #N`) closes the issue when the commit reaches `main`, before review. Only the PR body closes it.
- **Run the whole suite, not just the new tests** — after RED, after GREEN and after any refactor; a regression anywhere is a failure. Updating the docs the change affects is part of the stage.
- **Leave formatting and the PR to later stages.** It does not format, push or open a PR. It ends committed and clean, which is what `/gaffer:verify` requires.
- **Stop-on-failure is global.** A dirty tree, an unbuildable issue, RED tests that pass, a suite that won't go green: stop at that step, report, run nothing later.
- **It ends with a verdict:** a `ready` outcome naming the branch (every criterion implemented, whole suite green, tree clean) or a `failed` outcome with a short reason — see *The verdict contract*. Never `ready` over a red suite, an unimplemented criterion or an uncommitted change.

## The verify gate

The steps between "implementation looks done" and "fit to become a PR" are a fixed sequence with one hard ordering constraint, and a human re-enacting them from prose gets it subtly wrong. `/gaffer:verify` encodes them.

**The suite runs first; everything else is downstream of its exit code.** The ordering is *structural*, not policed: review cannot start on red code because it runs after the gate. Do not add a hook to enforce the ordering — the exit code **is** the gate. A hook watching for the agent *claiming* green is exactly the anti-pattern "gates attach to actions, not prose" warns against.

Properties worth knowing:

- **Format with the check CI enforces, and format the review's fix too.** The up-front pass runs before the suite and commits on its own, so the gate covers it and the tree is clean again before review — which the later commit of review fixes depends on. Then format again if the review led to edits, *before* the suite re-run, so the fix and its formatting are committed together and the suite ran on exactly the committed bytes. Run the same command CI checks, not a narrower subset of it, or the two can disagree about what "formatted" means. A repository names the command under `CONVENTIONS.md` → *Build, test and format*; with none named, the passes are skipped and the report says so.
- **Always run the whole suite — no docs-only skip.** It is the first suite run after the build stage: formatting and review fixes land later, and a branch may not have come from `/gaffer:build` at all. A skip would report a branch verified that no suite ran against.
- **Unattended by design.** No prompts, so a loop can drive it feature after feature, as well as a person. Anything needing a human turns the pipeline into a wait.
- **Stop-on-failure is global.** Dirty tree, red suite, a format tool error, a reviewer subagent error, a confirmed finding that must be fixed and cannot be: stop, report, run nothing later. Every such report says what state the tree is in.
- **Cheap preconditions first** (on a feature branch? commits over main?), or a full suite and review burn before a late guard trips.
- **Review runs in clean context.** Reviewers see the diff, not the conversation that produced it. The *deciding and fixing* happens in the orchestrator's own loop; "clean context" governs the reviewing, not the fixing.
- **Validate a finding before acting on it.** Check that it is real — cross-check it against the actual test and spec state rather than relaying it. Acting on a false positive is how a review makes code worse.
- **Let a rating be raised, never lowered.** Every reviewer gives a severity on one stated scale, and the stage that fixes findings rejects one only as not real. It may raise a rating — a confirmed defect in the branch's own work is never minor, and neither is a defect that arrives unrated — but if it may lower one, the thing deciding the verdict is the thing that wants the run to finish.
- **Report a serious problem in code the branch did not touch; do not fix it there.** Name it in the stage's own report with its severity, and leave it out of the branch.
- **Re-verify what review changed.** Post-gate fixes are unverified code: re-run the suite before reporting verified, or a bad fix reaches the PR unchecked. Then *commit* them — the PR stage pushes commits, and the gap before it is open-ended.
- **Review once, and let the pull-request review read the fix.** A review fix is new code, and someone who did not write it should read it — but not another round of the same stage. Re-reviewing the fix in a loop feeds itself: each round reads only text the stage has just written, reviewers find about as much in a forty-line fix as in the branch, and the fix to those findings is the next round's material. In practice the fix commits did not shrink from round to round, every blocker in a branch's own code was caught in the first round, and most looped runs ended at the round bound or ran out of usage allowance before reaching a round that found nothing. The reader for the fix is the asynchronous review on the pull request, which sees the whole diff.
- **Keep a fix small.** The fix is the one change the stage's own reviewers never read, so it is held to the smallest change that removes the defect: correct the one false fact, change the lines that misbehave, and add a test or a guard only where the finding is that it is missing. A fix that writes a fuller account, or restructures around the defect, is where the next defect comes from.
- **Stop before the irreversible step.** End at the verified branch; leave pushing and the PR to a separate, deliberate invocation. Everything before it is safe to re-run; the outward-facing act is not, and it is the step worth a human's decision.
- **Let unfixed findings end with the stage's report.** A finding left unfixed — a suggestion, or a problem in code the branch did not touch — is named in the closing report and carried nowhere else. Handing the first review's leftovers to the pull-request review tells it what to conclude; it should judge the branch on what it sees.

**Two reviews, not one.** *Review A* is synchronous inside `/gaffer:verify`: clean-context subagents over the branch diff, run once, whose findings stay in the conversation for `/gaffer:capture-learnings`. *Review B* is the asynchronous `/gaffer:review-pr` on the raised PR, triggered by the PR opening, for a human to read at merge. Nothing waits on Review B. It is also what reads Review A's fix commit, and that is a known cost: a narrowed `catch` clause once reached an open PR as the only code on the branch nothing but the suite had read, which is what the loop was built to stop. Keeping the fix small is what is left to guard against that.

## The verdict contract

Each stage ends with **one machine-readable verdict, as the last thing in its report** — the shared interface that lets a script chain the stages without a person reading each report. The verdict is one JSON object carrying a schema version, an outcome and that outcome's payload:

| Stage | Success outcome | Payload | Failure |
|---|---|---|---|
| `/gaffer:build` | `ready` | `branch` | `failed`, with a `reason` |
| `/gaffer:verify` | `verified` | `branch` | `failed`, with a `reason` |
| `/gaffer:raise-pr` | `raised` | `pr` | `failed`, with a `reason` |

The schema — every field, what each outcome carries, how a reader handles a version or a field it does not know, and how it is read off the report — is stated once, in [`verdict-schema.md`](verdict-schema.md); the commands and this guide point there rather than restating it. A chain starts the next stage only on the previous stage's success verdict, and stops at the first failure. Four rules make this safe:

- **Position is the verdict's identity.** The verdict is whatever ends the report — the last non-blank line, or a code fence closing the report — and nothing else in the report is read. A report quotes verdict-shaped text constantly — RED evidence in a code block, a review finding recording why a run stopped, a PR stage naming the pull request that already exists — and none of it can be mistaken for the stage's own decision, because a quotation cannot fake position.
- **The verdict is a structured object, not a phrase in the prose.** Anything that is not one JSON object — a sentence wrapped around it, a hedge after it, a bare URL, the retired text form — is no verdict, and the reader stops saying so rather than guessing. A success verdict that also carries a reason contradicts itself and is not a success: that is the structured form of the one-line hedge that once passed a text gate anchored only at its start.
- **The schema is versioned, and the reader is strict about the version and lenient about the fields.** A version the reader does not know stops the stage naming that version, so a caller is told it is behind rather than left to misread a verdict. Fields the reader does not know are ignored, so a command can add to its verdict — assumptions, deferred findings — without touching the reader or the version.
- **A stage writes its success verdict only for work it did.** `raised` names a PR this run opened; `ready` describes a suite this run saw pass.

## Running the stages end to end

Every stage after the issue stage runs unattended, so a script can take one issue from a clean `main` to an open PR with no prompt: `/gaffer:build` → `/gaffer:verify` → `/gaffer:raise-pr`. By hand, most of the elapsed time is waiting for a person to read each report and start the next stage; a chain removes that wait. The plugin ships no chain: it belongs to the repository that runs it, and what follows is what one must do.

- **Each stage is its own headless agent process.** The script starts each as a fresh non-interactive run (`claude -p "/gaffer:build <N>"`, with the plugin loaded from a checkout the script controls) and reads its verdict. Every stage starts fresh and inherits no context, so each is reached only through the previous stage's verdict and the state it left on the branch.
- **Gate on the verdict; stop at the first failure.** The next stage starts only on the previous one's success verdict. A failure verdict, a verdict the chain cannot read, a schema version it does not know, an agent error or a timeout stops the chain. The closing message names the stage, the reason, and the session to reopen; stages that succeeded need not re-run.
- **Read the verdict by position, not by scanning the prose.** Scanning free prose for verdict-shaped text fails in both directions at once, and tightening one direction loosens the other. Permissive failure matching stops a healthy stage over a verdict its own report quoted as evidence; permissive success matching reads a failed stage as a success whenever a success-shaped phrase sits below a failure line the scan missed, which is how a chain opens a pull request off unverified work. Position ends the negotiation — a quotation cannot fake being last — and it costs each stage's prompt one rule: the verdict goes last, with nothing after it.
- **Tolerate decoration around the object; treat anything else as no verdict.** Strip **one** leading heading, bullet, numbered-item or blockquote marker, a run of emphasis characters wrapping the line, and a code fence around the object when that fence closes the report; bound the indent at three spaces, because four is markdown's code block and a quotation that can indent itself into last place can fake position. Everything beyond that is **unreadable**, which stops the run saying so, distinctly from a stage that failed with a reason and from an unknown schema version: the three send the reader to different places. Fail safe in that direction deliberately: a false stop costs the rest of one run, a false success opens a pull request off work nobody verified.
- **Keep the reason as the stage gave it.** Strip only outer whitespace, and flatten a line break inside it to a space, because the reason lands on a one-line closing message that a runner reads whole. A whitespace-only or missing reason is a malformed report: say the stage failed without giving a reason rather than closing on a dangling dash.
- **The chain changes nothing itself — but it says what was left.** It resets, cleans and pushes nothing, so the branch is as the failing stage left it. For the same reason its closing output has to *describe* that state: the commits the branch holds over the trunk, and whether the working tree is dirty, printed *before* the closing message so that stays last. A stage killed at its time limit leaves no report of its own, and a stage stopped part-way can leave commits or uncommitted edits behind.
- **Check prerequisites before spending model time.** Confirm every tool the script needs is installed and the starting state holds (an issue named, a clean tree, `main` checked out), so a missing tool is named as itself rather than surfacing an hour later as a stage with no verdict. Give each stage a time limit, refuse a zero limit (to `timeout` it means *no limit*), record elapsed time so a kill from outside is not reported as a stall, and offer a dry run that lists the stages and runs nothing.
- **Tell a usage-limit stop apart from a failure.** A stage the account's Claude usage limit cut off is not a fault in the issue. Recognise it from the reply's typed error field, never from the report text (a report may quote a limit message it merely read about), report it with the reset wording, and exit with a code of its own so a runner does not park the issue for it.
- **Rely on each stage's contract rather than re-checking it.** The chain does not re-check between stages that the tree is clean or nothing was pushed early. A stage that breaks its contract is caught by the next stage's preconditions (`/gaffer:verify` refuses a dirty tree), which stops the chain.
- **Load the plugin from a checkout the script controls.** A headless run must not depend on whatever version happens to be installed on the machine: pass `--plugin-dir` for a clone of this repository's `main` that the runner brings up to date before each firing, so every stage in one run comes from one known commit and the log can say which.
- **The human decision moves to the start.** The last stage opens the PR without a pause — a deliberate exception to *Stop before the irreversible step*. The person's decision is starting the chain against one named issue. The commands stay separate, so running `/gaffer:verify` and `/gaffer:raise-pr` by hand keeps the pause.
- **Residual risk: silently denied `ask` rules.** Headless stages deny `ask`-matched calls without a prompt (see *Permissions and unattended runs*), so a stage can carry on degraded and still report success; the chain cannot detect it.
- **Test the chain against a stub agent** in throwaway repositories: order, failure and timeout handling, malformed replies. It takes seconds and calls no model. Check the two things a stub cannot prove — reopening a failed stage's session, and a full real run — by hand.

### A scheduled runner

A runner works through the `ready` backlog without anyone starting the chain: a scheduler fires it periodically, each firing picks the next eligible issue, resets a clone kept only for the runner to the latest `main`, and runs the chain against the issue there. It ends with an open pull request, or with the issue labelled `parked` and a comment saying why. It never merges, and it never pushes or deletes anything on the remote itself; only the chain's own `/gaffer:raise-pr` pushes.

- **Selection.** An issue is eligible when it is open, labelled `ready`, not labelled `parked`, has no open pull request linked to it, and has no open blocking issue. The runner takes the lowest-numbered one; the issue body plays no part. On a public repository, build only issues nobody but the maintainer and the review bot has written on: anyone can post a comment shaped like a review, and a confirmation would fold it into the body.
- **One run at a time.** A firing while a run is in progress starts nothing and exits 0. The runner holds a lock of its own rather than relying on the scheduler.
- **A clean start in its own clone.** Before each run the clone is fetched, forced onto the remote `main`, and cleaned of every untracked and ignored file, so every run builds from scratch. The reset is destructive, so the runner refuses any directory that is not a full clone explicitly marked as the runner's. State — logs and the lock — lives outside the clone.
- **Nothing to do is not an error.** With nothing eligible, a firing changes nothing and exits 0. A tracker query that fails selects nothing and exits 1 (fail closed), and the next firing tries again; so does a machine fault found before the chain starts, and the issue is not parked for it.
- **Failure parks the issue.** The runner adds the `parked` label and comments with the failed stage and position, the reason from the chain's closing line, and the log path. The attempt's local branch is renamed to `attempt/<N>-<timestamp>` and named in the comment, so the commits are kept for diagnosis and the next build can create the issue's branch afresh. A parked issue is never retried automatically; removing the label is the retry.
- **Report mode.** A dry run names the issue the next firing would build and only reads the tracker.

Three things to settle before the first firing: create the `parked` label; run report mode first; give the scheduler an explicit environment (a scheduled job starts with a minimal `PATH`; the clone needs a git identity; the runner shares the agent subscription with interactive work).

## Separation of concerns

- **The issue (what & why):** requirements as outcomes an outside observer can check, plus an explicit out-of-scope list. Settled at the issue stage, before a branch exists.
- **The failing tests (how you verify):** written from the issue's acceptance criteria, before any implementation, and run to watch them fail.
- **The implementation (how you build):** the minimum change that turns those tests green.
- **The review (did you honour it):** clean-context reviewers over the branch diff, confirming each criterion is met by an honest test.

### Specify the problem, not the solution
An issue fixes *outcomes and constraints*, not mechanism. "A searchable audit log retained seven years without slowing writes" beats "create table audit_log with these eight columns" (chrismdp). As a rule: **acceptance criteria must read as user-observable outcomes that hold under any reasonable implementation.** Over-specifying the solution upfront is waterfall with new branding, and produces brittle, implementation-mirroring tests. The default *Acceptance criteria* section carries the rule and its one exception, for a regression test pinning a named bug.

## Design principles

- **Single branch per feature, one mission.** Tests and implementation on one branch; commit history is the audit trail. When a second mission surfaces mid-flight, ship the first with documented known issues and open a separate branch.
- **PR review is the integrity gate.** The reviewer checks each acceptance criterion against the test that claims to cover it — not a binary pass/fail.

### Gates over rules
A rule the agent must *remember* is weaker than a gate the system *enforces*. Karpathy notes the common failure modes (silent assumptions, overcomplication, orthogonal edits, weak success criteria) persist "despite a few simple attempts to fix it via instructions in CLAUDE.md." When a correction recurs, promote it from a written rule to a mechanical gate. **Gates attach to actions, not prose:** no hook can see the agent *say* "all tests pass", so enforcement hangs off concrete actions (a test run, a commit, a PR creation), never claims.

Three corollaries:

- **Exclusions are amendment-level, not per-PR.** When a project deliberately excludes a tool or approach, record it as a *standing, named exclusion* that changes only by explicit amendment, and back it with a denylist gate so the excluded path is mechanically impossible. Left as prose, an agent re-derives the "reasonable" case for the excluded tool every time a gate blocks it.
- **Package operations as callable, self-documenting commands — not prose.** Anything the agent must do consistently, especially destructive or multi-step orchestration, belongs in one script or command, gated so the raw pieces can't be hand-assembled. Orchestration that lives only as prose gets re-enacted imperfectly and drifts.
- **Guard the files an upgrade will overwrite.** When a vendored tool installs files that then carry local customisations, a forced re-install silently resets them. Deny the agent's edit path on upstream-managed files and keep genuine extension points editable. That is why nothing in a consuming repository edits a plugin checkout: the fix goes here, by issue.

## Mechanical enforcement layer

The *verify* and *correct* duties, made automatic. The plugin ships one gate, `no-chmod`; the rest are the repository's, named under `CONVENTIONS.md` → *Hooks, scripts and plugins* and *Acceptance criteria* so the commands weigh them. The set worth having:

- **Stale-build guard.** Block running tests against stale binaries when sources changed since the last build; stale binaries produce lying green results.
- **The test-green gate.** The full suite must pass on the code about to become a PR. It is inside `/gaffer:verify`, not a hook (see *Where the completion gate belongs*).
- **Scenario traceability.** Where an issue labels a scenario, the test that covers it carries a matching marker, character for character. It needs a gate of its own, pre-merge, because the chain spans artefacts no single stage owns: the label is written at draft time, the marker at build time, and every stage in between edits the tests. Scope it to the one issue the branch implements, read off the branch name, and check one way only (label → marker): a scenario may legitimately be covered by a test that already existed. Fail it closed. The judgement half (invented markers, mock self-satisfaction, trivial passes) stays with the reviewers.
- **No skipped tests.** Skipped, ignored and conditionally-skipped tests (including *runtime* skips) are banned by a static gate — they fake coverage and rot the issue→test trace. Genuinely untestable scenarios go in a documented "untested branches" table.
- **CI on PR** *(where the suite can run in CI).* Build + test on every PR, blocking merge. If the real test stack can't run in hosted CI, keep the full gate local, let CI cover the deterministic subset, and say so.

### Where the completion gate belongs — at verify, not at turn-end

The instinct is a turn-end hook that won't let the *build* agent stop until the suite is green. It is the wrong seam. A turn-end hook can't run the suite itself — a full run takes minutes — so it consults a **ledger** recording that a green run happened at some past moment. That is a *proxy*: it attests the suite passed on earlier code, not on the code about to become a PR, and the plumbing it needs is substantial.

**Put the gate where the truth is: a real whole-suite run at verify time, on exactly the diff about to become a PR.** It removes more machinery than it adds, and the guarantee gets *stronger*. The general rule: **when a gate can only see a proxy for the property you care about, move the gate to where the property is observable.**

### How many green runs? One — and fix the flakiness instead

A tempting bar is *N consecutive* green runs. Resist it. **A multi-run bar is a crutch for a flaky suite, and prices every completion at N× the suite's wall-clock.** Set the bar at **one green whole-suite run since the last code change**, and *earn* it: if the suite is non-deterministic, hunt the flake.

### Formatting is not verification — do it at verify cadence

Formatting is cosmetic and doesn't belong on the inner loop. A format-on-commit hook taxes **every** commit — on a real codebase the tool's workspace load takes tens of seconds — to fix what no reviewer would catch. Run it in the verify flow, **once up front, then once more if the review applied edits, before the suite re-run**: at most two invocations per pull request, and every commit the flow makes is formatted. Run **the same command CI checks**, not a narrower subset of it, or a flow that formats with one command and is judged by another passes locally and fails on the pull request.

### Permissions and unattended runs

Claude Code's permission rules behave differently when nobody is there to answer a prompt; design unattended stages around that.

- **Pre-allow safe commands in checked-in settings** rather than disabling prompts wholesale (Boris Cherny): the agent flows, but high-stakes actions still surface.
- **`ask` rules outrank every permission mode.** `bypassPermissions` does not clear them; only removing the rule does. Subagents inherit the parent's mode, so a reviewer subagent stopped on a permission has hit an `ask` rule, not the subagent boundary.
- **Headless runs deny `ask` rules silently.** An `ask`-matched call prompts interactively, but a headless `claude -p` run can't prompt, so the call is denied and the worker carries on degraded. A green unattended run is not evidence its `ask` rules did no harm. If an unattended stage genuinely needs a command, give it an `allow` rule. The `no-chmod` hook exists for exactly one such case: `Bash(chmod:*)` on `ask` stalled interactive runs and vanished silently in headless ones, and a hook that refuses the call with the alternative named redirects the agent instead.
- **Headless runs show which rule matched, and nothing more.** Under `claude -p --dangerously-skip-permissions`, every call an `ask` or `deny` rule matches comes back denied, with no person to mask it — a test of rule matching, not of whether a person would have been asked.

## Context management

Output quality follows a curve (chrismdp): too little context gives generic slop; too much and the model drowns in noise and is confidently vague. Two habits:
- **Reset on drift.** Useless refactoring of working code, repeated wrong assumptions or going in circles mean start a fresh session: resetting is cheaper than correcting.
- **Plan mode first for non-trivial work** (Boris Cherny / Karpathy): agree the plan before auto-accepting edits. Reserve the issue stage for features; use lightweight plan mode for small changes.

**Prefer the tracker's own state as the progress ledger.** Open/closed, dependencies, labels and PR links are durable, shared, human-visible, and already what the team edits. A modern tracker resolves the dependency graph server-side, so "what is ready now" is a *query*, not a parser you maintain. Two practices follow:

- **Let the labels be the state.** When an automated step moves an issue forward, record where it stands in labels and the issue body. Give every combination exactly one meaning, including "the run did not finish", so the state reads off the issue without checking run logs. `needs answers` → `ready` is the issue stage's version of this.
- **The workflow checks its own results rather than trusting what the agent says.** An agent run usually reports success whenever the model finishes its turn, whatever it did. Check the post-conditions that matter (a label removed, a comment posted) and fail the run when they don't hold ([`ci.md`](ci.md)).

## The feedback loop (compounding engineering)

The trainer's job is to make next week's agent better than this week's:
- **Capture corrections as durable artifacts** — project-specific rules into the repository's `CONVENTIONS.md`, `REVIEW.md` and memory; generic ones into this plugin, by issue.
- **Do it continuously.** The strongest teams add to their shared instructions *several times a week*, the moment the agent goes wrong (Boris Cherny — "compounding engineering").
- **Prefer a gate to a memory entry** where the learning can be enforced mechanically. A correction that *could* have been a hook is a rule you will re-teach.

## Documentation hierarchy

- Tier 1: RULES → the project's stated rules and principles, each in one place (`CONVENTIONS.md`, `REVIEW.md`, a principles section of `CLAUDE.md`)
- Tier 2: IMPLEMENTATION → `CLAUDE.md` / `AGENTS.md` (essential patterns + signposts)
- Tier 3: DETAILED REFERENCES → `docs/…` deep guidance and/or a memory corpus

Keep Tier 2 short and high-signal. The commands read Tier 1 through the two rules files and Tier 2 through `CLAUDE.md`; they reach Tier 3 only where Tier 1 links it.

## Failure modes the harness defends against

| Failure mode (Karpathy / chrismdp) | Harness defence |
|---|---|
| Silent assumptions, no clarifying questions | plan-mode first; the review/confirm gates surface decisions before code |
| Overcomplication, bloated abstractions | slop review + simplifier sub-agent; "would a senior call this overcomplicated?" |
| Orthogonal edits (touching unrelated code) | one-mission branch; "mention dead code, don't delete it"; diff-scoped review |
| Weak success criteria | outcome-level ACs + a test seen failing for each + the verify gate (a real suite run before the PR) |
| Accidental vibe coding (ship unverified) | the mechanical enforcement layer; the verify gate's structural ordering |
| Review fatigue | move recurring issues into gates and this plugin, off the human's plate |
| Harness change locks out the harness | build gates fail-open with an override first, verify, then tighten |

## Modifying a harness

Harness changes can destroy the tool making the next change — a gate that blocks its own `git commit` is not hypothetical. Four rules, which this plugin follows for its own hook and a repository should follow for its:

1. **Test every hook standalone with synthetic input** before wiring it in. Every hook is a tested script with its own test cases, never an inline one-liner in settings: an untested gate can silently do nothing, which looks the same as a gate that passed. A Claude Code `PreToolUse` hook blocks only by exiting 2 or returning a JSON `permissionDecision: deny`; any other non-zero exit is reported and ignored.
2. **Build fail-open, with an override, first.** Verify no lock-out, *then* tighten to fail-closed.
3. **One mission per branch, its own PR.** Dogfood the workflow once the gate exists.
4. **A human reviews each hook before it lands.** Non-negotiable.
