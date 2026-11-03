# Contributing

How this plugin is changed. It has one author and a short list of repositories that consume it, so the rules here are the ones that keep those repositories working, not a process for its own sake.

## What a change must keep to

- **A command's steps are repository-agnostic.** Nothing in a command, or in the chain scripts, names a build tool, a path, a test framework, a product rule or an account; what the chain takes from a repository, it reads from the settings file [`chain.md`](chain.md) describes. Every repository binding goes into [`defaults/CONVENTIONS.md`](../defaults/CONVENTIONS.md) or [`defaults/REVIEW.md`](../defaults/REVIEW.md), under a heading the command documents in its *Repository conventions* or *Repository criteria* table, and the command reads the section as an addition to its own generic rule. A failure reason names no project tool: `formatting failed`, not the formatter's name. The harness itself stays in the steps — the verdict protocol, sibling command names, how a reader finds the verdict — because whoever edits the protocol must see what consumes it.
- **Review bindings live in `REVIEW.md`, not `CONVENTIONS.md`.** `/gaffer:review-pr` and `/gaffer:review-followup` read criteria rather than tools and paths, so their repository-side additions and their defaults sit in the review file, under the heading of the part of the method each extends.
- **Nothing project-specific survives.** `grep` the diff for the names of consuming repositories, their stacks and their owners before raising a pull request. The plugin reads as if written for any repository. The one exception is the README's *Used by* section, which names consuming repositories on purpose.
- **An interface change is documented where the interface is.** A new heading, a changed combination rule or a new assumed convention goes into [`interfaces.md`](interfaces.md); a new verdict field goes into [`verdict-schema.md`](verdict-schema.md) under its rules for adding a field or bumping the version; a new command goes into the README's table, and a new or changed outward-facing act or post-condition of an unattended command into [`unattended.md`](unattended.md). Docs describe what the plugin does today and nothing planned.
- **A command favours locality over DRY.** A running command loads only its own prompt, so each one states the rules it needs inline: a short rule repeated in three commands is better than one canonical section the others point to, which an agent may not follow. Centralise only a rule too long to paraphrase without drift. Don't defend a reader against input that nothing on its path produces — where the commands write both ends of a convention, the reader accepts the shapes the writer emits and no more. After adding a rule to a command, search the command for the older rules it overrides and every path it applies to (first run, re-run, unattended), and reconcile them in the same change.
- **`templates/` mirrors `defaults/`.** Each template has exactly the `## ` headings of the default file of the same name, in the same order: `/gaffer:init` takes its heading list from the templates, so a heading added to a default and not to its template drops out of what init looks for.
- **Pre-1.0: breaking changes need no approval, and each pull request says what breaks and for whom.** That line in the pull request body is the whole notice a consumer gets, so write it even when the answer is "nothing".
- **Learnings arrive by issue.** A consuming repository that finds a command wrong raises an issue or pull request here; it never edits a plugin checkout. When you fix one, say which repository and run showed it, so the fix can be checked against the case.

## Tests and checks

- `bash hooks/no-chmod.tests.sh` after any edit to the hook. The matrix is the hook's specification: every refused and allowed form, the known limits, and the wiring in `hooks.json`.
- `bash chain/chain.tests.sh` and `bash chain/chain-next.tests.sh` after any edit to the chain. The first is the specification of how a verdict is read; the second, of what the runner selects and what a failure leaves behind. Both use stubs, so nothing is spent and nothing reaches GitHub.
- `bash init/setup.tests.sh` after any edit to `init/setup.sh`. The matrix is the specification of what `/gaffer:init` sets up and what it leaves alone; it uses a stub `gh`, so nothing reaches GitHub.
- `claude plugin validate .` after any edit to the manifests or the layout.
- CI ([`.github/workflows/shell-tests.yml`](../.github/workflows/shell-tests.yml)) runs every committed `*.tests.sh`, discovered by name, and validates the manifests. A script that gains a matrix is gated the moment the matrix is committed. The `shell-tests` job is the one stable check name.
- A command has no automated test. Try a changed command in a consuming repository with `claude --plugin-dir <this checkout>` before merging, and say in the pull request what you ran.

## `main` is protected

Nothing lands on `main` except by a pull request whose checks have passed: no direct pushes, no force pushes, no deletion, squash merges only. Consuming repositories' CI installs the plugin from `main` at the start of each job and trusts what it finds there, which is why the branch is protected the moment the repository is public. The ruleset is kept in [`.github/ruleset-main.json`](../.github/ruleset-main.json) so it can be read, diffed and re-applied:

```bash
gh api -X POST repos/FrankRay78/gaffer-claude/rulesets --input .github/ruleset-main.json
```

To change it, edit the file, apply with `gh api -X PUT repos/FrankRay78/gaffer-claude/rulesets/<id> --input .github/ruleset-main.json`, and commit the file in the same change.

## Layout

```
.claude-plugin/   plugin.json and marketplace.json
commands/         the slash commands, one markdown file each
hooks/            hooks.json, no-chmod.sh and its test matrix
chain/            chain.sh, chain-next.sh and their test matrices
init/             setup.sh and its test matrix
defaults/         the CONVENTIONS.md and REVIEW.md the commands run on when a repository says nothing
templates/        copyable starting points for a repository's own two files
docs/             the guides
```

Commands are kept as `commands/*.md` rather than skills: each is a workflow a person invokes by name, with no supporting files, and the move from a repository's `.claude/commands/` was a move, not a rewrite.
