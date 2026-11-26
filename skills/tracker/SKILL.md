---
name: tracker
description: How gaffer's commands reach the issue tracker. Load before carrying out any `tracker:` operation a gaffer command names, such as view, create, comment, state or close. This repository's tracker is GitHub issues.
---

# The tracker: GitHub issues

A gaffer command names a tracker operation as `tracker: <operation> <arguments>`. This file says how to carry each one out with `gh`. A person may ask for one directly, as `/gaffer:tracker <operation> <arguments>`.

The calls below are the ones to make. If `gh` rejects a flag or a field, read its error, adjust the call, and still deliver what the operation yields. Never skip an operation, and never report one done that failed.

## Ground rules

- **Name the repository on every call**: `--repo <R>`, or `repos/<R>/…` in a REST path. `<R>` is the `owner/repo` of `git remote get-url origin`, unless the reference names another repository. Never let `gh` choose: in a fork clone it picks the upstream.
- **REST paths have no leading `/`.**
- **Text goes in from a file** (`--body-file`, `-F body=@<file>`, `--input`), never inline, so quotes, backticks and `$` arrive intact.
- **A failed call is a failed operation.** Pass on what `gh` printed. Only an empty result means "none".
- **`<ref>`** is a reference in its normal form, as `ref` gives it. **`<N>`** is its issue number.

## States and markers

| State | Label | Label description |
|---|---|---|
| `needs-answers` | `needs answers` | A review is posted and awaiting the author's answers |
| `ready` | `ready` | The issue is confirmed and may be built |
| `parked` | `parked` | An unattended run stopped on this issue; remove to retry |

Label names compare without regard to case.

| Marker | Text |
|---|---|
| `review` | `<!-- speckit:review -->` |
| `confirmed-decisions` | `<!-- confirmed-decisions -->` |
| `review-pr` | `<!-- review-pr -->` |

## Operations

### states

`states` lists each state, the label that shows it, and whether that label exists. It creates nothing.

List the labels with `gh label list --repo <R> --limit 1000 --json name --jq '.[].name'`. Report each state with its label, as present or missing. For a missing one, give the command that creates it: `gh label create "<label>" --repo <R> --description "<description>"`.

### ref

`ref <reference>` makes no call. A reference is `N`, `#N`, an issue URL or `owner/repo#N`; anything else is not recognised, and the operation fails.

- Normal form: the bare number `N` for an issue of this repository, however it was written; `owner/repo#N` for another repository's.
- Branch form: `N`.
- Mention form, for commit subjects and prose: `#N`. A commit message writes `Refs #N` and never `Fixes`, `Closes` or `Resolves`: GitHub closes the issue the moment such a commit reaches the default branch.

Another repository's issue has no branch form. Where a command needs one, the operation fails.

### branch-ref

`branch-ref <branch>` makes no call. A branch named `<prefix>/<N>-<slug>` carries `N`: the digits straight after the first `/`, followed by `-` and a slug. `feature/248-fix-x` carries `248`; `feature/net10-upgrade` and `main` carry none.

### view

`view <ref>` reads the issue and all its comments.

```bash
gh issue view <N> --repo <R> --json number,title,body,state,labels,url,closedByPullRequestsReferences
gh api --paginate repos/<R>/issues/<N>/comments
```

- If `url` does not end `/issues/<N>`, the number is a pull request: the operation fails.
- `state`: open or closed.
- `url`: the issue's page.
- States: each label that the table above maps to a state.
- Links: each URL in `closedByPullRequestsReferences` is a pull request that will close the issue. That field needs `gh` 2.73.0 or later; on an older `gh`, stop and say so.
- Comments: read every page. Each has `id`, `user.login`, `created_at`, `body` and `html_url`.

### create

`create --title <title> --body-file <file>`

```bash
gh issue create --repo <R> --title "<title>" --body-file <file>
```

It prints the new issue's URL, whose last segment is its reference.

### body-set

`body-set <ref> <file>` replaces the whole body. Write the file's text as JSON to a scratch file beside it, then send it:

```bash
jq -n --rawfile b <file> '{body: $b}' > <patch file>
gh api --method PATCH repos/<R>/issues/<N> --input <patch file> --jq .html_url
```

### state-add

`state-add <ref> <state>`: `gh issue edit <N> --repo <R> --add-label "<label>"`. A label the issue already has is no error.

### state-remove

`state-remove <ref> <state>`: `gh issue edit <N> --repo <R> --remove-label "<label>"`. A label the issue lacks is no error.

### comment-find

`comment-find <ref> <marker>` yields the newest comment whose body contains the marker's text, or none. List the comments as `view` does, every page, and choose by `created_at`, never by `id`.

### comment-post

`comment-post <ref> <file>`: `gh issue comment <N> --repo <R> --body-file <file>`. It prints the comment's URL, which ends `#issuecomment-<id>`.

### comment-edit

`comment-edit <ref> <id> <file>` replaces the comment's body:

```bash
gh api -X PATCH repos/<R>/issues/comments/<id> -F body=@<file> --jq '{id, url: .html_url}'
```

### comment-delete

`comment-delete <ref> <id>`: `gh api --method DELETE repos/<R>/issues/comments/<id>`. GitHub offers no undo and sends no notification.

### link

`link <ref> <other ref>` posts a comment on the first issue that mentions the other:

```bash
gh issue comment <N> --repo <R> --body "Related: #<M>"
```

Write `owner/repo#<M>` where the two issues are in different repositories.

### close

`close <ref> <file>` closes the issue with the file's text as its closing comment: `gh issue close <N> --repo <R> --comment "$(cat <file>)"`.

### pr-reference

`pr-reference <ref>` decides what a pull request body may write about the issue. It yields one of three outcomes and never fails a command.

Drop leading zeros from `<N>`. Another repository's issue, or a number that is all zeros, is **none** with no lookup. Otherwise:

```bash
gh issue view <N> --repo <R> --json number,state,title,url
```

- The call fails saying it could not resolve to an issue or pull request: **none**, with no line.
- The call fails any other way, such as auth, network or rate limit: **unverified**, quoting `gh`. Never read this as none.
- `url` is not exactly `https://github.com/<R>/issues/<N>`, case aside: **none**, with no line. GitHub numbers issues and pull requests in one sequence, and a transferred issue resolves elsewhere.
- `state` is not `OPEN`: **none**, with the line `Refs #<N>`.
- Otherwise **linked**: the line is `Closes #<N>`, and `title` is the issue's title.

The command writes the line exactly as given, and no closing line of its own.

### marker

`marker <name>` makes no call: the text is in the table above.

### search-title

`search-title <text>` yields the issues, open or closed, whose title matches:

```bash
gh issue list --repo <R> --state all --search "<text> in:title" --json number,title,state,url --limit 100
```
