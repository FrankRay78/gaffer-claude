# The interfaces between the plugin and a repository

Everything that crosses between gaffer and a repository that installs it goes through one of the interfaces below. Each is documented here and nowhere else restated; the commands point at these. A command that needs something that fits none of them is a sign the abstraction is wrong, not a reason for a special case — raise it as an issue on this repository.

## 1. The verdict schema

`/gaffer:build`, `/gaffer:verify` and `/gaffer:raise-pr` each end their report on one JSON object: `{"schema": 1, "outcome": "<ready|verified|raised|failed>", ...payload}`. [`verdict-schema.md`](verdict-schema.md) is the one statement of the fields, what each outcome carries, how a reader finds the verdict (by position: the last non-blank line, or the code fence that closes the report) and how it handles a version or field it does not know. The writers are the three commands; the readers are the chain scripts of consuming repositories, which are not part of the plugin. A reader is strict about the version and lenient about the fields, so a command may add a field without a version bump, and a version bump reaches readers before the writers change.

## 2. `CONVENTIONS.md` and `REVIEW.md`, with their heading sets

The commands run on conventions and review criteria, read section by section from two files each:

| File | Plugin default | Repository addition | Read by |
|---|---|---|---|
| Conventions | `${CLAUDE_PLUGIN_ROOT}/defaults/CONVENTIONS.md` | `CONVENTIONS.md` at the repository root | `build`, `verify`, `raise-pr`, `draftissue`, `reviewissue`, `audit-codebase` |
| Review criteria | `${CLAUDE_PLUGIN_ROOT}/defaults/REVIEW.md` | `REVIEW.md` at the repository root | `review-pr`, `review-followup`, and `verify` for *Where it runs* |

**How the two combine.** For each heading a command reads, the default section is read first, then the repository's section under the same heading, and the two are applied together: the repository's is an addition and wins where they conflict. A repository section whose first line is exactly `Replaces the default.` is read instead of the default section. A repository with no file, or no section under a heading, runs on the default alone. Where the default also has nothing (*No default*), the step runs on the command's generic rule alone and the report names the heading; where the convention is the thing itself and there is no generic rule — the build-and-test command — the command stops with the reason `conventions missing: <heading>`. A section under a heading neither file documents is read too, and applied where its text says.

**The heading set.** The headings are recommended, not mandatory: a repository adopts them one section at a time. The defaults files document each, and each command's *Repository conventions* or *Repository criteria* table names the ones it reads.

`CONVENTIONS.md`: *Build, test and format* · *Test-driven development* · *Testing* · *Acceptance criteria* · *Code quality* · *Dependencies* · *Public API and breaking changes* · *Commit messages* · *Documentation* · *Change-intent records* · *Scratch files* · *Pull requests* · *Issue sources* · *Issue concerns* · *Issue review checks* · *Audit* · *Hooks, scripts and plugins*.

`REVIEW.md`: *Where it runs* · *Severity* · *What not to flag* · *Risk tier* · *Always a person* · *Contracts* · *Context to load* · *Change map* · *Tests*.

**Which command reads which heading.** The command's own table is authoritative; this is the index across them, so a repository writing a section knows which commands it reaches.

| Heading | Read by |
|---|---|
| *Build, test and format* | `build`, `verify` |
| *Test-driven development* | `build` |
| *Testing* | `build`, `audit-codebase`, `capture-learnings` |
| *Acceptance criteria* | `draftissue`, `build`, `audit-codebase` |
| *Code quality* | `build` |
| *Dependencies* | `build`, `audit-codebase` |
| *Public API and breaking changes* | `build`, `audit-codebase` |
| *Commit messages* | `build`, `verify` |
| *Documentation* | `build` |
| *Change-intent records* | `build`, `raise-pr` |
| *Scratch files* | `draftissue`, `reviewissue`, `confirmissue`, `raise-pr` |
| *Pull requests* | `raise-pr` |
| *Issue sources*, *Issue concerns* | `draftissue` |
| *Issue review checks* | `reviewissue` |
| *Audit* | `audit-codebase` |
| *Hooks, scripts and plugins* | `verify` |
| `REVIEW.md` → *Where it runs* | `review-pr`, `review-followup`, `verify` |
| `REVIEW.md` → every other heading | `review-pr`, and `review-followup` through the `review-pr` steps it invokes |

