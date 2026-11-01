# gaffer

A personal SDLC toolbox for Claude Code, packaged as a plugin so any repository can install it: the issue stage (`draftissue` → `reviewissue` → `confirmissue`), the build chain (`build` → `verify` → `raise-pr`, each ending on a machine-readable verdict a script can chain), a verified pull-request review with follow-up rounds, the periodic audits, a `diagnose` skill for hard bugs, and one hook that keeps an unattended run from stalling on `chmod`.

> **Personal toolbox — breaking changes at any time.** This plugin exists to serve its author's repositories. Any command, heading, default, verdict field or hook may change or disappear in any commit, with no deprecation period and no notice beyond the pull request that makes the change, which says what breaks and for whom. A consumer that cannot absorb that pins a commit, as *Installing* describes.

## Why it is different

- **The confirmed issue is the specification.** There is no spec folder, plan file or task list: the issue stage settles outcome-level acceptance criteria on the issue itself, cross-checked against the codebase before a branch exists, and the build and verify stages implement and check exactly those.
- **Every unattended stage ends on a verdict a script can read.** `build`, `verify` and `raise-pr` close their report with one JSON object, read by position so nothing the report quotes can be mistaken for the stage's own decision. A chain that reads it starts the next stage only on success. The chain itself is not shipped: it belongs to the repository that runs it.
- **Repository specifics are data, not prompt text.** The commands are repository-agnostic and run on default conventions and review criteria shipped here; a repository extends them with a `CONVENTIONS.md` and a `REVIEW.md` of its own, section by section. Nothing a repository needs is written into a command, so a fix to a command is a change here and reaches every repository that tracks it.
- **It is built to run with nobody watching.** The build stages, the pull-request review and the issue gate all run headless, check their own post-conditions instead of trusting the model's report, and refuse rather than guess when a convention they need is missing.

## What it ships

Commands are typed as `/gaffer:<name>`. [`docs/commands.md`](docs/commands.md) is the per-command reference: what each needs, reads, changes or posts, and how it ends.

| Command | What it does |
|---|---|
| `/gaffer:draftissue` | Turns an idea, a document, a backlog item or an old issue into a needs-first GitHub issue and raises it. |
| `/gaffer:reviewissue` | Reviews an issue before building: posts the gaps and a recommendation for each as an inline-answerable comment. |
| `/gaffer:confirmissue` | Folds the answered review into a *Confirmed decisions* section on the issue, labels it `ready`, deletes the review comment. |
| `/gaffer:build` | Builds one issue to a green, committed feature branch — RED-GREEN-REFACTOR, docs, nothing pushed. Unattended. |
| `/gaffer:verify` | Formats, runs the whole suite as the gate, reviews the branch once in clean context, fixes and commits. Unattended. |
| `/gaffer:raise-pr` | Pushes the branch and opens the pull request with a body sized to the change and a verified `Closes #N`. |
| `/gaffer:review-pr` | Multi-pass verified review of an open PR: triage map, specialist passes, verification, inline comments, risk tier, no-human-merge verdict. |
| `/gaffer:review-followup` | A later round on a reviewed PR: evaluates replies, verifies fixes, re-reviews only the new diff. Caps at three rounds. |
| `/gaffer:review-slop` | Reviews a branch diff for AI-generated slop and emits a cleaned diff. |
| `/gaffer:audit-codebase` | Whole-tree audit across five lenses, every finding challenged before it is reported, raised as one issue. |
| `/gaffer:audit-deadcode` | Dead-code audit from the real entry points, producing `DEADCODE.md`. |
| `/gaffer:bugmagnet` | Systematic test-coverage and edge-case discovery for one module. |
| `/gaffer:capture-learnings` | Mines a session and a branch for durable learnings and applies the approved ones. |
| `/gaffer:context-gardening` | Prunes `CLAUDE.md`, its linked docs and `.claude/memory/`. |

Plus the **`diagnose` skill** (`/gaffer:diagnose`): a reproduce → minimise → hypothesise → instrument → fix → regression-test loop, and the **`no-chmod` hook**, which runs on every Bash call and refuses a `chmod` that would set the executable bit, naming `bash script.sh` as the alternative, so an unattended run is redirected rather than stalled on a permission prompt.

The build chain's three stages end their reports on one JSON verdict; the schema is [`docs/verdict-schema.md`](docs/verdict-schema.md). A chain script that reads those verdicts and drives the stages is not part of the plugin: it stays in the repository that runs it.

## Installing

From a shell, add this repository as a marketplace and install the plugin from it. The repository is public, so this needs no credentials:

```bash
claude plugin marketplace add FrankRay78/gaffer-claude
claude plugin install gaffer@gaffer-claude
```

To turn it on for everyone who opens a repository, commit this to the repository's `.claude/settings.json`. When the project is opened and trusted, Claude Code fetches the marketplace and loads the plugin from it, so a fresh clone offers the `/gaffer:` commands with no install step; the install commands above are for using the plugin outside such a repository:

```json
{
  "extraKnownMarketplaces": {
    "gaffer-claude": { "source": { "source": "github", "repo": "FrankRay78/gaffer-claude" } }
  },
  "enabledPlugins": { "gaffer@gaffer-claude": true }
}
```

