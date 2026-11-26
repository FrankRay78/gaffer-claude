# The tracker skill

Every command that reaches the issue tracker does so through one plugin skill, [`skills/tracker/SKILL.md`](../skills/tracker/SKILL.md), which Claude Code loads as `gaffer:tracker`. A command names an operation in plain notation, such as `tracker: view <ref>`, and tells the agent near its top to load the skill before the first one; the skill says how to carry each operation out. The file this plugin ships says GitHub, as `gh` calls the agent makes itself, so when a `gh` version or a response differs slightly the agent adjusts and still delivers what the operation yields.

The plugin ships no tracker script, and no setting chooses a tracker: the tracker is whatever the skill file says. This page is for someone whose issues live elsewhere and who replaces that file.

## Replacing the file

Keep a clone of the plugin whose `skills/tracker/SKILL.md` holds instructions for your tracker — an authenticated MCP connector your own Claude Code settings allow, for instance — and change nothing else. Nothing beside that file needs editing for another tracker: no command, default, template, script or test.

- **Run from the clone.** Start sessions with `claude --plugin-dir <clone>`, and run the chain by hand as `bash <clone>/chain/chain.sh <issue>`, which loads its stages from the checkout it sits in ([`chain.md`](chain.md)).
- **Keep the frontmatter's `name: tracker`, and leave model invocation enabled.** A command loads the skill by that name, and a skill the model may not invoke cannot be loaded by one.
- **Keep it short.** Every command that reaches the tracker loads the whole file. This plugin's is held to 1,500 words (`wc -w skills/tracker/SKILL.md`).
- **State every operation below, with its arguments and what it yields.** A command says only `tracker: <operation> <arguments>`; everything else about the tracker is the file's to say.

Claude Code re-attaches a loaded skill after it compacts a conversation. A subagent does not inherit a skill its parent loaded, which is why each command file tells whoever is applying it to load the skill.

## Operations

Every operation is required. No command carries a fallback for a missing one: where a tracker has no native means for an operation, the file meets the stated outcome its own way, as this plugin's file does for `link`, which on GitHub is a comment mentioning the other issue.

| Operation | Arguments | Must yield |
|---|---|---|
| `setup` | — | Every state exists in the tracker. Says which it added and which were present. |
| `ref` | `<reference>` | The reference in its normal form, and its forms for a branch name and for commit subjects and prose. Refuses a reference the tracker does not recognise. |
| `branch-ref` | `<branch>` | The reference a branch name carries, or none. |
| `view` | `<ref>` | The issue's title, body and URL, whether it is open or closed, the states it is in, the pull requests that will close it, and every comment with its id, author, time and body. |
| `create` | `--title <title> --body-file <file> [--state <state>]…` | A new issue with that title and body, in the given states. Its reference and URL. |
| `body-set` | `<ref> <file>` | The issue body replaced with the file's text. |
| `state-add`, `state-remove` | `<ref> <state>` | The issue put in, or taken out of, the state. Repeating either is no error. |
| `comment-find` | `<ref> <marker>` | The newest comment carrying the marker, by time, or none. |
| `comment-post` | `<ref> <file>` | The file posted as a comment. Its id and URL. |
| `comment-edit` | `<ref> <id> <file>` | The comment's body replaced with the file's text. Its id and URL. |
| `comment-delete` | `<ref> <id>` | The comment removed. |
| `link` | `<ref> <other ref>` | A record on the first issue that it relates to the other. |
| `close` | `<ref> <file>` | The issue closed, with the file as its closing note. |
| `pr-reference` | `<ref>` | What a pull request body may write about the issue: see below. |
| `marker` | `<name>` | The text of the marker. |
| `search-title` | `<text>` | The issues, open or closed, whose title matches. |

**A failed operation is a failure, never an empty answer.** The commands treat only an answer of none as "there is none": `reviewissue` posts a first review when `comment-find` yields none, so a lookup that failed must say so, with what the tracker reported.

