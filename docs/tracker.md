# The tracker interface

Every command and the chain reach the issue tracker through one script, [`tracker/tracker.sh`](../tracker/tracker.sh), never through a tracker's own CLI or API. The script reads which tracker the repository uses and hands each call to that tracker's adapter, under [`tracker/adapters/`](../tracker/adapters/). The plugin ships one adapter, `github`, which makes the calls the commands made before the interface existed. Pull requests and their reviews are not tracker business: they stay on GitHub whatever the tracker.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh <operation> [arguments…]
```

A command describes what it means — "put this issue in the `ready` state" — and the adapter decides how the tracker shows it: on GitHub, a label.

## The setting

The `tracker` key of the repository's settings file names the adapter: `"tracker": "github"` selects `tracker/adapters/github.sh`. A missing file or a missing key means `github`, so a repository that has never set it behaves as it always has.

The settings file is `.gaffer/chain.json` at the root of the repository — the chain's settings file, which [`chain.md`](chain.md) → *The settings file* describes — or the file the `GAFFER_SETTINGS` environment variable names. The chain sets `GAFFER_SETTINGS` for every stage to the file it read itself, so a stage started with `chain.sh --settings <file>` reads the same tracker as the chain.

An adapter may read its own key from the same file. The `github` adapter reads `github.labels`, which names the label each state maps to:

```json
{
  "tracker": "github",
  "github": { "labels": { "needs-answers": "needs answers", "ready": "ready", "parked": "parked", "audit": "audit" } }
}
```

Each state defaults to the label shown. `github.labels.ready` is the label `/gaffer:confirmissue` applies; the runner's own `labels.ready` is the label it selects on, and the two are kept apart so a repository can confirm and queue separately, as before.

A setting that names no adapter, a tracker name that is not a plain lower-case name, or an adapter that does not implement an operation stops the call before the tracker is reached, with a message naming the setting, the file and the operation. Each command first runs `require` for every operation it needs, so a broken setting stops it before it changes anything.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success. |
| 1 | The operation failed, or a reference is not one the tracker recognises. The message is on stderr. |
| 2 | Bad usage: an operation outside the contract, or a state or marker name outside its closed list. Nothing reached the tracker. |
| 3 | The adapter does not implement the operation. Nothing reached the tracker. For an optional operation, this is how a command learns to take its fallback. |
| 78 | The setting names no usable adapter, or the adapter's own setting is malformed. Nothing reached the tracker. |

## States and markers

The interface speaks of states, never labels, from one closed list: `needs-answers`, `ready`, `parked` and `audit`. A command passes them as exact tokens; any other name is refused with exit 2. `audit-codebase` never puts an issue in `ready` or `parked`.

| State | Meaning | Set by |
|---|---|---|
| `needs-answers` | A review is posted and waits for the author. | `reviewissue`; removed by `confirmissue` |
| `ready` | The issue is confirmed and may be built. | `confirmissue` |
| `parked` | An unattended run stopped on the issue. | the runner, which applies its own `labels.parked` on GitHub directly |
| `audit` | The issue holds a codebase audit's findings. | `audit-codebase` |

Markers are the text by which the commands find each other's output on an issue: `review` marks the review comment `reviewissue` posts, `confirmed-decisions` marks the section `confirmissue` writes into the issue body, and `review-pr` marks the summary of a pull request review. The `marker <name>` operation prints the text, and the commands write and look for exactly that. On GitHub they are `<!-- speckit:review -->`, `<!-- confirmed-decisions -->` and `<!-- review-pr -->`. Pull requests stay on GitHub, so every adapter returns `<!-- review-pr -->` for the last, and `review-pr`, `review-followup` and `chain-local.sh` use it as written.

## Issue references

A reference is whatever the user typed to name an issue. `ref` checks that the tracker recognises it and normalises it; every other operation takes the normalised form. On GitHub, `N` and `#N` normalise to `N` — digits with a leading `#` removed, nothing else changed — and an issue URL to `<owner>/<repo>#<N>`, GitHub's cross-repository form, which every operation also accepts.

