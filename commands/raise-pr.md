---
description: Raise a PR for the current feature branch — composes a PR body sized to the change and pushes. The review-pr workflow reviews the PR once it is opened ready, or marked ready.
argument-hint: "[--draft] [issue number or URL]"
---

Read `CLAUDE.md` for project context, and the conventions as *Repository conventions* below says, before proceeding.

## User Input

```text
$ARGUMENTS
```

Optionally an issue reference the repository's tracker recognises — on GitHub bare (`248`), hashed (`#248`), or a full issue URL — naming the issue this PR closes. Empty is the normal case and is **not** a prompt: step 4 infers a candidate from the branch instead. `/gaffer:raise-pr` never asks the invoker for anything, so it stays composable by an automated chain with no interactive gate.

One flag, anywhere in the arguments:

- `--draft` — open the pull request as a draft. The chain passes it when a repository opts in to the pre-review, so the repository's own review does not start until `/gaffer:pre-review` marks the pull request ready ([`docs/chain.md`](../docs/chain.md)). Without it — the normal case, and always the case by hand unless you type it — the pull request is opened ready for review.

## Repository conventions

The steps in this file are generic. The conventions they run on live in two files, read section by section: the plugin's defaults in `${CLAUDE_PLUGIN_ROOT}/defaults/CONVENTIONS.md`, and the repository's own `CONVENTIONS.md` at the root of the repository this command runs in, written as additions to the defaults. Each step applies its own rule together with the two sections under the matching heading — the default first, then the repository's, which wins where they conflict, and stands alone where its first line is `Replaces the default.`. Wherever this file says `CONVENTIONS.md` → *Heading*, it means those two sections read that way. The headings this command reads:

| Heading | Supplies |
|---|---|
| `Scratch files` | the git-ignored file step 6 writes the body to |
| `Pull requests` | any check the repository runs on the issue link, which step 4's abstain turns red |
| `Change-intent records` | where the records step 4 links from the body live |

A section under any other heading is read too, and applied where its text says. Where neither file has a heading, the step concerned runs on its generic rule alone, and the final report names each heading found in neither. A step whose convention is the thing itself — the command to run, the file to write — has no generic rule and no default, so where the repository supplies none the command STOPS rather than invent one, with the reason `conventions missing: <heading>`. The repository's `CONVENTIONS.md` is read from the root of the repository this command runs in, and trusted as this command file is. The harness itself is not a repository convention: the verdict protocol, whatever drives the chain by reading it, and the sibling commands stay named in the steps, so whoever edits the protocol sees what consumes it.

## Steps

Every STOP below is a **failure**, so each ends its report with step 7's failure verdict, carrying the reason given here, as the last line and nothing after it — the explanatory sentence for a human goes *above* it. A stop message whose last line is not the verdict reaches whatever drives the chain as the far less useful `no readable verdict` instead of the reason, and a runner that parks a failed issue then parks it with that non-reason.

1. **Get branch name**: Run `git rev-parse --abbrev-ref HEAD`. If the result is `main`, stop immediately and output: "Run /gaffer:raise-pr from a feature branch, not main." Reason: `/gaffer:raise-pr was run on main, not a feature branch`.

2. **Check for commits**: Run `git log main..HEAD --oneline`. If the output is empty, stop immediately and output: "No commits found on this branch compared to main — nothing to raise a PR for." Reason: `no commits on this branch over main`.

3. **Infer PR title**: Take the branch name from step 1, strip any leading path segment (`feat/`, `fix/`, `chore/`, `docs/`, etc.), strip the issue reference leading the remaining segment with its hyphen, replace hyphens with spaces, and apply title case. The reference is whatever `bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh branch-ref <branch>` prints, in the `branch` form `bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh ref --forms <that>` gives — on GitHub the `NNN` of a leading `NNN-` — and where `branch-ref` exits non-zero there is none to strip. Examples: `feature/316-remove-planning-pipeline` → `Remove Planning Pipeline`; `chore/docs-tidy` → `Docs Tidy`. Every tracker call goes through the tracker interface, its script path written unquoted as here so the allow rule `/gaffer:init` writes matches it, and a reference the user typed in single quotes, since unquoted a leading `#` starts a shell comment, never a tracker's own CLI or API; [`docs/tracker.md`](../docs/tracker.md) is the contract.