**References.** `ref` gives three forms of one reference. The normal form is what every other operation takes as `<ref>`. The branch form is the `<N>` in the branch `build` creates, `feature/<N>-<slug>`, and `branch-ref` must read it back out of that name. The mention form is what a commit subject and prose carry: `Refs <mention>: …`. On GitHub issue 50 is `50`, `50` and `#50`; a tracker with keys such as `PROJ-12` may give the key for all three. `ref` and `branch-ref` reach no tracker in this plugin's file, and `draftissue` and `graft` use `ref` to tell an issue from free text, so a reference it refuses is read there as not an issue.

**`pr-reference`** has three outcomes, and never fails the command that asked:

- **linked** — an open issue of this repository: the issue's title, and the line that closes it when the pull request merges.
- **none** — nothing may be closed: a pull request at that number, a closed issue, an issue that lives elsewhere, or nothing there. It may still give a line that only refers to the issue, as this plugin's file does for a closed one.
- **unverified** — the lookup could not answer: authentication, network, a rate limit. Never reported as none.

`raise-pr` writes the line exactly as given and no closing line of its own, so the closing word for the repository's host lives in the skill file. The same holds for commits: this plugin's file says a commit subject writes `Refs #N` and never a word that closes the issue.

## States and markers

A command speaks of states, never labels. There are four, and `setup` makes each exist.

| State | Meaning | Set by |
|---|---|---|
| `needs-answers` | A review is posted and waits for the author. | `reviewissue`; removed by `confirmissue` |
| `ready` | The issue is confirmed and may be built. | `confirmissue` |
| `parked` | An unattended run stopped on the issue. | the runner, on GitHub directly |
| `audit` | The issue holds a codebase audit's findings. | `audit-codebase` |

On GitHub they are the labels `needs answers`, `ready`, `parked` and `audit`, named in the skill file and nowhere else in a command.

Markers are the text by which the commands find each other's output. `review` marks the comment `reviewissue` posts, and `confirmed-decisions` the section `confirmissue` writes into the issue body; a command writes and looks for exactly the text `marker` gives. In this plugin's file they are `<!-- speckit:review -->` and `<!-- confirmed-decisions -->`, which GitHub does not render. `review-pr` marks the summary of a pull request review; pull requests stay on GitHub, where `review-pr` and `review-followup` write it as `<!-- review-pr -->`, so a replacement file gives that same text.

## What a headless stage needs allowed

A headless session denies, without asking, any call its permission rules do not allow ([`unattended.md`](unattended.md)). `chain.sh` passes its stages no permission rule for the tracker. A stage run with `--skip-permissions` is denied nothing; a stage run under the repository's own permissions needs whatever the skill file's calls need allowed, by the repository's settings or the user's.

With this plugin's file, those calls are:

| Calls | Operations | Needed by |
|---|---|---|
| `git remote get-url origin` | every operation that reaches GitHub | every command below |
| `gh issue view`, `gh api` reading an issue's comments | `view`, `comment-find`, `pr-reference` | the chain's stages (`build`, `raise-pr`), `review-pr`, and the issue commands |
| `gh issue create`, `gh issue edit`, `gh issue comment`, `gh issue close`, `gh api` writing an issue or a comment, `jq` | `create`, `state-add`, `state-remove`, `comment-post`, `comment-edit`, `comment-delete`, `body-set`, `link`, `close` | `draftissue`, `reviewissue`, `confirmissue`, `graft`, `audit-codebase` |
| `gh issue list` | `search-title` | `audit-codebase` |
| `gh label list`, `gh label create` | `setup` | `init` |

`verify` and `pre-review` use only `ref` and `branch-ref`, which make no call. Loading the skill needs no rule of its own. A replacement file that reaches its tracker through an MCP connector needs that connector's tools allowed instead.

## What stays on GitHub

- **Pull requests and their reviews.** `raise-pr`, `pre-review`, `review-pr` and `review-followup` reach them with `gh`, and `init` delivers its recommendations as a pull request.
- **The unattended runner.** [`chain/chain-next.sh`](../chain/chain-next.sh) selects issues by label and parks them with `gh` itself, under the names its own `labels` setting gives ([`chain.md`](chain.md)). It loads no skill and stays GitHub-only: with another tracker, run `chain.sh` by hand. It refuses a `tracker` setting as a key it does not know.
- **Links to files.** `reviewissue` and `confirmissue` write links to the repository's files as absolute GitHub URLs, because that is where the code is hosted.
