# Getting started

From nothing to a first pull request raised by the commands, in a repository that has never seen them. Every step below works on the plugin's defaults; adopting the templates comes last, once you have seen what the defaults do.

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

## 2. Enable it for the repository

In the repository's `.claude/settings.json`, so the plugin is enabled for every clone and every collaborator. Committing it does not install the plugin: when the project is opened and trusted, Claude Code fetches the marketplace it names, but each collaborator still runs step 1 once on their machine, and a session before that offers no `/gaffer:` commands.

```json
{
  "extraKnownMarketplaces": {
    "gaffer-claude": { "source": { "source": "github", "repo": "FrankRay78/gaffer-claude" } }
  },
  "enabledPlugins": { "gaffer@gaffer-claude": true },
  "permissions": { "ask": ["Bash(chmod:*)"] }
}
```

The `ask` rule is the backstop behind the plugin's `no-chmod` hook: the hook refuses the executable-bit forms with a message naming `bash script.sh`, and the rule catches the forms the hook declines to decide. A plugin cannot set permission rules, so this one is yours to keep.

Three more things the commands assume, all cheap: `.claude/scratch/` is git-ignored (every command writes its working files there), `main` is the default branch, and `git`, `gh` (signed in) and `jq` are on the path. The full list is under *What a repository needs* in the [README](../README.md).

## 3. Create the labels

The issue stage moves an issue through two labels, and an unattended runner uses a third:

```bash
gh label create "needs answers" --description "A review is posted and awaiting the author's answers"
gh label create ready --description "The issue is confirmed and may be built"
gh label create parked --description "An unattended run stopped on this issue; remove to retry"
```

## 4. Run the issue stage on an idea

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

## 5. Tell the build stage how to build

This is the one convention with no default. Create `CONVENTIONS.md` at the repository root with a single section:

```markdown
# Conventions

## Build, test and format

- **Build-and-test command** — `<the one command that builds the repository and runs its whole test suite>`, run from the repository root.
- **Formatter** — `<the command CI checks formatting with>`, or delete this line if there is none.
```

Without it, `/gaffer:build` and `/gaffer:verify` stop with the reason `conventions missing: Build, test and format`, because inventing a build command unattended is how a run reports green over nothing.

## 6. Build, verify, raise

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

It pushes the branch and opens the pull request, with a body sized to the change and `Closes #<number>`. That is the one outward-facing act in the sequence, which is why it is a command of its own.

## 7. Review the pull request

```
/gaffer:review-pr <pr-number>
```

A triage map, specialist passes in parallel, every finding verified before it is posted, inline comments, a risk tier and a merge recommendation. Run it locally like this, or from CI when the pull request opens ([`unattended.md`](unattended.md), *In CI*). A later round, after the author has replied, is `/gaffer:review-followup <pr-number>`.

## 8. Adopt the templates

Once the defaults have run, copy [`templates/CONVENTIONS.md`](../templates/CONVENTIONS.md) over the one-section file from step 5 and [`templates/REVIEW.md`](../templates/REVIEW.md) beside it, and delete every section the repository has nothing to add under. Each section you keep is read together with the plugin's default section of the same heading and wins where they conflict; a section whose first line is `Replaces the default.` is read instead of it. [`interfaces.md`](interfaces.md) lists the headings and which command reads each.

Two sections pay for themselves first: *Testing* (your test projects, naming scheme and what not to test) and *Documentation* (what a kind of change owes — a user guide for a changed option, API docs for a public member — so `/gaffer:build` discharges it without being asked).

## Where next

- [`workflow.md`](workflow.md) — how the stages fit together, and what a chain that runs them must do; [`chain.md`](chain.md) — the chain itself, and the runner that fires it from a timer.
- The prompts under [`commands/`](../commands/) — everything each command needs, reads, changes and ends with.
- [`unattended.md`](unattended.md) — before you let any of this run with nobody watching, and the CI pattern.
