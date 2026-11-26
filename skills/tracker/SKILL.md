---
name: tracker
description: How gaffer's commands reach the issue tracker. Load before carrying out any `tracker:` operation a gaffer command names, such as view, create, comment, state or close. This repository's tracker is Jira, through the Atlassian MCP connector.
---

# The tracker: Jira

A gaffer command names a tracker operation as `tracker: <operation> <arguments>`. This file says how to carry each one out with the Atlassian connector's Jira tools. A person may ask for one directly, as `/gaffer:tracker <operation> <arguments>`.

If the connector rejects a parameter, read its error, adjust the call, and still deliver what the operation yields. Never skip an operation, and never report one done that failed.

## Ground rules

- **Connect first.** Before the first operation that reaches Jira, call `getAccessibleAtlassianResources`. If the Atlassian tools are missing from the session, or the call fails for lack of authentication, the operation fails: tell the user to run `/mcp` and authenticate the Atlassian connector.
- **Site and project.** Read the repository's `CONVENTIONS.md` → *Issue tracker* section, which reads:

  ```markdown
  - **Jira site** — `example.atlassian.net`
  - **Project key** — `PROJ`
  - **Issue type** — `Task`
  ```

  It gives the site (`<site>`), the project key (`<P>`) and, optionally, the type `create` uses. Pass the site as `cloudId` on every call. Without a site, use the only accessible one. With none, or with no `<P>` where an operation needs it, the operation fails, naming the heading.
- **Text goes in as the tool's argument**, read from the file the command names, with `contentFormat` `markdown`. Read text back with `responseContentFormat` `markdown`.
- **Jira resolves no relative link and shows an HTML comment as visible text.** Before sending a body or comment, rewrite each link to a repository path as `https://github.com/<R>/blob/<default-branch>/<path>`, where `<R>` is origin's repository (below).
- **A failed call is a failed operation.** Pass on what the connector reported. Only an empty result means "none".
- **`<KEY>`** is a reference in its normal form, as `ref` gives it.
- **`<R>`**, wherever a GitHub call needs it, is origin's repository under its current name: take the `owner/repo` from `git remote get-url origin`, then resolve it once, with its default branch, by `gh repo view <owner/repo> --json nameWithOwner,defaultBranchRef`.

## States and markers

| State | Label |
|---|---|
| `needs-answers` | `gaffer-needs-answers` |
| `ready` | `gaffer-ready` |
| `parked` | `gaffer-parked` |

A Jira label exists as soon as an issue carries it and needs no creating. Labels compare exactly.

| Marker | Text |
|---|---|
| `review` | `gaffer:review` |
| `confirmed-decisions` | `gaffer:confirmed-decisions` |
| `review-pr` | `<!-- review-pr -->` |

`review-pr` marks pull request reviews, which stay on GitHub.

## Operations

### states

`states` checks the setup, then lists the states. It creates nothing. Connect, find `<site>` and `<P>` as the ground rules say, and call `getJiraProjectIssueTypesMetadata` for `<P>`. Where any step fails, or the project does not offer a type *Issue tracker* names, the operation fails, saying what to fix: the *Issue tracker* section to write, in the form above, and the types the project offers.

Otherwise report each state with its label as present, and name the type `create` would use for each kind of issue.

### ref

`ref <reference>` makes no call. A reference is a Jira key, such as `PROJ-12`, or a Jira issue URL ending `/browse/<KEY>`. A key is a capital letter, then capitals, digits or `_`, a hyphen, and a number with no leading zero. A key written in lower case is read in capitals. A bare number, `#N`, or anything else is not recognised, and the operation fails.

- Normal form, branch form and mention form are all the key in capitals: `PROJ-12`.
- A commit subject writes `Refs PROJ-12: …`. Never put a `#` command after the key: Jira's smart commits act on those.

### branch-ref

`branch-ref <branch>` makes no call. A branch named `<prefix>/<KEY>-<slug>` carries `<KEY>`: the text straight after the first `/`, in capitals, matching the key shape above, followed by `-` and a slug. `feature/PROJ-12-fix-x` carries `PROJ-12`; `feature/fix-12-x`, `feature/net10-upgrade` and `main` carry none.

### view

`view <ref>` reads the issue and its comments. `view <ref> no-comments` leaves `comment` out of `fields` and reports no comment.

Call `getJiraIssue` with `issueIdOrKey` `<KEY>` and `fields` `summary`, `description`, `status`, `labels`, `comment`.