`ref --forms` gives the two other forms a reference takes: `branch`, the text in a branch name `feature/<branch>-<slug>`, and `mention`, the text in a commit subject `Refs <mention>: …` and in a note pointing at the issue. On GitHub, issue 50 is `{"ref": "50", "branch": "50", "mention": "#50"}`. An adapter whose tracker uses keys such as `PROJ-12` returns the key for all three, so branches, commit subjects and pull request titles carry the key.

`branch-ref <branch>` reads a reference back out of a branch name: the shortest run of hyphen-separated words after the `<prefix>/` that `ref` recognises, with a slug after it. `feature/248-pr-closing-keyword` gives `248`, `feature/PROJ-12-add-thing` gives `PROJ-12` where the tracker recognises keys, and `feature/net10-upgrade` gives nothing. It is the dispatcher's, built on the adapter's `ref`, and an adapter does not implement it.

## Operations

Every operation is required except `comment-delete` and `search-title`. An operation that returns content prints one JSON value on stdout, never text for a shell to evaluate; one that only changes something prints nothing.

| Operation | Arguments | Output |
|---|---|---|
| `setup` | — | Makes sure every state exists in the tracker. One `added: …` or `present: …` line per state; a second run adds nothing. On GitHub, `added: label ready`. |
| `ref` | `<reference>`, or `--forms <reference>` | The normalised reference, one line; with `--forms`, `{"ref", "branch", "mention"}`. Exit 1 for a reference the tracker does not recognise. Reaches no tracker. |
| `view` | `<ref>` | The issue: `{"ref", "title", "body", "state", "states", "labels", "url", "links", "comments"}`. `state` is `open` or `closed`; `states` the contract states the issue is in; `labels` the tracker's own tags, for reading only; `links` `[{"kind", "url"}]`, where `kind` `closing-pull-request` is a pull request that will close it; `comments` `[{"id", "author", "created_at", "body", "url"}]`, oldest first, every one. |
| `create` | `--title <title> --body-file <file> [--state <state>]…` | `{"ref", "url"}` of the new issue, in the given states. |
| `body-set` | `<ref> <file>` | Replaces the body with the file's bytes. `{"ref", "url"}`. |
| `state-add`, `state-remove` | `<ref> <state>` | Nothing. Adding a state the issue is in, or removing one it is not, is not an error. |
| `comment-find` | `<ref> <marker name>` | The newest comment carrying the marker, by `created_at`, as a `comments` entry; `null` when there is none. |
| `comment-post` | `<ref> <file>` | Posts the file as a comment. `{"id", "url"}`. |
| `comment-edit` | `<ref> <id> <file>` | Replaces the comment's body with the file's bytes. `{"id", "url"}`. |
| `comment-delete` | `<ref> <id>` | Optional. Deletes the comment; nothing. Where it is missing, `confirmissue` overwrites the review with a one-line pointer to the issue's *Confirmed decisions*, carrying no marker, so the review is never found again. |
| `link` | `<ref> <other ref>` | Records that one issue relates to the other; nothing. On GitHub, a comment mentioning the other issue. |
| `close` | `<ref> <note file>` | Closes the issue with the note as its closing comment; nothing. |
| `pr-reference` | `<ref>` | What a pull request body may say about the issue, as one of `{"outcome": "linked", "line", "ref", "title"}` — an open issue of this repository, and `line` the text that closes it on merge (`Closes #N`); `{"outcome": "none", "reason", "line"}` — the lookup settled that nothing may be closed, and `line`, where not `null`, still references it (`Refs #N` for a closed issue); `{"outcome": "unverified", "reason"}` — the lookup could not answer (auth, network, rate limit). Exit 0 for all three: `raise-pr` abstains rather than fails. |
| `marker` | `<name>` | The marker's text, one line. Reaches no tracker. |
| `search-title` | `<text>` | Optional. `[{"ref", "title", "state", "url"}]` for every issue, open or closed, whose title holds the text. Where it is missing, `audit-codebase` runs with no baseline and says so. |