**Trust.** The repository's files are read from the root of the repository the command runs in, and trusted as the command files are: never from a worktree made for a review, and in CI from the default branch's copy, which the workflow puts in place before the agent starts. A change to either file always needs a person at review. The defaults are read from the plugin, so a repository changes a default only by extending or replacing a section in its own file.

## 3. The hook the plugin ships

`hooks/hooks.json` registers `no-chmod.sh` on `PreToolUse` for every Bash call, invoked via `bash "${CLAUDE_PLUGIN_ROOT}/hooks/no-chmod.sh"` so it needs no executable bit and no `if` clause. It refuses a `chmod` that would set the executable bit, with a message naming `bash script.sh` as the alternative, and waves everything else through. It fails open on a missing tool or unparseable input, announcing the degraded state on stderr; `GAFFER_ALLOW_CHMOD=1` bypasses hook mode, announced, and `--check '<command>'` classifies one command string for CI or manual use and ignores the override. Its test matrix, `hooks/no-chmod.tests.sh`, is the specification: every refused and allowed form, the known limits (a `chmod` reached through `find -exec`, `xargs` or `bash -c` is not seen), and the wiring.

What the repository keeps: `Bash(chmod:*)` on `permissions.ask` in its `.claude/settings.json`. A plugin cannot set permission rules, and that rule is the fail-open backstop for the forms the hook declines to decide.

The plugin ships no other hook and no script. A repository's own gates — a stale-build guard, a skipped-test ban, a traceability check, a suite re-run on pull-request creation — stay in the repository, named under `CONVENTIONS.md` → *Hooks, scripts and plugins* and *Acceptance criteria* so the commands weigh them.

## 4. Repository conventions the commands assume

Not configurable; a repository that differs changes the command, by an issue here.

- **`CLAUDE.md`** at the repository root is the project context every command reads first.
- **`.claude/memory/`** holds durable learnings as one file per fact with an index in `MEMORY.md`; `/gaffer:capture-learnings` writes there and `/gaffer:context-gardening` prunes it.
- **`.claude/scratch/`**, git-ignored, holds every working file a command writes; the file names are under `CONVENTIONS.md` → *Scratch files*.
- **`main`** is the default branch: `/gaffer:build` branches from `origin/main` and refuses to run anywhere else, `/gaffer:verify` and `/gaffer:raise-pr` refuse to run on it, and the review workflows read `main`'s copy of the rules files.
- **Branches** are named `feature/<N>-<slug>` by `/gaffer:build`, and `/gaffer:raise-pr` reads the issue number off that shape.
- **Issue labels**: `needs answers` (set by `/gaffer:reviewissue`, removed by `/gaffer:confirmissue`) and `ready` (set by `/gaffer:confirmissue`; the done-marker of the issue stage, and what an unattended runner selects on). `/gaffer:audit-codebase` applies only the label the repository names and never `ready`, `review`, `confirm` or `parked`, because automation may react to those.
- **Comment markers**: `<!-- speckit:review -->` on the review comment `/gaffer:reviewissue` posts and `/gaffer:confirmissue` consumes; `<!-- confirmed-decisions -->` in the issue body; `<!-- review-pr -->` on the summary of every `/gaffer:review-pr` round, which `/gaffer:review-followup` finds prior rounds by.
- **Tools**: `git`, `gh` authenticated against the repository's remote, `jq`; the `pr-review-toolkit` plugin for `/gaffer:verify`'s reviewers; the `update-config` skill where `/gaffer:capture-learnings` wires a hook.

## What does not cross

A chain script, a scheduled runner, CI workflows and a repository's own hooks are the repository's: anything run by CI, a timer or a human stays where it runs, and loads the plugin from a checkout of this repository's `main` — a fresh clone in CI, a clone the runner brings up to date before each firing — never from whatever copy happens to be installed on the machine. [`ci.md`](ci.md) has the CI pattern. Learnings cross by issue, never by an edit to a plugin checkout from a consuming repository.
