# Conventions — plugin defaults

The generic conventions the gaffer commands run on when a repository says nothing. Each command's *Repository conventions* table names the headings it reads. For each heading a command reads this section first, then the section under the same heading in the repository's own `CONVENTIONS.md`, at the root of the repository the command runs in, and applies the two together: the repository's section is an addition to this one, and wins where the two conflict. A repository section whose first line is exactly `Replaces the default.` is read instead of this file's section, not with it. A repository with no `CONVENTIONS.md`, or no section under a heading, runs on this file's section alone. Where this file also has nothing under a heading — marked *No default* below — the step concerned runs on its generic rule alone, or, where the convention is the thing itself and there is no generic rule, stops and names the heading. A section under a heading this file does not have is read too, and applied where its text says.

This file is read from the plugin, never from the repository, so a repository cannot change a default by editing it; it extends or replaces a section in its own file. Keep a repository's file to what is particular to that repository: a rule stated here is not restated there, unless the repository also loads its file as session context (from `CLAUDE.md`, say), where a default restated is a rule every session sees rather than only a running command.

## Build, test and format

*No default for the build-and-test command.* A repository states, under this heading, the one command that builds and runs its whole test suite, run from the repository root; `/gaffer:build` and `/gaffer:verify` gate on its exit code. Without it both stop with the reason `conventions missing: Build, test and format`, because inventing a build command unattended is how a run reports green over nothing.

The default formatter is none. A repository that has one names it here, as the same command its CI checks, so what passes locally is what passes on the pull request. Where none is named, `/gaffer:verify` skips its format passes and says so in its report.

## Test-driven development

Every line of production code is written in response to a failing test, in the RED-GREEN-REFACTOR cycle: write the failing test that describes the behaviour and watch it fail; write the minimum code that passes and watch it pass; commit, then improve the design with the tests still passing. Never write production code without a failing test first, never skip the RED step, never refactor on red, never add a feature no test covers, and never proceed while tests are failing.

**Configuration, tooling and CI changes.** A change to configuration, tooling or CI is not production code, and its RED step is the real tool or gate failing. Run the tool before the change and capture the failure, make the change, run it again, and record both outcomes in the commit message or pull request body — that is the RED-GREEN evidence, and it is complete. Do not write a bespoke test to stand in for a tool that already performs the check: a hand-rolled reimplementation of a formatter, linter or config parser covers strictly less than the tool it imitates, carries its own bugs, and reports green when its own matching logic fails. Do make the check repeatable: where the tool can run in CI, add it there, so the invariant is gated rather than verified once.

## Testing

Tests are readable, independent, fast and deterministic, and unit tests mock external dependencies: network, filesystem and time. A new test follows the naming, structure and file-placement conventions of the tests beside it. No test in the suite may be skipped: a skipped test reports green while verifying nothing, and the gap it leaves is invisible in every report. A missing runtime dependency or unavailable external resource fails loudly, not skips; a destructive or environment-specific opt-in suite is gated by a category the runner excludes by default, never by a runtime skip.

A repository names here its test projects, naming scheme, testing guide, any snapshot convention, what not to test, and any hook that enforces the skipped-test ban.

## Acceptance criteria

- **Outcomes, not mechanism** — acceptance criteria and tests describe outcomes an outside observer can verify, not the mechanism that delivers them, so that multiple reasonable implementations of the same feature satisfy the same criteria and pass the same tests. The independence test: would this criterion or test still hold under a different reasonable implementation of the same feature? If not, it describes the mechanism. Mechanism includes, unless it is an interface contract: internal names and paths, data structures and storage, library and framework picks, algorithms and protocol choices, internal timings and polling cadences, log formats, and the exact wording of messages meant for people to read.
- **Interface contracts are outcomes** — a detail that users, their scripts or other programs work with directly is part of the outcome, and a criterion may name it exactly: a command, option or flag name; a config key; a field in machine-readable output; an exit code; a file format users write; a public library member; a route that clients call. The test is who touches it: if changing it would break a user, a script or a consumer, it is a contract.
- **Tests verify the criterion as written**, not the chosen implementation: a test that would fail under a different reasonable implementation of the same criterion is testing mechanism. Project housekeeping — a project exists, scaffolding is created — is a step on the way to a criterion, not one itself, and is left out. **Regression exception:** a criterion or test may pin a specific mechanism only when it exists to prevent a named, previously fixed bug; name the bug in the criterion text, the scenario name or a one-line comment in the test.
- **Scenario labels** — an issue may give a scenario a `**Scenario: <name>**` label on its own line, outside any code fence, with the Given / When / Then beneath it. Where one is present, at least one test carries a `SCENARIO: <name>` marker naming it exactly, in the test file's own comment syntax — `// SCENARIO: <name>` in a language whose comments open with `//`, `# SCENARIO: <name>` where they open with `#` — so what must match character for character is the name after `SCENARIO:`. Labels are optional: an issue may carry none, and that is not a defect; a label with no marker, or a marker naming no label, traces nothing. Never invent a marker. Leave a scenario unlabelled when only an external tool or gate can check it.
- **Traceability** — the default check is review: nothing mechanical verifies the label-to-marker pairing. A repository that gates it names its check here, and `/gaffer:build` runs that check before it reports ready.

