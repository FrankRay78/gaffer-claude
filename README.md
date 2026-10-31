# gaffer

A personal SDLC toolbox for Claude Code, packaged as a plugin so any repository can install it: the issue stage (`draftissue` → `reviewissue` → `confirmissue`), the build chain (`build` → `verify` → `raise-pr`, each ending on a machine-readable verdict a script can chain), a verified pull-request review with follow-up rounds, the periodic audits, a `diagnose` skill for hard bugs, and one hook that keeps an unattended run from stalling on `chmod`.

> **Personal toolbox — breaking changes at any time.** This plugin exists to serve its author's repositories. Any command, heading, default, verdict field or hook may change or disappear in any commit, with no deprecation period and no notice beyond the commit itself. Pin the commit you depend on; move the pin deliberately.

## What it ships

Commands are typed as `/gaffer:<name>`.

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

From a shell, add this repository as a marketplace and install the plugin from it:

```bash
claude plugin marketplace add <owner>/gaffer-claude      # or the repository's git URL
claude plugin install gaffer@gaffer-claude
```

To turn it on for everyone who opens a repository, commit this to the repository's `.claude/settings.json` (collaborators still run the install command once; a committed entry enables but does not download):

```json
{
  "extraKnownMarketplaces": {
    "gaffer-claude": { "source": { "source": "github", "repo": "<owner>/gaffer-claude" } }
  },
  "enabledPlugins": { "gaffer@gaffer-claude": true }
}
```

The repository is private, so the marketplace fetch uses your git credentials: `gh auth login` or a stored HTTPS credential, or an SSH key with no passphrase prompt.

**Pinning.** The plugin carries no `version` field, so an installed copy is identified by the commit it came from, and that commit is what `${CLAUDE_PLUGIN_ROOT}` points at. The marketplace entry is a relative path into this same repository, so pinning the marketplace pins the plugin: add it with a ref — `claude plugin marketplace add <owner>/gaffer-claude#<tag-or-commit>`, or a `ref` or `sha` on the `source` object in settings — and move the ref deliberately. A consuming repository's CI should install the pinned ref the same way, so a command change reaches it only by a reviewed pin bump. The first consumer to wire this into CI should confirm the ref form its installer honours; the plugin docs define `ref` as a branch or tag and `sha` as a full commit.

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
- **Reads outside the working directory allowed**, for an unattended run. The defaults the commands read live in the plugin's install directory, outside the repository, so a headless `claude -p` that is not run with permissions bypassed denies the read and the command stops with a failure verdict saying so. An interactive session prompts once instead.
- **`main` as the default branch**, and labels the issue stage uses: `needs answers` and `ready`. An unattended runner may also use `parked`.
- **`CLAUDE.md`** for project context, and **`.claude/memory/`** where `/gaffer:capture-learnings` writes durable learnings.

## Extending the defaults

The commands run on generic conventions and review criteria shipped in [`defaults/CONVENTIONS.md`](defaults/CONVENTIONS.md) and [`defaults/REVIEW.md`](defaults/REVIEW.md). A repository that has more to say puts a `CONVENTIONS.md` and a `REVIEW.md` at its root — copy [`templates/CONVENTIONS.md`](templates/CONVENTIONS.md) and [`templates/REVIEW.md`](templates/REVIEW.md) and delete what does not apply. Each section of the repository's file sits under a heading the defaults document and is read **together with** the default section of the same name: the repository's section is an addition, and wins where the two conflict. A repository section whose first line is exactly `Replaces the default.` is read **instead of** the default. A missing file or section means the default, never an error, and a section under a heading of the repository's own is read too. The one thing a repository must supply is its build-and-test command, under *Build, test and format*: `/gaffer:build` and `/gaffer:verify` stop rather than invent one.

Everything that crosses between the plugin and a repository goes through one of a small number of documented interfaces — the verdict schema, the two rules files and their headings, the hook, and the repository conventions the commands assume. [`docs/interfaces.md`](docs/interfaces.md) lists them. Anything a command needs that fits none of them is a sign the abstraction is wrong, not a reason for a special case.

**Learnings cross by issue, not by edit.** When work in a consuming repository shows a plugin command is wrong, the fix is an issue or pull request on this repository; nothing in a consuming repository edits a plugin checkout. Until the fix lands, a repository-side section under the matching heading is the workaround, since the repository's file wins.

## Developing the plugin

- `bash hooks/no-chmod.tests.sh` — the hook's test matrix; run it after any edit to the hook. CI runs every committed `*.tests.sh`.
- `claude plugin validate .` — checks the manifests and layout.
- Commands are kept as `commands/*.md` rather than skills: each is a workflow a person invokes by name, with no supporting files, and the move from a repository's `.claude/commands/` is then a move, not a rewrite. The one skill, `diagnose`, is model-invocable and stays a skill.

Layout:

```
.claude-plugin/   plugin.json and marketplace.json
commands/         the slash commands
skills/diagnose/  the diagnose skill
hooks/            hooks.json, no-chmod.sh and its test matrix
defaults/         the CONVENTIONS.md and REVIEW.md the commands run on when a repository says nothing
templates/        copyable starting points for a repository's own two files
docs/             the verdict schema and the interface list
```
