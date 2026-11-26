# Contributing

How this plugin is changed. It has one author and a short list of repositories that consume it, so the rules here are the ones that keep those repositories working, not a process for its own sake.

## What a change must keep to

- **A command's steps are repository-agnostic.** Nothing in a command, or in the chain scripts, names a build tool, a path, a test framework, a product rule or an account; what the chain takes from a repository, it reads from the settings file [`chain.md`](chain.md) describes. Every repository binding goes into [`defaults/CONVENTIONS.md`](../defaults/CONVENTIONS.md) or [`defaults/REVIEW.md`](../defaults/REVIEW.md), under a heading the command documents in its *Repository conventions* or *Repository criteria* table, and the command reads the section as an addition to its own generic rule. A failure reason names no project tool: `formatting failed`, not the formatter's name. The harness itself stays in the steps — the verdict protocol, sibling command names, how a reader finds the verdict — because whoever edits the protocol must see what consumes it.
- **A command reaches the tracker only through the skill.** A command names a tracker operation as `tracker: <operation> <arguments>`, outside any `bash` block, and tells the agent near its top to load the `gaffer:tracker` skill before the first one; [`skills/tracker/SKILL.md`](../skills/tracker/SKILL.md) is the only file that says how an operation is carried out. Outside that file, no command, default, template or script makes a GitHub issue call, an issue REST call or a label call, and no command or chain script names a GitHub label or a closing keyword: a command names a state, and writes the line `pr-reference` gives. The unattended runner, `chain/chain-next.sh`, is exempt, since it selects and parks issues on GitHub itself. So is `.github/`, this repository's own CI, which ships to no consuming repository. `skills/tracker.tests.sh` holds the calls: it reads them from the skill file's `bash` fences and fails when anything else makes one. Labels and closing keywords are held at review ([`tracker.md`](tracker.md)).
- **Review bindings live in `REVIEW.md`, not `CONVENTIONS.md`.** `/gaffer:review-pr` and `/gaffer:review-followup` read criteria rather than tools and paths, so their repository-side additions and their defaults sit in the review file, under the heading of the part of the method each extends. One exception is the comment rule: it lives under `CONVENTIONS.md` → *Code quality*, which the review reads too, so a repository states it once for the commands that write comments and the ones that judge them.
- **Nothing project-specific survives.** `grep` the diff for the names of consuming repositories, their stacks and their owners before raising a pull request. The plugin reads as if written for any repository. Two places name a consuming repository on purpose: the README's *Used by* section, and [`review-trial.md`](review-trial.md), whose subject is measuring a review change against a consuming repository's merged pull requests.
- **An interface change is documented where the interface is.** A new heading, a changed combination rule or a new assumed convention goes into [`interfaces.md`](interfaces.md); a new verdict field goes into [`verdict-schema.md`](verdict-schema.md) under its rules for adding a field or bumping the version; a new command goes into the README's table, and a new or changed outward-facing act or post-condition of an unattended command into [`unattended.md`](unattended.md). Docs describe what the plugin does today and nothing planned.
- **A command favours locality over DRY.** A running command loads only its own prompt, so each one states the rules it needs inline: a short rule repeated in three commands is better than one canonical section the others point to, which an agent may not follow. Centralise only a rule too long to paraphrase without drift. Don't defend a reader against input that nothing on its path produces — where the commands write both ends of a convention, the reader accepts the shapes the writer emits and no more. After adding a rule to a command, search the command for the older rules it overrides and every path it applies to (first run, re-run, unattended), and reconcile them in the same change.
- **`templates/` mirrors `defaults/`.** Each template has exactly the `## ` headings of the default file of the same name, in the same order: `/gaffer:init` takes its heading list from the templates, so a heading added to a default and not to its template drops out of what init looks for.
- **Pre-1.0: breaking changes need no approval, and each pull request says what breaks and for whom.** That line in the pull request body is the whole notice a consumer gets, so write it even when the answer is "nothing".
- **Learnings arrive by issue.** A consuming repository that finds a command wrong raises an issue or pull request here; it never edits a plugin checkout. When you fix one, say which repository and run showed it, so the fix can be checked against the case.

## Tests and checks

