# The interfaces between the plugin and a repository

Everything that crosses between gaffer and a repository goes through one of these. A command that needs something fitting none of them is a sign the abstraction is wrong, not a reason for a special case — raise it as an issue here.

## 1. The verdict schema

`/gaffer:build`, `/gaffer:verify` and `/gaffer:raise-pr` end their report on one JSON object, read by a caller's chain script. [`verdict-schema.md`](verdict-schema.md) is its one statement.

## 2. `CONVENTIONS.md` and `REVIEW.md`

The commands read conventions and review criteria section by section, from the plugin's [`defaults/`](../defaults/) and from the repository root. `REVIEW.md` is read by `review-pr` and `review-followup` (and `verify`, for *Where it runs*); `CONVENTIONS.md` by the rest.

- **They combine.** For each heading, the default section is read, then the repository's section of the same name; the repository's is an addition and wins where they conflict.
- **A repository can replace a default.** A section whose first line is exactly `Replaces the default.` is read instead of the default.
- **Nothing is mandatory.** A missing file or section means the default; a heading of the repository's own is read too. Where neither has anything, the command runs on its generic rule — except the build-and-test command, where it stops with `conventions missing: <heading>`.
- **The headings** are the ones the defaults files use. Each command's *Repository conventions* or *Repository criteria* table names those it reads, and is authoritative.
- **They are trusted like the commands**: read from the root of the repository the command runs in, never from a review worktree, and in CI from the default branch's copy. A change to either needs a person at review.

## 3. The hook

`hooks/hooks.json` runs `no-chmod.sh` on every Bash call. It refuses a `chmod` that sets the executable bit, naming `bash script.sh`, and fails open on a missing tool or bad input. Its test matrix, `hooks/no-chmod.tests.sh`, is the specification, including its known limits. The repository keeps `Bash(chmod:*)` on `permissions.ask` as the backstop. The plugin ships no other hook and no script; a repository's own gates stay in the repository, named under `CONVENTIONS.md` → *Hooks, scripts and plugins* so the commands weigh them.

## 4. Conventions the commands assume

Not configurable; a repository that differs changes the command, by an issue here.

- `CLAUDE.md` at the root is the project context every command reads first.
- `.claude/memory/` holds durable learnings, one file per fact, indexed in `MEMORY.md`.
- `.claude/scratch/`, git-ignored, holds every working file.
- `main` is the default branch; `build` branches from `origin/main` and names branches `feature/<N>-<slug>`, which `raise-pr` reads the issue number from.
- Labels `needs answers` and `ready` carry the issue stage's state. `audit-codebase` never applies `ready`, `review`, `confirm` or `parked`, because automation may react to them.
- Comment markers `<!-- speckit:review -->`, `<!-- confirmed-decisions -->` and `<!-- review-pr -->` let the commands find each other's output.

## What does not cross

A chain script, a scheduled runner, CI workflows and a repository's own hooks are the repository's. Each loads the plugin from a checkout of `main` it controls, never from whatever copy is installed on the machine. **Learnings cross by issue**: when a command is wrong, the fix is an issue or PR here, never an edit to a plugin checkout from a consuming repository.