**Which commit you run.** The plugin carries no `version` field: an installed copy is the commit of this repository's `main` at the moment the marketplace was added or last updated, and that commit is what `${CLAUDE_PLUGIN_ROOT}` points at. `claude plugin marketplace update gaffer-claude` moves it to the current `main`. Tracking `main` is the intended way to consume the plugin while it has one author: a change here reaches a consumer on its merge, with no version to bump. A consumer that wants a slower pace adds the marketplace with a ref — `claude plugin marketplace add FrankRay78/gaffer-claude#<tag-or-commit>`, or a `ref` or `sha` on the `source` object in settings — and moves the ref deliberately. `main` is protected: nothing lands on it except by a pull request whose checks have passed.

**In CI**, a job installs the plugin from `main` at its start, so what a workflow runs is always the current commit and never a copy cached on a runner. [`docs/ci.md`](docs/ci.md) has the pattern.

**Local development.** Run a checkout as an unpacked plugin for one session, without installing it:

```bash
claude --plugin-dir /path/to/gaffer-claude
```

The commands then appear as `/gaffer:<name>` exactly as they will when installed.

## What a repository needs

- **`git`, `gh` (authenticated) and `jq`** on the path. The hook also needs `awk`.
- **The `pr-review-toolkit` plugin** (from the official marketplace): `/gaffer:verify` spawns its reviewers by their `pr-review-toolkit:` names.
- **`Bash(chmod:*)` on `permissions.ask`** in the repository's `.claude/settings.json`. The `no-chmod` hook refuses the executable-bit forms; a plugin cannot set permission rules, so the ask rule is the repository's to keep as the backstop for the forms the hook declines to decide.
- **`.claude/scratch/` git-ignored.** Every command writes its working files there.
- **Reads outside the working directory allowed**, for an unattended run. The defaults the commands read live in the plugin's install directory, outside the repository, so a headless `claude -p` that is not run with permissions bypassed denies the read and the command stops with a failure verdict saying so. An interactive session prompts once instead; a CI job passes `--add-dir` for the plugin's directory.
- **`main` as the default branch**, and labels the issue stage uses: `needs answers` and `ready`. An unattended runner may also use `parked`.
- **`CLAUDE.md`** for project context, and **`.claude/memory/`** where `/gaffer:capture-learnings` writes durable learnings.
- **A build-and-test command**, under *Build, test and format* in the repository's `CONVENTIONS.md`, before the build stage is used: `/gaffer:build` and `/gaffer:verify` stop rather than invent one. Everything else has a default.

## Extending the defaults

The commands run on generic conventions and review criteria shipped in [`defaults/CONVENTIONS.md`](defaults/CONVENTIONS.md) and [`defaults/REVIEW.md`](defaults/REVIEW.md). A repository that has more to say puts a `CONVENTIONS.md` and a `REVIEW.md` at its root — copy [`templates/CONVENTIONS.md`](templates/CONVENTIONS.md) and [`templates/REVIEW.md`](templates/REVIEW.md) and delete what does not apply. Each section of the repository's file sits under a heading the defaults document and is read **together with** the default section of the same name: the repository's section is an addition, and wins where the two conflict. A repository section whose first line is exactly `Replaces the default.` is read **instead of** the default. A missing file or section means the default, never an error, and a section under a heading of the repository's own is read too.

Everything that crosses between the plugin and a repository goes through one of a small number of documented interfaces — the verdict schema, the two rules files and their headings, the hook, and the repository conventions the commands assume. [`docs/interfaces.md`](docs/interfaces.md) lists them. Anything a command needs that fits none of them is a sign the abstraction is wrong, not a reason for a special case.

**Learnings cross by issue, not by edit.** When work in a consuming repository shows a plugin command is wrong, the fix is an issue or pull request on this repository; nothing in a consuming repository edits a plugin checkout. Until the fix lands, a repository-side section under the matching heading is the workaround, since the repository's file wins.

## Documentation

- [`docs/getting-started.md`](docs/getting-started.md) — install, enable, a first run on the defaults, then adopting the two templates.
- [`docs/workflow.md`](docs/workflow.md) — the workflow the commands implement: the stages, where the human checkpoints are, when to use which command, and why it is built this way.
- [`docs/commands.md`](docs/commands.md) — the per-command reference.
- [`docs/interfaces.md`](docs/interfaces.md) — the interfaces between the plugin and a repository, including the heading set and which command reads which heading.
- [`docs/verdict-schema.md`](docs/verdict-schema.md) — the verdict the chain stages end on, and how a reader handles it.
- [`docs/ci.md`](docs/ci.md) — running the commands in CI: the pattern a caller's workflow follows.
- [`docs/unattended.md`](docs/unattended.md) — what runs unattended and what it is allowed to touch.
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — the common failures and what each one means.
- [`docs/contributing.md`](docs/contributing.md) — how the plugin itself is changed: the rules a command must keep to, the tests, the protected `main`.

## Layout

```
.claude-plugin/   plugin.json and marketplace.json
commands/         the slash commands
skills/diagnose/  the diagnose skill
hooks/            hooks.json, no-chmod.sh and its test matrix
defaults/         the CONVENTIONS.md and REVIEW.md the commands run on when a repository says nothing
templates/        copyable starting points for a repository's own two files
docs/             the guides above
```

## Licence

[MIT](LICENSE).
