# Getting started

From nothing to a first pull request raised by the commands, in a repository that has never seen them. `/gaffer:init` does the setup and starts the repository's conventions from what it already contains; everything after that runs on what it wrote and on the plugin's defaults.

## 1. Install the plugin

```bash
claude plugin marketplace add FrankRay78/gaffer-claude
claude plugin install gaffer@gaffer-claude
```

The repository is public, so this needs no credentials. Check it took: `claude plugin list` names `gaffer@gaffer-claude`, and a new session in any repository offers `/gaffer:build` and its siblings in the slash-command list.

`/gaffer:verify` spawns reviewers from the `pr-review-toolkit` plugin, so install that too if you have not:

```bash
claude plugin install pr-review-toolkit@claude-plugins-official
```

## 2. Set up the repository

In a session at the repository root, on whatever branch you like:

```
/gaffer:init
```

It asks nothing, and needs only `jq` on the path. It writes into the checkout as it stands and commits nothing, so it does not matter which branch is checked out or what else is uncommitted there. What it writes:

- **`.claude/settings.json` entries** that enable gaffer and `pr-review-toolkit` for every clone, and put `Bash(chmod:*)` on `permissions.ask`. The `ask` rule is the backstop behind the plugin's `no-chmod` hook: the hook refuses the executable-bit forms with a message naming `bash script.sh`, and the rule catches the forms the hook declines to decide. When gaffer runs from a local checkout (`claude --plugin-dir <checkout>`) rather than a marketplace install, init leaves out the gaffer marketplace and plugin entries and reports them as `skipped:`: a session opened without that `--plugin-dir` would otherwise load the marketplace's gaffer, which may not be the checkout's, as with a clone carrying its own tracker skill ([`tracker.md`](tracker.md)).
- **`.claude/scratch/` git-ignored**, since every command writes its working files there.
- **`.claude/memory/MEMORY.md`**, and **`CLAUDE.md` importing it** and `CONVENTIONS.md` (once there is one), so the memory entries `/gaffer:capture-learnings` writes and the conventions are in every session's context.
- **A `CONVENTIONS.md` and a `REVIEW.md`** with a section for each template heading the repository already answers: pointers to its CI workflows, scripts and guides, and the build, test and format commands copied word for word from the file that runs them. It writes no principle or decision; a heading with nothing to point at is left out, so the plugin's default applies.

Its report names each file it wrote and the headings it filled, with the files each was filled from. It also lists the states the issue stage and the chain need the tracker to have, as the tracker skill gives them, and says which are missing. It creates none: make the missing ones yourself before the first `/gaffer:reviewissue`, which fails at its last step without them. Read what it wrote with `git status` and `git diff`, check the copied build-and-test command above all, edit anything, and commit it by whatever route the repository takes changes — or discard it.

**To keep it out of git**, run `/gaffer:init --git-ignore`. It writes the same files, and adds each to `.git/info/exclude`, the ignore file that belongs to your clone and is never committed, leaving `.gitignore` alone. `git status` then shows nothing, and nobody else's clone is touched: this is the way to use gaffer in a repository whose owners have not agreed to carry its files. A file git already tracks cannot be hidden that way, so it changes none: where `CLAUDE.md` is tracked the imports go in `CLAUDE.local.md`, and where `.claude/settings.json` is tracked the entries go in `.claude/settings.local.json`, the files Claude Code reads beside them for one clone. A tracked `CONVENTIONS.md` or `REVIEW.md` is not changed either; the report gives the headings it would have gained. Your working tree stays as clean as it was, which matters because `/gaffer:build`, `/gaffer:verify` and the chain refuse a dirty one.

Committing the settings does not install the plugin for anyone: when the project is opened and trusted, Claude Code fetches the marketplace it names, but each collaborator still runs step 1 once on their machine, and a session before that offers no `/gaffer:` commands.

Run `/gaffer:init` again whenever you like. On a repository already set up it touches nothing that is there, adds what is missing, and says so when nothing is.

### By hand

