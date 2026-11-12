# Review criteria — plugin defaults

The generic criteria `/gaffer:review-pr` and `/gaffer:review-followup` apply when a repository says nothing. The command holds the method — severities, tiers, dimensions, verification, the verdict — and its *Repository criteria* table names the part of the method each heading extends. For each heading the review reads this section first, then the section under the same heading in the repository's own `REVIEW.md`, at the root of the repository the command runs in, and applies the two together: the repository's section is an addition to this one, and wins where the two conflict. A repository section whose first line is exactly `Replaces the default.` is read instead of this file's section, not with it. A repository with no `REVIEW.md`, or no section under a heading, runs on this file's section alone; a section under a heading this file does not have is read too, and applied where its text says. Either way the review completes.

This file is read from the plugin, never from the repository. A repository's own file is read from the root of the repository the command runs in — in CI, the checkout, where a workflow puts the default branch's copy before the agent starts — never from a worktree made for the review, so a pull request cannot weaken the rules it is reviewed against. A change to a repository's `REVIEW.md` is itself never eligible for merge with no human review.

## Where it runs

By default the review is run by hand — `/gaffer:review-pr <N>` and `/gaffer:review-followup <N>` — and posts under the invoker's own `gh` account; no CI workflow triggers either, and no cost is recorded on the pull request. A repository that runs them in CI says here which workflow runs which command, on what trigger, as whom, and how it puts the default branch's copy of this repository's `REVIEW.md` and `CONVENTIONS.md` in place before the agent starts.

## Severity

- **Critical** — wrong results, data loss, a crash on a supported path, a security hole, or a broken gate (a CI check or hook that passes when it should fail). Blocks merge.
- **Major** — a real defect on a less common path, a missing test for new behaviour, a breach of a rule the repository states as mandatory, or an unstated breaking change. Should be fixed before merge.
- **Minor** — worth fixing, but merging without it does no harm.

A repository says here which of its own rules count as mandatory, so a breach is Major: the codebase rules under its `CONVENTIONS.md` headings, the principles its `CLAUDE.md` states. It may also add examples of a mechanical note particular to this repository, beyond those `/gaffer:review-pr`'s *Review contract* defines.

## What not to flag

- Formatting and style the formatter or `.editorconfig` already settles.
- Anything a required CI check already gates, unless the check itself is what the PR breaks. By default no check is known: a repository lists its gated checks here.
- Preferences with no consequence a reader could name.

A repository adds here what it has settled — a stance on breaking changes, a message it has decided not to require — so the review does not raise it.

## Risk tier

- **Low** — docs, tests or mechanical changes only (renames, moved files, generated code, lockfiles).
- **Medium** — anything that is neither Low nor High: real logic.
- **High** — security-sensitive code, or a change large enough to span several layers.

A repository names here the areas whose logic makes a change High, and any kind of change that is never Low — a changed snapshot of user-visible output, say.

## Always a person

- the Claude harness — anything under `.claude/` — and `CLAUDE.md`
- `REVIEW.md`, the criteria this review applies, and `CONVENTIONS.md`, the conventions the other commands read
- any change to a contract a user or a consumer relies on, as the *Contracts* dimension defines one

A repository adds here the paths that need the maintainer whatever the tier: its CI and scripts, its release pipeline, its dependency manifests.

## Contracts

Anything a user, a script or a consumer touches directly: a command-line option, an exit code, a field in machine-readable output, a public member of a published library, a route clients call, a file format users write. A change to a contract must be stated in the PR body with who it breaks. A repository names here what that is for it, and the user-facing documents a change to one must update.

## Context to load

`CLAUDE.md` and `CONVENTIONS.md` from the checkout, where they exist. A repository lists here the documents to read for the layers a PR touches — a style guide for one language, a testing guide for tests.

## Change map

The areas the repository's layout shows: top-level directories and projects, tests, CI and scripts, the harness under `.claude/`, docs. A repository lists its own areas here.

## Tests

A finding is judged against the test conventions under `CONVENTIONS.md` → *Testing* and *Acceptance criteria*: tests exercise the new behaviour and its edge cases, not only the happy path; a test that mocks away the system under test, asserts mechanism rather than outcome, or is skipped is a finding. A repository adds here the conventions of its own — a snapshot rule, a naming scheme — a reviewer should hold tests to.
