# The tracker interface: GitHub issues

How a command performs a tracker operation from this checkout. A command names an operation and its arguments, such as `view <ref>`; this file says how to carry it out.

## Running an operation

Each operation is one Bash call to `tracker.sh`, the script in the directory this file was read from:

```bash
bash <that directory>/tracker.sh <operation> [arguments…]
```

- Write the script's absolute path unquoted, and each call as a command of its own, never piped, chained or wrapped: a permission rule for the script then matches it.
- Put a reference the user typed in single quotes (`ref '#50'`): unquoted, a leading `#` starts a comment.
- `<ref>` is a reference as `ref` printed it. `<file>` is a file holding the text.
- Output is JSON on stdout unless stated otherwise.
- Exit 0 is success. Exit 1: the operation failed, or the reference is not recognised. Exit 2: a missing argument, or an unknown operation, state or marker. Exit 78: `github.labels` is malformed. On 2 and 78 nothing reached GitHub. The reason is on stderr; pass it on.
- Calls go to the `origin` remote's repository, or to the one a reference names.

## States and markers

The states are `needs-answers`, `ready`, `parked` and `audit`. Each is a GitHub label of the same name, except `needs answers` for the first; `github.labels` in `.gaffer/chain.json` may rename them.

The markers are `review`, `confirmed-decisions` and `review-pr`.

## Operations

### setup

`setup` creates the label of every state that lacks one. Prints `added: label <name>` or `present: label <name>` for each.

### ref

`ref <reference>` prints the normalised reference, one line. `ref --forms <reference>` prints `{"ref", "branch", "mention"}`: `branch` is its form in a branch name, `mention` its form in commit subjects and prose. Issue 50 gives `50`, `50` and `#50`.

Recognised: `N`, `#N`, an issue URL, `owner/repo#N`. Anything else is exit 1, as is another repository's issue with `--forms`, since no branch name here can carry it. Makes no GitHub call.

### branch-ref

`branch-ref <branch>` prints the reference a branch named `<prefix>/<N>-<slug>` carries, one line: `feature/248-fix-x` gives `248`. Exit 1 where the branch carries none. Makes no GitHub call.

### view

`view <ref>` prints the issue: `{"ref", "title", "body", "state", "states", "labels", "url", "links", "comments"}`.

- `state`: `open` or `closed`.
- `states`: the states the issue is in.
- `labels`: every label on it, for reading only.
- `links`: `[{"kind", "url"}]`; kind `closing-pull-request` is a pull request that will close the issue.
- `comments`: `[{"id", "author", "created_at", "body", "url"}]`, oldest first, all of them.

Exit 1 for a pull request's number. Needs `gh` 2.73.0 or later, and says so.

### create

`create --title <title> --body-file <file> [--state <state>]…` raises an issue in the given states. Prints `{"ref", "url"}`.

### body-set

`body-set <ref> <file>` replaces the issue's body. Prints `{"ref", "url"}`.

### state-add

`state-add <ref> <state>` puts the issue in the state. Prints nothing. A state it is already in is no error.

### state-remove

`state-remove <ref> <state>` takes the issue out of the state. Prints nothing. A state it is not in is no error.

### comment-find

`comment-find <ref> <marker>` prints the newest comment containing that marker's text, as one `comments` entry, or `null` where there is none.

### comment-post

`comment-post <ref> <file>` posts a comment. Prints `{"id", "url"}`.

### comment-edit

`comment-edit <ref> <id> <file>` replaces a comment's body. Prints `{"id", "url"}`.

### comment-delete

`comment-delete <ref> <id>` deletes a comment for good. Prints nothing.

### link

`link <ref> <other ref>` records on the first issue that it relates to the other, as a comment mentioning it. Prints nothing.

### close

`close <ref> <file>` closes the issue, with the file as its closing comment. Prints nothing.

### pr-reference

`pr-reference <ref>` says what a pull request body may write about the issue. Exit 0 for any recognised reference, printing one of:

- `{"outcome": "linked", "line", "ref", "title"}`: an open issue of this repository. `line` closes it when the pull request merges.
- `{"outcome": "none", "reason", "line"}`: nothing may be closed. `line`, unless `null`, still refers to the issue.
- `{"outcome": "unverified", "reason"}`: the lookup could not answer.

Write `line` exactly as printed, and no closing line of your own.

### marker

`marker <name>` prints the marker's text, one line. Makes no GitHub call.

### search-title

`search-title <text>` prints `[{"ref", "title", "state", "url"}]`: the issues, open or closed, whose title matches the text, up to 100.
