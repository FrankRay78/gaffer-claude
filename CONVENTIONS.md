# Conventions

This repository's additions to the gaffer plugin's default conventions. Each section sits under a heading the plugin's `defaults/CONVENTIONS.md` documents and is read together with the plugin's section of the same name; this file wins where the two conflict. A section whose first line is exactly `Replaces the default.` is read instead of the plugin's section. Delete any section this repository has nothing to add under, and add a section under any heading of your own that a command should read.

## Build, test and format

- **Build-and-test command** — `bash hooks/no-chmod.tests.sh && bash chain/chain.tests.sh && bash chain/chain-next.tests.sh && bash chain/chain-local.tests.sh && bash init/setup.tests.sh`, run from the repository root — the test matrices listed under *Tests and checks* in [`docs/contributing.md`](docs/contributing.md), in that file's order. CI runs every committed `*.tests.sh`, discovered by name — [`.github/workflows/shell-tests.yml`](.github/workflows/shell-tests.yml).
- **Manifest check** — `claude plugin validate .`, after any edit to the manifests or the layout — [`docs/contributing.md`](docs/contributing.md); CI runs it in the `manifests` job of [`.github/workflows/shell-tests.yml`](.github/workflows/shell-tests.yml).

## Testing

- **Test matrices and what each specifies** — [`docs/contributing.md`](docs/contributing.md) → *Tests and checks*: each `*.tests.sh` sits beside the script it specifies and uses stubs, so nothing reaches GitHub; a command has no automated test.
- **Chain tests** — [`docs/chain.md`](docs/chain.md) → *Tests*.

## Code quality

- **What a change must keep to** — [`docs/contributing.md`](docs/contributing.md) → *What a change must keep to*: repository-agnostic command steps, review bindings in `REVIEW.md`, nothing project-specific, locality over DRY, `templates/` mirroring `defaults/`.

## Public API and breaking changes

- **The interfaces between the plugin and a repository** — [`docs/interfaces.md`](docs/interfaces.md), and the verdict schema in [`docs/verdict-schema.md`](docs/verdict-schema.md).
- **Versioning stance** — [`docs/contributing.md`](docs/contributing.md) → *What a change must keep to*: pre-1.0, breaking changes need no approval, and each pull request says what breaks and for whom.

## Documentation

- **Where an interface change is documented** — [`docs/contributing.md`](docs/contributing.md) → *What a change must keep to*: a heading, combination rule or assumed convention in [`docs/interfaces.md`](docs/interfaces.md); a verdict field in [`docs/verdict-schema.md`](docs/verdict-schema.md); a new command in the [`README.md`](README.md) table; an unattended command's outward-facing act or post-condition in [`docs/unattended.md`](docs/unattended.md).

## Change-intent records

This project keeps them. The convention is [`docs/conventions/change-intent-records.md`](docs/conventions/change-intent-records.md), whose decision table `/gaffer:build` runs, and records live in [`docs/change-intent-records/`](docs/change-intent-records/).

- **The `→ No CIR` rows that most often apply.** Reasoning already recorded in the issue's confirmed decisions is linked, not restated — unless the decision constrains future work (an interface in [`docs/interfaces.md`](docs/interfaces.md), the verdict schema, how the commands divide the work), which keeps a short record linking the issue for its reasoning. A change only to documentation written for the plugin's readers needs none at all; commands, `defaults/`, `templates/` and the chain scripts are not covered by that row, because they direct future work.
- **Length and shape.** About **150 words**: the intent in a sentence, each rejected alternative with its reason, and any constraint the code will not make obvious.