What `/gaffer:init` adds to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "gaffer-claude": { "source": { "source": "github", "repo": "FrankRay78/gaffer-claude" } }
  },
  "enabledPlugins": { "gaffer@gaffer-claude": true, "pr-review-toolkit@claude-plugins-official": true },
  "permissions": { "ask": ["Bash(chmod:*)"] }
}
```

Then git-ignore `.claude/scratch/`, and add `@CONVENTIONS.md` and `@.claude/memory/MEMORY.md` lines to `CLAUDE.md`, creating it if there is none. Claude Code does not read `.claude/memory/` on its own, so without the second line no session sees a memory entry; the import is harmless before the first entry exists. Then make sure the tracker has the states the commands use. In a session, this lists them, what shows each in the tracker, which are missing, and how to create those:

```
/gaffer:tracker states
```

The commands also assume `main` is the default branch and that `git`, `gh` 2.73.0 or later (signed in) and `jq` are on the path. The full list is under *What a repository needs* in the [README](../README.md).

## 3. Run the issue stage on an idea

In a session in the repository, on `main`:

```
/gaffer:draftissue A short description of something the repository should do
```

It writes a needs-first issue — users and jobs, capability, out of scope, acceptance criteria as outcomes an outside observer can check — and raises it. Then review it:

```
/gaffer:reviewissue <number>
```

The review posts one comment: the gaps the issue leaves open, each with a recommendation and a line to answer on. Answer them on the issue itself, in the GitHub UI, then fold the answers in:

```
/gaffer:confirmissue <number>
```

The issue now carries a *Confirmed decisions* section and the `ready` label, and the review comment is gone. The confirmed issue is the specification: there is no separate spec, plan or task list.

## 4. Check the build stage knows how to build

This is the one convention with no default. If init's report does not list *Build, test and format* as filled, add the section to `CONVENTIONS.md` at the repository root yourself:

```markdown
# Conventions

## Build, test and format

- **Build-and-test command** — `<the one command that builds the repository and runs its whole test suite>`, run from the repository root.
- **Single-test command** — `<the command that runs only the named tests>`, or delete this line; without it `/gaffer:verify` re-runs the whole suite to check a failing test.
- **Formatter** — `<the command CI checks formatting with>`, or delete this line if there is none.
```

Without it, `/gaffer:build` and `/gaffer:verify` stop with the reason `conventions missing: Build, test and format`, because inventing a build command unattended is how a run reports green over nothing.

## 5. Build, verify, raise

Still on a clean `main`:

```
/gaffer:build <number>
```

It branches as `feature/<number>-<slug>`, writes the failing tests for each acceptance criterion and watches them fail, makes them pass, updates the documents the change affects, and ends on a `ready` verdict naming the branch — or a `failed` verdict with a reason, having stopped at the first thing it could not do. It pushes nothing. Then:

```
/gaffer:verify
```

It formats with the command you named, runs the whole suite as the gate, reviews the branch once in clean context, fixes what the review confirmed, re-runs the suite and commits, ending on a `verified` verdict. Finally:

```
/gaffer:raise-pr <number>
```

It pushes the branch and opens the pull request, with a body sized to the change and `Closes #<number>`. Opening the pull request is the first outward-facing act in the sequence, which is why it is a command of its own; only the pre-review also acts on GitHub.

To have the repository's own review run once, and its findings fixed, before anyone reads the pull request, raise it with `/gaffer:raise-pr --draft <number>` and then run `/gaffer:pre-review`, which marks it ready. The chain does this on every run ([`chain.md`](chain.md), *The pre-review*).

## 6. Review the pull request

```
/gaffer:review-pr <pr-number>
```

A triage map, specialist passes in parallel, every candidate verified before it is listed, Critical and Major findings posted inline, Minor observations listed in the summary as notes, split into those needing a judgement call and mechanical ones, a risk tier, how much human review the pull request needs, and a merge recommendation. Run it locally like this, or from CI when the pull request is opened ready or marked ready ([`unattended.md`](unattended.md), *In CI*). A later round, after the author has replied, is `/gaffer:review-followup <pr-number>`.

## 7. Fill in what init could not

The headings init's report left to the plugin's default run on it. Once the defaults have run and you know what you want to add, copy a heading's section from [`templates/CONVENTIONS.md`](../templates/CONVENTIONS.md) or [`templates/REVIEW.md`](../templates/REVIEW.md) into your file and fill it in. Each section is read together with the plugin's default section of the same heading and wins where they conflict; a section whose first line is `Replaces the default.` is read instead of it. [`interfaces.md`](interfaces.md) lists the headings and which command reads each.

Two sections pay for themselves first: *Testing* (your test projects, naming scheme and what not to test) and *Documentation* (what a kind of change owes — a user guide for a changed option, API docs for a public member — so `/gaffer:build` discharges it without being asked).

## Where next

- [`workflow.md`](workflow.md) — how the stages fit together, and what a chain that runs them must do; [`chain.md`](chain.md) — the chain itself, and the runner that fires it from a timer.
- The prompts under [`commands/`](../commands/) — everything each command needs, reads, changes and ends with.
- [`unattended.md`](unattended.md) — before you let any of this run with nobody watching, and the CI pattern.