Three operations are the dispatcher's own: `require <operation>…` (exit 0 when the adapter implements them all, else the exit and message the first missing one would give), `operations` (`{"tracker", "settings", "required", "optional", "implemented"}`) and `branch-ref`.

On GitHub, `pr-reference` carries the check `raise-pr` used to make itself: GitHub numbers issues and pull requests from one sequence and resolves a transferred issue to another number, so the issue's whole URL must be this repository's issue URL for that number before `Closes` is written. A lookup that says nothing exists at that number is `none`; one that fails for any other reason is `unverified`, quoting `gh`.

## Permissions

A headless session denies, without asking, a command its permission rules do not allow ([`unattended.md`](unattended.md)). Two rules cover the tracker:

- **The chain** passes every stage `--allowedTools "Bash(bash <checkout>/tracker/tracker.sh *)"` for the checkout it loads the plugin from, unless it runs with `--skip-permissions`, where nothing is denied anyway. A stage needs nothing from the repository's settings to reach the tracker.
- **An interactive session** needs the allow rule `/gaffer:init` writes into `.claude/settings.json`: `Bash(bash */plugins/cache/*/gaffer/*/tracker/tracker.sh *)`. It matches the plugin as Claude Code installs it, under any configuration directory, marketplace and version, so it outlives a plugin update. Without it, each tracker call asks first. A session started with `claude --plugin-dir <checkout>` loads the plugin from outside the cache and is asked too; add `Bash(bash <checkout>/tracker/tracker.sh *)` to your own settings for it.

The commands write every call unquoted — `bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh view 50` — because that is the form the rules match. Each call stands alone, never piped into another command, which a rule for the tracker would not cover.

## Writing an adapter

An adapter is one bash script, `tracker/adapters/<name>.sh`, run as `bash <name>.sh <operation> [arguments…]` with the arguments the table above gives, after the dispatcher has checked the operation and any state or marker name. Add it by pull request here: the adapters ship with the plugin, so the chain's checkout and the installed plugin carry the same ones.

- `bash <name>.sh operations` prints the operations it implements, one per line. The dispatcher refuses the rest with exit 3 before calling it.
- `TRACKER_SETTINGS` holds the path of the settings file, or is empty, for an adapter that reads its own key. A malformed key of its own exits 78.
- Output is exactly the JSON the table gives, on stdout; errors go to stderr with exit 1.
- Every state maps to something the tracker shows, and `setup` makes it exist.
- `ref` must normalise its own output to itself, and must not reach the tracker: the chain calls it before a stage starts.

[`tracker/conformance.sh`](../tracker/conformance.sh) checks an adapter against this contract. Run it from the root of a repository whose settings name the adapter, against a tracker it may write to — it creates two issues, comments on them, sets every state, links them and closes both — and it prints `met`, `not met` with the reason, or `not implemented (optional)` for each operation, exiting 0 only when everything the adapter implements is met. What it cannot check is the tracker's own side: that a state shows where people look, or that a link is visible.

## What stays on GitHub

- Pull requests, their reviews, and `review-pr`, `review-followup`, `pre-review` and `chain-local.sh`'s review stage.
- The runner, [`chain/chain-next.sh`](../chain/chain-next.sh), which selects issues by label and parks them on GitHub. It refuses a settings file whose `tracker` is not `github`.
- `init/setup.sh check`, which checks the repository can take a pull request.

[`tracker/boundary.tests.sh`](../tracker/boundary.tests.sh) holds the line in CI: it fails when `gh issue`, an issue-comment REST path or an issue label call appears in a command, a default, a template or a script, outside the GitHub adapter and `chain/chain-next.sh`.