4. **Compose PR body**: Read `git log main..HEAD` and `git diff main...HEAD` first, so the body describes what actually changed, not what the branch name suggests. Write a description sized to the change. **Do not follow a fixed template.** Decide which sections earn their place based on what's actually in this PR.

   **First, settle the closing keyword.** A merged PR must close the issue it implemented without the invoker having to remember to ask for it, so decide this every time — not only when someone thinks to mention an issue:

   - **Find a candidate.** A reference supplied by the invoker wins over anything inferred; normalise it with `bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh ref '<reference>'`. Otherwise take the reference leading a branch of the `<prefix>/<N>-<slug>` shape `/gaffer:build` produces, with `bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh branch-ref <branch>`, so `feature/248-pr-closing-keyword` yields `248`. Where either exits 1 there is **no candidate**; any other exit is the **unverified** outcome below, quoting what it printed, because the tracker setting is at fault, not the branch: `feature/build-command` has no reference, and `branch-ref` never takes a number from inside a word, so `feature/net10-upgrade` does not yield `10`. Use what it printed as `<N>` in every check and message below.
   - **A candidate is only ever a candidate.** However it arrived — typed by the invoker or parsed from the branch — it is unverified until the tracker confirms it. The invoker's reference wins the *sourcing*, never the *checking*: a hand-typed digit is if anything easier to get wrong than a parse, so `/gaffer:raise-pr 247` (a PR number) and `/gaffer:raise-pr 24` (a slip for `248`) must not sail through.
   - **Verify it** with `bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh pr-reference <N>`. It always exits 0 once it has a reference, and prints one of three outcomes as JSON. It is where the checks live that make a `Closes` safe: on GitHub, that the number is an open issue of this repository and not a pull request at the same number, an issue of another repository, or a transferred issue that now redirects.
   - **Report one of three outcomes — never fold the last two together.**
     - **Linked** — `{"outcome": "linked", "line": …, "title": …}`. Put its `line` (on GitHub, `Closes #<N>`) on its own line in **Related**.
     - **No issue** — `{"outcome": "none", "reason": …, "line": …}`: the lookup settled the question, and the reason says what disqualified it (a pull request, a closed issue, another repository's issue, nothing at that number). Add no closing keyword. Where `line` is not `null` — a real but closed issue in *this* repository, for which GitHub gives `Refs #<N>` — still record it in **Related**: dropping the closing keyword is the safety property, dropping every trace of the link is collateral damage.
     - **Unverified** — `{"outcome": "unverified", "reason": …}`: the lookup could not answer at all — expired auth, no network, rate limit, the tracker's tool missing. Add no closing keyword, and say the check could not run, quoting its `reason`. Reporting a fixable auth failure as "no such issue" sends the invoker looking in the wrong place.
   - A failed lookup here is **not** a stop-on-failure condition for the calling chain — it is an abstain, reported rather than fatal. Compose the rest of the body and carry on. That holds for a non-zero exit from `pr-reference` too: report it as unverified, quoting what it printed.
   - **An abstain is no longer free, and the report must say so.** Where the repository gates pull requests on an issue link (`CONVENTIONS.md` → *Pull requests* names the check), both outcomes above raise a PR whose check reports **red**. Still abstain rather than guess — a wrong `Closes` is worse than an absent one — but name the red check in the step 7 report so the invoker knows an edit is owed. Such a check re-runs when the body is edited, so fixing it needs no new push.
   - What this proves is bounded, and worth knowing: that `<N>` is an open issue in this repo, never that it is *this branch's* issue, and it can change state between here and merge. Restricting inference to the `/gaffer:build` shape is what keeps that gap narrow.
   - The PR body is the *only* place a closing keyword belongs — never a commit message, which would close the issue as soon as it reached `main`, ahead of review.
   - Whichever way it lands, step 7 reports it.

   **Guiding principle — don't duplicate things a reviewer can get elsewhere.** GitHub already shows:
   - the list of changed files and their diffs
   - the commit list and commit messages
   - line-count statistics, additions/deletions
   - the author, base/head branches, and CI status

   Don't repeat any of that in the body. Use the body for things a reviewer *can't* easily get from the code or git history.

   **Sections to consider** (include each only if it adds value for this PR):

   - **Why** — motivation or context that isn't already obvious from commit messages. Skip for trivial PRs where the title is self-explanatory.
   - **What changes** — a short summary of observable changes. For single-theme PRs, 1–3 bullets. For multi-theme PRs, group by theme rather than by file. Describe *what* changed at a behaviour level, not which files were touched.
   - **Non-obvious things a reviewer should know** — caveats, deliberate trade-offs, hidden invariants, anything in the diff that looks weird but is intentional. Omit if there are none. **Where the branch adds a change-intent record (`CONVENTIONS.md` → *Change-intent records* says where they live), link it here and stop** — the record already holds the rejected alternatives and the reasoning, so restating them is the same words in two places. Add only what the record does not carry.
   - **How to verify** — a markdown checklist of concrete actions a reviewer can perform. Derive items from what actually changed. Omit for pure-documentation PRs where there's nothing functional to exercise.
   - **Related** — the `Closes #<N>` (or `Refs #<N>`) line settled above — the `line` step 4's lookup gave — plus links to prior PRs or related issues that give context. This section always survives when step 4 settled a keyword, whatever the PR's size.

   A tiny PR may collapse to two sections. A sprawling PR may use all five. Match the size of the body to the size of the change.

5. **Push branch**: Run `git push -u origin <branch>`.

6. **Create PR**: Write the body from step 4 to a git-ignored scratch file (`CONVENTIONS.md` → *Scratch files* names it) with the native `Write` tool, never a shell heredoc, then run `gh pr create --title "<inferred title>" --body-file <scratch file>` with the title from step 3, adding `--draft` when the invocation carried it. Passing the body as a file keeps the backticks and `$` in it out of the shell, where a double-quoted `--body` or an unquoted heredoc would expand them. Capture the PR URL from the output.

7. **Output result**: First say whether the pull request was opened as a draft, then print step 4's outcome in whichever of its three forms applies — `<line> — <issue title>` (on GitHub, `Closes #<N> — <issue title>`); `No closing keyword: <reason>` (the branch carries no issue number; `#<N>` is a pull request; `#<N>` is closed); or `Closing keyword unverified: <reason>` — so the invoker can see from the output alone what merging this PR will close, if anything.

    **Then close the report with the verdict as its last line** — one JSON object on one line, at column 1, nothing else on that line and nothing after it. Exactly one of:

    - `{"schema": 1, "outcome": "raised", "pr": "<url>"}` — naming the pull request this run opened, and only for a pull request this run actually opened.
    - `{"schema": 1, "outcome": "failed", "reason": "<short reason>"}` — if no PR was opened, for any reason. Never the `raised` verdict then, even when the report above quotes the URL of a PR that already exists.

    The schema — its fields, what each outcome carries, and how it is read — is [`docs/verdict-schema.md`](../docs/verdict-schema.md) in the plugin (`${CLAUDE_PLUGIN_ROOT}/docs/verdict-schema.md`). That object is the machine-readable verdict: whatever drives the chain reads only what ends the report, so anything written after it — a next-steps note — costs the run its verdict *after* a real pull request is already open, which is the worst moment to lose it; a code fence around the verdict is tolerated, a sentence after the fence is not. A URL in the prose above is deliberately not enough, because the commonest failure here — a PR already open for this branch — reports an error whose text contains a perfectly good PR URL; the chain reads the `pr` field and nothing else. Two limits apply, and both cost the verdict at that same worst moment: **the URL must be bare**, so write `"pr": "https://github.com/o/r/pull/9"` and not a markdown autolink (`<…>`) or link (`[…](…)`); and **nothing else may share the line**, so a parenthetical such as `{…} (draft, CI red)` is read as no verdict at all.
