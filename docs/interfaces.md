# The interfaces between the plugin and a repository

Everything that crosses between gaffer and a repository goes through one of these. A command that needs something fitting none of them is a sign the abstraction is wrong, not a reason for a special case — raise it as an issue here.

## 1. The verdict schema

`/gaffer:build`, `/gaffer:verify`, `/gaffer:raise-pr` and `/gaffer:pre-review` end their report on one JSON object, read by the chain under [`chain/`](../chain/). [`verdict-schema.md`](verdict-schema.md) is its one statement.

## 2. `CONVENTIONS.md` and `REVIEW.md`

The commands read conventions and review criteria section by section, from the plugin's [`defaults/`](../defaults/) and from the repository root. `REVIEW.md` is read by `review-pr` and `review-followup` (and `verify`, for *Where it runs*); `CONVENTIONS.md` by the rest, and by `review-pr` and `review-followup` for the comment rule under *Code quality*, which `build` writes to and `verify`, `review-slop` and the pull request review hold a branch to.

- **They combine.** For each heading, the default section is read, then the repository's section of the same name; the repository's is an addition and wins where they conflict.
- **A repository can replace a default.** A section whose first line is exactly `Replaces the default.` is read instead of the default.
- **Nothing is mandatory.** A missing file or section means the default; a heading of the repository's own is read too. Where neither has anything, the command runs on its generic rule — except the build-and-test command, where it stops with `conventions missing: <heading>`.
- **The headings** are the ones the defaults files use. Each command's *Repository conventions* or *Repository criteria* table names those it reads, and is authoritative.
- **They are trusted like the commands**: read from the root of the repository the command runs in, never from a review worktree, and in CI from the default branch's copy. A change to either needs a person at review.

## 3. The hook

`hooks/hooks.json` runs `no-chmod.sh` on every Bash call. It refuses a `chmod` that sets the executable bit, naming `bash script.sh`, and fails open on a missing tool or bad input. Its test matrix, `hooks/no-chmod.tests.sh`, is the specification, including its known limits. The repository keeps `Bash(chmod:*)` on `permissions.ask` as the backstop. The plugin ships no other hook. Its one other script run inside a session, `init/setup.sh`, is called only by `/gaffer:init` and writes only the setup the README's *What a repository needs* lists — the `.claude/settings.json` entries, the git-ignore line, the memory index and `CLAUDE.md` imports. The marketplace, repository and plugin id in those entries are read from `.claude-plugin/marketplace.json` of the plugin it runs from — its `name`, and the first plugin entry's `name` and `repository` — so a copy of the plugin published under another marketplace proposes itself. A repository's own gates stay in the repository, named under `CONVENTIONS.md` → *Hooks, scripts and plugins* so the commands weigh them.

## 4. The chain settings file

`.gaffer/chain.json` in the repository, read by the chain scripts and by nothing inside a session: the runner's clone and the accounts whose issues it may build, with defaults for the runner's labels, the pre-review opt-in, each stage's model and effort, the permissions opt-in and where state is kept. It names no tracker. [`chain.md`](chain.md) → *The settings file* is its one statement; a key the runner does not know is refused.

## 5. Conventions the commands assume

Not configurable; a repository that differs changes the command, by an issue here.

- `CLAUDE.md` at the root is the project context every command reads first.
- `.claude/memory/` holds durable learnings, one file per fact, indexed in `MEMORY.md`, which `CLAUDE.md` loads into every session with the line `@.claude/memory/MEMORY.md`. Claude Code does not read the folder on its own.
- `.claude/scratch/`, git-ignored, holds every working file.
- `main` is the default branch; `build` branches from `origin/main` and names branches `feature/<N>-<slug>`, where `<N>` is the issue reference in the tracker's branch form, which `raise-pr` reads back.
- The commands speak of three tracker states (§6): `needs-answers` and `ready` carry the issue stage's state, and `parked` the runner's. On GitHub they are the labels `needs answers`, `ready` and `parked`, which the tracker skill names. No command creates one: `/gaffer:init` lists them and says which are missing. `audit-codebase` puts its issue in no state, never `ready` or `parked`, because automation reacts to them.
- Markers let the commands find each other's output: the tracker's `review` and `confirmed-decisions` markers on issues (on GitHub `<!-- speckit:review -->` and `<!-- confirmed-decisions -->`), and `<!-- review-pr -->` on pull request reviews.

## 6. The tracker skill

[`skills/tracker/SKILL.md`](../skills/tracker/SKILL.md), loaded as `gaffer:tracker`, is the one way a command reaches the issue tracker. A command names an operation — `tracker: view <ref>` — with states and markers by name, never a label, a `gh` issue call or a closing keyword, and loads the skill before its first one; the skill says how to carry each out, on GitHub with `gh`. A repository whose issues live elsewhere runs a clone of the plugin with that one file replaced, and nothing else changed. [`tracker.md`](tracker.md) is its one statement — every operation and what it must yield, the states and markers, and what a headless stage needs allowed. Pull requests and reviews are outside it and stay on GitHub, as does the runner, `chain/chain-next.sh`. `chain.sh` reads no issue reference and reaches no tracker: it hands its argument to the first stage as typed.

## What does not cross

How the chain is scheduled, CI workflows and a repository's own hooks are the repository's. Each loads the plugin from a checkout of `main` it controls, never from whatever copy is installed on the machine — the chain scripts from the checkout they sit in, a CI job from a clone it makes. **Learnings cross by issue**: when a command is wrong, the fix is an issue or PR here, never an edit to a plugin checkout from a consuming repository.
