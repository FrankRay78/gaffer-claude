# gaffer

A personal SDLC toolbox for Claude Code, packaged as a plugin so any repository can install it: the issue stage (`draftissue` → `reviewissue` → `confirmissue`), the build chain (`build` → `verify` → `raise-pr`, each ending on a machine-readable verdict a script can chain), a verified pull-request review with follow-up rounds, the periodic audits, and one hook that keeps an unattended run from stalling on `chmod`.

> **Personal toolbox — breaking changes at any time.** Any command, heading, default, verdict field or hook may change or disappear in any commit, with no notice beyond the pull request that makes the change, which says what breaks and for whom. A consumer that cannot absorb that pins a commit, as *Installing* describes.

## Why it is different

- **The confirmed issue is the specification.** No spec folder, plan file or task list: the issue stage settles outcome-level acceptance criteria on the issue itself, checked against the codebase before a branch exists, and the build and verify stages implement and check exactly those.
- **Every unattended stage ends on a verdict a script can read.** `build`, `verify` and `raise-pr` close their report with one JSON object, read by position so nothing the report quotes can be mistaken for the stage's decision. The chain that reads it belongs to the repository that runs it, not the plugin.
- **Repository specifics are data, not prompt text.** The commands run on defaults shipped here; a repository extends them with a `CONVENTIONS.md` and a `REVIEW.md` of its own, section by section. A fix to a command is a change here and reaches every repository that tracks it.
- **It is built to run with nobody watching.** The build stages, the pull-request review and the issue gate run headless, check their own post-conditions rather than trusting the model's report, and stop rather than guess when a convention they need is missing.

## What it ships

Commands are typed as `/gaffer:<name>`. Each command's prompt under [`commands/`](commands/) is its full reference.

| Command | What it does | Unattended? |
|---|---|---|
| `draftissue` | Turns an idea, a document, a backlog item or an old issue into a needs-first GitHub issue and raises it. | No — discusses open decisions |
| `reviewissue` | Reviews an issue before building: posts the gaps and a recommendation for each as an inline-answerable comment, labels it `needs answers`. | Yes, given an issue number |
| `confirmissue` | Folds the answered review into *Confirmed decisions* on the issue, labels it `ready`, deletes the review comment. | Yes, given an issue number |
| `build` | Builds one issue to a green, committed `feature/<N>-<slug>` branch — RED-GREEN-REFACTOR, docs, nothing pushed. | Yes |
| `verify` | Formats, runs the whole suite as the gate, reviews the branch once in clean context, fixes and commits. | Yes |
| `raise-pr` | Pushes the branch and opens the pull request with a verified `Closes #N`. | Yes |
| `review-pr` | Multi-pass verified review of an open PR: triage map, specialist passes, inline comments, risk tier, no-human-merge verdict. | Yes |
| `review-followup` | A later round on a reviewed PR: evaluates replies, verifies fixes, re-reviews only the new diff. Caps at three rounds. | Yes |
| `review-slop` | Reviews a branch diff for AI-generated slop and emits a cleaned diff. | No prompts, no side effects |
| `audit-codebase` | Whole-tree audit across five lenses, every finding challenged before it is reported, raised as one issue. | Once given a `<since-ref>` |
| `audit-deadcode` | Dead-code audit from the real entry points, producing `DEADCODE.md`. | No prompts, no side effects |
| `capture-learnings` | Mines a session and a branch for durable learnings and applies the approved ones. | No — you pick candidates |
| `context-gardening` | Prunes `CLAUDE.md`, its linked docs and `.claude/memory/`. | No — you pick candidates |

Plus the **`no-chmod` hook**, which refuses a `chmod` that would set the executable bit and names `bash script.sh` instead, so an unattended run is redirected rather than stalled on a permission prompt.

## Installing

The repository is public, so this needs no credentials:

```bash
claude plugin marketplace add FrankRay78/gaffer-claude
claude plugin install gaffer@gaffer-claude
```

To enable it for every clone of a repository, commit this to its `.claude/settings.json`. It enables the plugin and fetches the marketplace once the project is trusted; it does not install it, so each machine still runs the `install` above once:

```json
{
  "extraKnownMarketplaces": {
    "gaffer-claude": { "source": { "source": "github", "repo": "FrankRay78/gaffer-claude" } }
  },
  "enabledPlugins": { "gaffer@gaffer-claude": true }
}
```

**Which commit you run.** The plugin has no `version` field: an installed copy is `main` as of the last `claude plugin marketplace update gaffer-claude`. Tracking `main` is the intended way to consume it; a consumer that wants a slower pace adds the marketplace with a ref (`FrankRay78/gaffer-claude#<tag-or-commit>`) and moves it deliberately. `main` is protected: nothing lands on it except by a pull request whose checks have passed.

**Local development.** `claude --plugin-dir /path/to/gaffer-claude` runs a checkout for one session, with the commands under the same `/gaffer:` names.

## What a repository needs

- **`git`, `gh` (authenticated) and `jq`** on the path. The hook also needs `awk`.
- **The `pr-review-toolkit` plugin**: `/gaffer:verify` spawns its reviewers by their `pr-review-toolkit:` names.
- **`Bash(chmod:*)` on `permissions.ask`** in `.claude/settings.json`, as the backstop for the forms the hook declines to decide; a plugin cannot set permission rules.
- **`.claude/scratch/` git-ignored**, for every command's working files.
- **`main` as the default branch**, `CLAUDE.md` for project context, and `.claude/memory/` for durable learnings.
- **A build-and-test command** under *Build, test and format* in the repository's `CONVENTIONS.md` before the build stage is used. It is the one convention with no default: `build` and `verify` stop rather than invent one.

How the repository's `CONVENTIONS.md` and `REVIEW.md` combine with the defaults is in [`docs/interfaces.md`](docs/interfaces.md); copy [`templates/`](templates/) to start them.

## Documentation

- [`docs/getting-started.md`](docs/getting-started.md) — install, a first run on the defaults, then adopting the templates.
- [`docs/workflow.md`](docs/workflow.md) — how the stages fit together, and why they are shaped this way.
- [`docs/interfaces.md`](docs/interfaces.md) — everything that crosses between the plugin and a repository.
- [`docs/verdict-schema.md`](docs/verdict-schema.md) — the verdict the build chain ends on, and how to read it.
- [`docs/unattended.md`](docs/unattended.md) — running commands with nobody watching: what each touches, permissions, and the CI pattern.
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — the common failures.
- [`docs/contributing.md`](docs/contributing.md) — how the plugin itself is changed.

## Layout

```
.claude-plugin/   plugin.json and marketplace.json
commands/         the slash commands
hooks/            hooks.json, no-chmod.sh and its test matrix
defaults/         the CONVENTIONS.md and REVIEW.md the commands run on when a repository says nothing
templates/        copyable starting points for a repository's own two files
docs/             the guides above
```

## Licence

[MIT](LICENSE).