- `bash hooks/no-chmod.tests.sh` after any edit to the hook. The matrix is the hook's specification: every refused and allowed form, the known limits, and the wiring in `hooks.json`.
- `bash chain/chain.tests.sh` and `bash chain/chain-next.tests.sh` after any edit to the chain. The first is the specification of how a verdict is read; the second, of what the runner selects and what a failure leaves behind. Both use stubs, so nothing is spent and nothing reaches GitHub.
- `bash init/setup.tests.sh` after any edit to `init/setup.sh`. The matrix is the specification of what `/gaffer:init` sets up and what it leaves alone; it uses a stub `gh`, so nothing reaches GitHub.
- `bash skills/tracker.tests.sh` after any edit to the tracker skill, a command or a script. It reads each call in a `bash` fence of [`skills/tracker/SKILL.md`](../skills/tracker/SKILL.md) and fails when a command, default, template or script makes one, the runner and `.github/` excepted. It names no tracker of its own, so it needs no edit when the skill file is replaced.
- `bash .github/scripts/link-check.tests.sh` after any edit to `.github/scripts/link-check.sh`, and `bash .github/scripts/link-check.sh` after renaming or deleting a file or heading anything links to. The matrix is the specification of which references are read and how a heading is matched; the check itself reads the checkout and nothing else, so it needs no network.
- `claude plugin validate .` after any edit to the manifests or the layout.
- CI ([`.github/workflows/shell-tests.yml`](../.github/workflows/shell-tests.yml)) runs every committed `*.tests.sh`, discovered by name, and validates the manifests. A script that gains a matrix is gated the moment the matrix is committed. The `shell-tests` job is the one stable check name for all of it; the link check reports as `link-check` ([*Continuous integration*](#continuous-integration)).
- A command has no automated test, and the tracker skill has none of what its calls do: after an edit to [`skills/tracker/SKILL.md`](../skills/tracker/SKILL.md), check it is still at most 1,500 words with `wc -w`. Try a changed command in a consuming repository with `claude --plugin-dir <this checkout>` before merging, and say in the pull request what you ran. To measure a change to `/gaffer:review-pr` against `main` — its cost and what it finds — follow [`review-trial.md`](review-trial.md).

## `main` is protected

Nothing lands on `main` except by a pull request whose checks have passed: no direct pushes, no force pushes, no deletion, squash merges only. Consuming repositories' CI installs the plugin from `main` at the start of each job and trusts what it finds there, which is why the branch is protected the moment the repository is public. The ruleset is kept in [`.github/ruleset-main.json`](../.github/ruleset-main.json) so it can be read, diffed and re-applied:

```bash
gh api -X POST repos/FrankRay78/gaffer-claude/rulesets --input .github/ruleset-main.json
```

To change it, edit the file, apply with `gh api -X PUT repos/FrankRay78/gaffer-claude/rulesets/<id> --input .github/ruleset-main.json`, and commit the file in the same change.

## Continuous integration

These are this repository's own workflows, under [`.github/workflows/`](../.github/workflows/). The plugin ships none to a consuming repository.

- **`shell-tests`** — every committed `*.tests.sh` and the manifest checks, on every pull request to `main` and every push to it ([`shell-tests.yml`](../.github/workflows/shell-tests.yml)).
- **`link-check`** — every markdown link in a tracked `*.md` file that points at a file in this repository resolves on the branch, as does the `#heading` it names and a heading named in prose directly after it (`[file](path) → *Heading*`), on every pull request to `main` ([`link-check.yml`](../.github/workflows/link-check.yml), running [`.github/scripts/link-check.sh`](../.github/scripts/link-check.sh)). A full link to a path on `main` is mapped onto the checkout; nothing is fetched.
- **Review** — `/gaffer:review-pr` on a pull request the maintainer opens from a branch of this repository, once it is opened ready or marked ready ([`review-pr.yml`](../.github/workflows/review-pr.yml)); `/gaffer:review-followup` when the maintainer adds the `review-followup` label to one ([`review-followup.yml`](../.github/workflows/review-followup.yml)). Both follow the shape in [`unattended.md`](unattended.md) → *In CI*: a fork's pull request and anyone else's are skipped, `main`'s `REVIEW.md` and `CONVENTIONS.md` are put in place, the commands run from a clone of `main` rather than the pull request's copy, a run that posts no `<!-- review-pr -->` review on the commit it checked out ends red, and the two share one queue per pull request. A review re-runs by hand from *Run workflow* on the Review PR workflow, given the PR number. The follow-up removes its label when the run ends, pass or fail, so each round is started by adding it again.
- **`@claude`** — a conversation comment by the maintainer on an issue or pull request that contains `@claude` gets an answer on the same thread; anyone else's gets none. It answers only: its token cannot push ([`claude.yml`](../.github/workflows/claude.yml)).

`shell-tests` and `link-check` are the required checks on `main` ([*`main` is protected*](#main-is-protected)). Two things are set up by hand, once:

- The **`CLAUDE_CODE_OAUTH_TOKEN`** repository secret, which the review, follow-up and `@claude` workflows run Claude Code with. Create it with `claude setup-token`, then `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo FrankRay78/gaffer-claude`.
- The **`review-followup`** label, which has to exist before it can be added: `gh label create review-followup --repo FrankRay78/gaffer-claude --description "Triggers an automated review follow-up round; removed when the run ends"`.

## Layout

```
.claude-plugin/   plugin.json and marketplace.json
commands/         the slash commands, one markdown file each
skills/           tracker/SKILL.md, the one skill: how each tracker operation is carried out, and the matrix that keeps its calls there
hooks/            hooks.json, no-chmod.sh and its test matrix
chain/            chain.sh, chain-next.sh and their test matrices
init/             setup.sh and its test matrix
defaults/         the CONVENTIONS.md and REVIEW.md the commands run on when a repository says nothing
templates/        copyable starting points for a repository's own two files
docs/             the guides
.github/          workflows/, this repository's own CI (it ships to no consuming repository); scripts/, the scripts a workflow runs and their test matrices; ruleset-main.json
```

Commands are kept as `commands/*.md` rather than skills: each is a workflow a person invokes by name, with no supporting files, and the move from a repository's `.claude/commands/` was a move, not a rewrite. The tracker is the one skill, because commands load it; a person may also invoke it, as `/gaffer:tracker <operation>`.
