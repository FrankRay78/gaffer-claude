# Review criteria

This repository's additions to the gaffer plugin's default review criteria. Each section sits under a heading the plugin's `defaults/REVIEW.md` documents — the part of `/gaffer:review-pr`'s method it extends — and is read together with the plugin's section of the same name; this file wins where the two conflict. A section whose first line is exactly `Replaces the default.` is read instead of the plugin's section. Delete any section this repository has nothing to add under. In CI the review reads the default branch's copy of this file, never the pull request's, so a change here takes effect on merge, and is itself a change that always needs the maintainer.

## What not to flag

- **The `shell-tests` gate** — every committed `*.tests.sh` passing, every tracked JSON file parsing, and `claude plugin validate .` — [`.github/workflows/shell-tests.yml`](.github/workflows/shell-tests.yml).

## Contracts

- **The interfaces between the plugin and a repository** — [`docs/interfaces.md`](docs/interfaces.md).
- **The verdict schema** — [`docs/verdict-schema.md`](docs/verdict-schema.md).
- **The chain settings file** — [`docs/chain.md`](docs/chain.md) → *The settings file*.
- **Unattended commands' outward-facing acts** — [`docs/unattended.md`](docs/unattended.md).

## Context to load

- **Rules for changing the plugin** — [`docs/contributing.md`](docs/contributing.md).
- **The interfaces with a repository** — [`docs/interfaces.md`](docs/interfaces.md).
- **The chain scripts** — [`docs/chain.md`](docs/chain.md).
- **How the stages fit together** — [`docs/workflow.md`](docs/workflow.md).

## Change map

- **Top-level directories** — [`docs/contributing.md`](docs/contributing.md) → *Layout*: `.claude-plugin/`, `commands/`, `skills/`, `hooks/`, `chain/`, `init/`, `defaults/`, `templates/`, `docs/`.

## Tests

- **Test matrices and what each specifies** — [`docs/contributing.md`](docs/contributing.md) → *Tests and checks*.
