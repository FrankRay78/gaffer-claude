# The workflow

How the stages fit together, where a person decides, and why they are shaped this way. The commands' own prompts hold the detail; this is the map.

**In one line:** draft, review and confirm an issue → build it → verify → raise the PR → review → merge.

The approach is a *harness*: an agent constrained by context, feedback loops and mechanical gates, so the agent does the work and the engineer reviews it. When an agent struggles with trivial work, treat it as a harness failure, not a prompt failure. The bottleneck has moved from generation to verification, so the harness's main job is giving the agent — and the reviewer — a fast, trustworthy way to tell whether the work is right.

*Inspired by* [Coding with AI](https://www.chrismdp.com/coding-with-ai/) (Chris Parsons), [Harness Engineering](https://openai.com/index/harness-engineering/) (OpenAI), [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) (Anthropic), and field notes from Andrej Karpathy and Boris Cherny.

## The stages

**Once per repository**, and again whenever you want a report of what is missing: `/gaffer:init` sets the repository up from what it already contains and raises the result as a pull request to edit or discard.

**The issue stage**, on `main`, with a person:

1. `/gaffer:draftissue` (optional) — an idea, a document or a backlog item becomes a needs-first issue: user, job, scenarios, scope, acceptance criteria. No technical design.
2. `/gaffer:reviewissue` — reads the codebase and posts the gaps the issue leaves open, each with a recommendation. The author answers inline.
3. `/gaffer:confirmissue` — folds the answers into *Confirmed decisions* and labels the issue `ready`.

The confirmed issue **is** the specification. There is no separate spec, plan or task list.

**The build chain**, unattended:

4. `/gaffer:build <N>` — branch, failing tests first, implementation, docs, all committed. Ends on a green, committed branch.
5. `/gaffer:verify` — format, whole suite (the gate), one review by the same agents `review-pr` uses, fix, one narrow check of the fixes, re-run, commit, then draft and check the PR body. Ends on a green, reviewed branch with its body drafted; does not push.
6. `/gaffer:raise-pr` — push and open the PR. A separate stage because it is the one outward-facing act; everything before it is safe to re-run.

**The review**, asynchronous:

7. `/gaffer:review-pr` — a verified multi-pass review of the open PR, with a risk tier and a verdict on whether it may merge with no human review. `/gaffer:review-followup` runs later rounds. A person merges.

**Periodic**, not per feature: `/gaffer:capture-learnings` at a supervised checkpoint after several features; `/gaffer:audit-codebase` and `/gaffer:audit-deadcode` after a batch of merges or before a release; `/gaffer:context-gardening` quarterly.

## Why it is shaped this way

- **Specify the problem, not the solution.** Acceptance criteria are outcomes an outside observer can check, which hold under any reasonable implementation. Mechanism in a criterion produces tests that mirror the implementation and lock the code to its current shape.
- **RED is proven by the real tool.** A failing test is seen to fail before the code exists. For a configuration or tooling change, RED is the real tool failing before and passing after — never a stand-in test that reimplements the tool's check.
- **The suite is the gate, and it runs first.** `/gaffer:verify` runs the whole suite before anything else, so review cannot start on red code. The ordering is structural; no hook polices it. One green whole-suite run since the last change is the bar — if the suite is flaky, fix the flake rather than demanding several runs.
- **Gates attach to actions, not prose.** No hook can see an agent *say* "all tests pass", so enforcement hangs off a test run, a commit, a PR creation. When a gate can only see a proxy for the property you care about, move the gate to where the property is observable — which is why the completion gate is a real suite run at verify, not a turn-end hook.
- **Format at verify cadence, with the command CI checks.** Once before the suite, once more if the review changed anything. Formatting on every commit taxes every commit to fix what no reviewer would catch.
- **Review once, in clean context, and keep the fix small.** Reviewers see the diff, not the conversation. A finding is checked before it is acted on; a severity may be raised, never lowered. The review's fix is not re-reviewed by the same stage — looping found as much in each fix as in the branch — so it is held to the smallest change that removes the defect, and the PR review reads it.
- **Two reviews, one standard.** Review A is inside `/gaffer:verify`, synchronous. Review B is `/gaffer:review-pr` on the opened PR, for the person who merges. Both start the same review agents against the same `REVIEW.md`, so B should find little that A did not; what A deliberately left is stated in the PR body. Nothing waits on B.
- **One mission per branch.** When a second mission surfaces mid-flight, ship the first with a known issue and open another branch.
- **Check results, don't trust reports.** An agent run reports success whenever the model finishes its turn. Every unattended use checks the post-condition that matters — a verdict, a posted review, a label — and fails when it does not hold.

## Running the chain

Every stage after the issue stage runs without prompting, so a script can take one issue from a clean `main` to an open PR. [`chain.md`](chain.md) is that script, and the runner that fires it from a timer. What it is built to do, which anything else driving the stages must do too:

- **Run each stage as its own headless process** (`claude -p "/gaffer:build <N>"`), reaching the next only through the previous stage's verdict and the state it left on the branch.
- **Gate on the verdict, read by position.** Start the next stage only on the previous one's success verdict; stop at the first failure, an unreadable verdict, an unknown schema version, an agent error or a timeout. [`verdict-schema.md`](verdict-schema.md) is how to read it.
- **Load the plugin from a checkout it controls**, so every stage in one run comes from one known commit — the chain loads the checkout it is part of.
- **Move the human decision to the start.** The chain opens a PR without a pause; the person's decision is starting it against one named issue, or confirming an issue where a runner builds every confirmed one. Run `verify` and `raise-pr` by hand to keep the pause.
- **Expect silent degradation.** A headless run denies `ask`-matched calls without a prompt, so a stage can carry on degraded and still report success ([`unattended.md`](unattended.md)); skipping permissions removes that and everything else, and is an opt-in with conditions ([`chain.md`](chain.md), *Permissions*).

## The feedback loop

Make next week's agent better than this week's. Capture a correction the moment it happens: project rules into the repository's `CONVENTIONS.md`, `REVIEW.md` and memory; generic ones into this plugin, by issue. Prefer a gate to a memory entry wherever the learning can be enforced — a correction that could have been a hook is a rule you will re-teach.

## Changing a harness

A gate can lock out the tool making the next change. Test every hook standalone, with synthetic input, before wiring it in; build it fail-open with an override first and tighten once there is no lock-out; give it its own branch; and have a person review it before it lands.
