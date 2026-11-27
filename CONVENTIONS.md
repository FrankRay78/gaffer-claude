# Conventions

This repository's additions to the gaffer plugin's default conventions. Each section sits under a heading the plugin's `defaults/CONVENTIONS.md` documents and is read together with the plugin's section of the same name; this file wins where the two conflict. A section whose first line is exactly `Replaces the default.` is read instead of the plugin's section. Delete any section this repository has nothing to add under, and add a section under any heading of your own that a command should read.

This repository is mostly prose: the commands, skills, defaults, templates and docs are Markdown an agent reads, and its only code is the shell scripts and their test matrices. The sections below say how the chain's stages treat each.

## Build, test and format

- **Build-and-test command** — `git ls-files -z --cached --others --exclude-standard '*.tests.sh' | xargs -0 -n1 bash && git ls-files -z '*.json' | xargs -0 -n1 jq -e . > /dev/null && claude plugin validate . && bash .github/scripts/link-check.sh`, run from the repository root: every test matrix, committed or not, then every JSON file parsing and the plugin layout validating, then the link check. It runs what CI runs — [`.github/workflows/shell-tests.yml`](.github/workflows/shell-tests.yml) and [`.github/workflows/link-check.yml`](.github/workflows/link-check.yml) — and must never check less, because on a Markdown change it is the whole gate (*Test-driven development*).
- **Single-test command** — `bash <path>`, one matrix per path. A matrix is the smallest unit this repository runs; each is stubbed and deterministic.

## Test-driven development

- **A Markdown change has no RED step.** No test here can fail on a `*.md` file before an edit and pass after it, so `/gaffer:build` makes the edit the acceptance criteria call for, runs the build-and-test command, which must be green, and commits. In place of RED evidence its final report says: `No RED step: Markdown change (CONVENTIONS.md → Test-driven development)`.
- **Never write a test that checks a Markdown file's wording**, or that a sentence or heading is present. It pins mechanism, CI runs it from then on, and it stays green whatever the prose now tells an agent to do. The one test a Markdown change may add is a check of an invariant across the whole tree, as [`skills/tracker.tests.sh`](skills/tracker.tests.sh) and the link check are, where an acceptance criterion is that invariant.
- **A shell script is built test-first**, under the default rule, against the matrix beside it — [`docs/contributing.md`](docs/contributing.md) → *Tests and checks*. An issue that changes both a script and Markdown builds each part its own way.

## Testing

- **Test matrices and what each specifies** — [`docs/contributing.md`](docs/contributing.md) → *Tests and checks*: each `*.tests.sh` sits beside the script it specifies and uses stubs, so nothing reaches GitHub; a command has no automated test.
- **A Markdown file has no test, by design.** `/gaffer:verify` and `/gaffer:pre-review` reject as not real a finding that a command, skill, default, template or doc lacks one.
- **Chain tests** — [`docs/chain.md`](docs/chain.md) → *Tests*.

## Acceptance criteria

- **`SCENARIO:` markers go only in a `*.tests.sh` file**, never in a Markdown file: commands, skills and defaults are loaded as prompts. A scenario that only a Markdown change satisfies gets no marker, and `/gaffer:build`'s final report says so.

## Code quality

- **What a change must keep to** — [`docs/contributing.md`](docs/contributing.md) → *What a change must keep to*: repository-agnostic command steps, review bindings in `REVIEW.md`, nothing project-specific, locality over DRY, `templates/` mirroring `defaults/`.
- **Review A covers the scripts only.** The `pr-review-toolkit` reviewers and `/gaffer:review-slop` review code, so on a branch whose diff touches only `*.md` files none of them applies: `/gaffer:verify`'s step 2 spawns none, and its final report says Review A was skipped under this section. On a branch that also changes a script, they review the scripts alone, and `pr-review-toolkit:type-design-analyzer` does not apply. The Markdown is reviewed against this repository's own rules by `/gaffer:pre-review`'s dry run and the review on the pull request ([`REVIEW.md`](REVIEW.md)).

## Public API and breaking changes

- **The interfaces between the plugin and a repository** — [`docs/interfaces.md`](docs/interfaces.md), and the verdict schema in [`docs/verdict-schema.md`](docs/verdict-schema.md).
- **Versioning stance** — [`docs/contributing.md`](docs/contributing.md) → *What a change must keep to*: pre-1.0, breaking changes need no approval, and each pull request says what breaks and for whom.

## Documentation

- **Where an interface change is documented** — [`docs/contributing.md`](docs/contributing.md) → *What a change must keep to*: a heading, combination rule or assumed convention in [`docs/interfaces.md`](docs/interfaces.md); a verdict field in [`docs/verdict-schema.md`](docs/verdict-schema.md); a new command in the [`README.md`](README.md) table; an unattended command's outward-facing act or post-condition in [`docs/unattended.md`](docs/unattended.md).