## Code quality

No default rules beyond what the codebase shows: `/gaffer:build` follows the patterns in the files it touches, validates inputs early, never swallows an exception, leaves no commented-out code — delete it, git remembers — and leaves the build with no new warning. A repository states its standards, its cross-platform or runtime constraints, and any build-time guarantee here.

## Dependencies

No library is marked dependency-controlled by default. A repository that publishes a library, or otherwise controls what it depends on, names the library here and states its rule — justification, licence, preference for the standard library — so that `/gaffer:build` adds no dependency to it unattended, and stops where an issue cannot be built without one.

## Public API and breaking changes

No protected public API and no stance on breaking changes by default. A repository names here the surface its consumers depend on, and any versioning stance — a pre-1.0 stance that lifts the discussion duty on a breaking change, say — so that `/gaffer:build` knows which changes to call out and whether it may make them unasked.

## Commit messages

Work on feature branches, named `<prefix>/<N>-<short-slug>` after the issue, with `feature/` as the prefix `/gaffer:build` uses. Messages are clear and concise, in the imperative mood, and reference the issue where applicable as `Refs #<N>: <imperative>` — never a GitHub closing keyword (`Fix`/`Fixes`/`Close`/`Closes`/`Resolve`/`Resolves` `#<N>`), which closes the issue the moment the commit reaches the default branch, before review. The pull request body's `Closes #<N>` is the only place that should close an issue.

## Documentation

No standing obligations by default: a change corrects any document it makes false, and owes nothing else. A repository lists here what a kind of change owes — a user guide for a changed option, API docs for a public member, a release document for a pipeline change — and `/gaffer:build` discharges every obligation its change triggers, and no more.

## Change-intent records

This project keeps none by default, so `/gaffer:build` writes none and `/gaffer:raise-pr` links none. A repository that keeps them says so here, names the convention whose decision table `/gaffer:build` runs, and says where the records live.

## Scratch files

`.claude/scratch/` at the repository root, git-ignored; the `Write` tool creates it when it is missing. The files the commands write there: `/gaffer:verify` its draft of the pull request body to `raise-pr-body.md`, first line `<!-- gaffer:verify <sha> -->`, and the simplifier's edits to `verify-simplifier.patch`; `/gaffer:raise-pr` the pull request body to `raise-pr-body.md`, reading verify's draft from there first; `/gaffer:draftissue` the issue body to `gh-issue-body-<slug>.md`, where the slug is a short kebab-case form of the title; `/gaffer:reviewissue` the review comment to `reviewissue-body.md`; `/gaffer:confirmissue` the issue body to `confirmissue-body.md` and the patch to `confirmissue-patch.json`; `/gaffer:review-pr` its review to `review-pr-<N>.json` and a worktree to `review-pr-<N>/`; `/gaffer:audit-codebase` its working files under `audit/`. A repository that keeps scratch files elsewhere, or ignores them differently, says so here.

## Pull requests

No check on the issue link by default. A repository that fails or flags a pull request closing no issue names the check here, so `/gaffer:raise-pr` can say when its abstain turns that check red.

## Issue sources

No backlog by default. `/gaffer:draftissue` asks the user where a `backlog <number>` or `item <number>` argument refers to; a repository that keeps a backlog names it here, says how to read a row and whatever the page says about it elsewhere, and how the issue's Related section links it.

## Issue concerns

Nothing beyond `/gaffer:draftissue`'s generic categories by default. A repository lists here the requirements decisions its issues must settle that the generic categories do not reach — which consumers a feature is offered to, which output modes are in scope, what documentation an option change owes, what a breaking change must state.

## Issue review checks

Nothing beyond `/gaffer:reviewissue`'s generic categories by default. A repository lists here the checks its issues must answer beyond them, under the same test: raise a gap only where the issue leaves the point open.

## Audit

By default `/gaffer:audit-codebase` reads every tracked file, takes no evidence beyond the build-and-test command under *Build, test and format*, holds the code to the rules under the headings above and whatever `CLAUDE.md` states as the project's rules, knows nothing about the tree in advance, and raises its issue with no label. A repository that has more says so here: the paths in scope, an evidence table of the tools that already decide a question, the rules each lens audits, what each lens should know about this tree before it starts (a known flaky test, symbols a generator consumes, fixtures that look like traceability markers), and the one label the issue carries.

## Hooks, scripts and plugins

The plugin ships one hook, `no-chmod`, registered on every Bash call: it refuses a `chmod` that would set the executable bit and names `bash script.sh` as the alternative. A plugin cannot set permission rules, so a repository keeps `Bash(chmod:*)` on `permissions.ask` in its own `.claude/settings.json` as the fail-open backstop for the forms the hook declines to decide. The review agents `/gaffer:verify` and `/gaffer:review-pr` start ship with gaffer; the simplifier `/gaffer:verify` also runs comes from the `pr-review-toolkit` plugin, which the repository installs. No hook re-runs the suite when a pull request is created, and no hook blocks a commit, unless the repository adds one and names it here with whatever else of its own it wires in.