- Title is `summary`; body is `description`; URL is `https://<site>/browse/<KEY>`.
- Closed when `status.statusCategory.key` is `done`; open otherwise.
- States: each label the table above maps to a state.
- Comments: each has `id`, `author.displayName`, `created` and `body`; its URL is the issue's URL with `?focusedCommentId=<id>`. Where `comment.total` exceeds the comments returned, the operation fails, saying how many were not read.
- Links: the open pull requests that carry the key. List them, and keep each whose `headRefName` gives `<KEY>` by `branch-ref`, or whose body holds the line `pr-reference` gives:

```bash
gh pr list --repo <R> --state open --json number,url,headRefName,body --limit 1000
```

### create

`create --title <title> --body-file <file>` calls `createJiraIssue` with `projectKey` `<P>`, `summary` the title, `description` the file's text, and `issueTypeName` the type *Issue tracker* names. Where it names none, choose from the types `getJiraProjectIssueTypesMetadata` offers, leaving out sub-task and epic types: for a defect, a type whose name contains `Bug`; for a new capability, `Story`; for anything else, or where that kind is not offered, `Task`, then `Story`. Where none fits, fail, listing the offered types. Report the type used. A description over 32,000 characters fails before the call. It yields the new key and `https://<site>/browse/<KEY>`.

### body-set

`body-set <ref> <file>` calls `editJiraIssue` with `fields` `{"description": "<the file's text>"}`.

### state-add

`state-add <ref> <state>` adds the state's label. `editJiraIssue` replaces the whole label set, so read the labels with `getJiraIssue` (`fields` `labels`), add the label if it is missing, and write the full list back as `fields` `{"labels": [...]}`. A label already there is no error.

### state-remove

`state-remove <ref> <state>` removes the state's label the same way: read the labels, drop it, write the full list back. A missing label is no error.

### comment-find

`comment-find <ref> <marker>` yields the newest comment whose body contains the marker's text, or none. Read the comments as `view` does and choose by `created`, never by `id`.

### comment-post

`comment-post <ref> <file>` calls `addCommentToJiraIssue` with `issueIdOrKey` `<KEY>` and `commentBody` the file's text, with no `commentId`. It yields the comment's `id` and its URL.

### comment-edit

`comment-edit <ref> <id> <file>` calls `addCommentToJiraIssue` as `comment-post` does, passing `commentId` `<id>`. It yields the id and URL.

### comment-delete

`comment-delete <ref> <id>`: the connector cannot delete a comment, so replace its body, as `comment-edit` does, with this text, which carries no marker:

> Removed by gaffer: folded into the issue. Delete by hand if wanted.

Report that it was overwritten, not deleted.

### link

`link <ref> <other ref>` calls `createJiraIssueLink` with type `Relates`, from `<KEY>` to the other key; `listJiraIssueLinkTypes` gives the site's name for that type. Where the connector offers no link tool, or the site has no such type, post a comment on the first issue reading `Related: <other KEY>`, and say which was done.

### close

`close <ref> <file>` posts the file as a comment, as `comment-post` does, then moves the issue to a done status. Of the transitions `getTransitionsForJiraIssue` gives into the Done category, prefer one whose name says the work was not done, such as Cancelled, Won't Do or Duplicate, else the only one, and call `transitionJiraIssue` with it. Where there is none, or several with nothing to choose between them, it fails after the comment, listing those offered. Report the transition used.

### pr-reference

`pr-reference <ref>` decides what a pull request body may write about the issue. It yields one of three outcomes and never fails a command.

Where `ref` does not recognise the reference, or `<P>` is known and the key's project is another, the outcome is **none**, with no lookup. Otherwise call `getJiraIssue` with `fields` `summary`, `status`.

- The call says the issue does not exist or cannot be seen: **none**, with no line.
- The call fails any other way, such as the connector missing, auth or network: **unverified**, quoting the connector. Never read this as none.
- The status category is `done`: **none**, with the line `Jira: [<KEY>](https://<site>/browse/<KEY>)`.
- Otherwise **linked**: the line is `Jira: [<KEY>](https://<site>/browse/<KEY>)`, and `summary` is the issue's title.

Jira closes nothing on merge: the line only links the two. The command writes the line exactly as given, and no closing line of its own.

### marker

`marker <name>` makes no call: the text is in the table above.

### search-title

`search-title <text>` calls `searchJiraIssuesUsingJql` with `jql` `project = "<P>" AND summary ~ "<text>"` and `fields` `summary`, `status`, escaping each `"` and `\` in the text with `\`. It yields each issue's key, title, open or closed by status category, and URL.

## What a headless stage needs allowed

The Atlassian connector's tools named above, as the session's MCP server names them, and the `git remote get-url origin`, `gh repo view` and `gh pr list` calls.
