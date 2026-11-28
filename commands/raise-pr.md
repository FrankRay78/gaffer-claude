---
description: Raise a PR for the current feature branch — composes a PR body sized to the change and pushes. The review-pr workflow reviews the PR once it is opened ready, or marked ready.
argument-hint: "[--draft] [issue reference]"
---

Read `CLAUDE.md` for project context, and the conventions as *Repository conventions* below says, before proceeding.

## User Input

```text
$ARGUMENTS
```

Optionally an issue reference the repository's tracker recognises, such as `248` or `#248`, naming the issue this PR closes. Empty is the normal case and is **not** a prompt: step 4 infers a candidate from the branch instead. `/gaffer:raise-pr` never asks the invoker for anything, so it stays composable by an automated chain with no interactive gate.

**Load the `gaffer:tracker` skill with the Skill tool before the first tracker operation.** A line written `tracker: <operation> <arguments>` names an operation that skill says how to carry out on this repository's tracker; it is notation, not a command to run.

One flag, anywhere in the arguments:

- `--draft` — open the pull request as a draft. The chain always passes it, so the repository's own review does not start until `/gaffer:pre-review` marks the pull request ready ([`docs/chain.md`](../docs/chain.md)). Without it — the normal case, and always the case by hand unless you type it — the pull request is opened ready for review.

## Repository conventions

The steps in this file are generic. The conventions they run on live in two files, read section by section: the plugin's defaults in `${CLAUDE_PLUGIN_ROOT}/defaults/CONVENTIONS.md`, and the repository's own `CONVENTIONS.md` at the root of the repository this command runs in, written as additions to the defaults. Each step applies its own rule together with the two sections under the matching heading — the default first, then the repository's, which wins where they conflict, and stands alone where its first line is `Replaces the default.`. Wherever this file says `CONVENTIONS.md` → *Heading*, it means those two sections read that way. The headings this command reads:

| Heading | Supplies |
|---|---|
| `Scratch files` | the git-ignored file step 6 writes the body to |
| `Pull requests` | any title form step 3 writes the title in, with the check that enforces it, and any check the repository runs on the issue link, which step 4's abstain turns red |
| `Public API and breaking changes` | the surface step 3 judges a title form's breaking marker against |
| `Change-intent records` | where the records step 4 links from the body live |

A section under any other heading is read too, and applied where its text says. Where neither file has a heading, the step concerned runs on its generic rule alone, and the final report names each heading found in neither. A step whose convention is the thing itself — the command to run, the file to write — has no generic rule and no default, so where the repository supplies none the command STOPS rather than invent one, with the reason `conventions missing: <heading>`. The repository's `CONVENTIONS.md` is read from the root of the repository this command runs in, and trusted as this command file is. The harness itself is not a repository convention: the verdict protocol, whatever drives the chain by reading it, and the sibling commands stay named in the steps, so whoever edits the protocol sees what consumes it.

## Steps

Every STOP below is a **failure**, so each ends its report with step 7's failure verdict, carrying the reason given here, as the last line and nothing after it — the explanatory sentence for a human goes *above* it. A stop message whose last line is not the verdict reaches whatever drives the chain as the far less useful `no readable verdict` instead of the reason, and a runner that parks a failed issue then parks it with that non-reason.

1. **Get branch name**: Run `git rev-parse --abbrev-ref HEAD`. If the result is `main`, stop immediately and output: "Run /gaffer:raise-pr from a feature branch, not main." Reason: `/gaffer:raise-pr was run on main, not a feature branch`.

2. **Check for commits**: Run `git log main..HEAD --oneline`. If the output is empty, stop immediately and output: "No commits found on this branch compared to main — nothing to raise a PR for." Reason: `no commits on this branch over main`.

3. **Infer PR title**: First take the slug. Starting from the branch name from step 1, strip any leading path segment (`feat/`, `fix/`, `chore/`, `docs/`, etc.), then strip the issue reference at the start of what remains, with its hyphen, and replace the remaining hyphens with spaces. The reference is the one `tracker: branch-ref <branch>` yields. Match it whatever its case, because a tracker may yield it in a different case from the branch's spelling: `feature/dev-112-fix-login` gives `fix login` where `branch-ref` yields `DEV-112`. Where `branch-ref` yields none there is nothing to strip. Then write the title by whichever rule `CONVENTIONS.md` → *Pull requests* calls for:

   - **No title form named** — the section names none, or neither file has the heading at all, which is no reason to stop. Apply title case to the slug: `feature/316-remove-planning-pipeline` → `Remove Planning Pipeline`; `chore/docs-tidy` → `Docs Tidy`; `feature/dev-112-fix-login` → `Fix Login`.
   - **A title form named** — write the title in that form, every part of it as the form describes:
     - **The description** is the slug, recased as the form asks, such as lower-case imperative.
     - **The issue key** is step 4's candidate reference in the form the tracker gives it, never as the branch spells it: its normal form from `tracker: ref`, or its mention form where the form writes the key as a mention, such as `#<N>`. It is settled once step 4 has run its lookup, before step 6 uses the title. Leave the key out where step 4 finds no candidate, or where its lookup settles that no issue is there: a pull request, or nothing at that number. A closed issue, or a lookup that could not run, still gives the key.
     - **Where the key is left out**, leave out the part of the form that holds it and write the rest as normal; do not stop. Where the form requires a key, the title then fails its check, and step 7 reports that check as red.
     - **The type, and any scope**, fit what the change does, judged from the commits and diff step 4 reads and, where step 4 linked an issue, the issue's title: a bug fix is not titled as a new feature, nor a new capability as a fix. Choose only among the types the form allows, and add a scope only where the form allows one and one part of the code clearly holds the change.
     - **The breaking marker**, where the form has one, goes on a change that breaks the surface `CONVENTIONS.md` → *Public API and breaking changes* names, and on no other change.

4. **Compose PR body**: Read `git log main..HEAD` and `git diff main...HEAD` first, so the body describes what actually changed, not what the branch name suggests. Write a description sized to the change. **Do not follow a fixed template.** Decide which sections earn their place based on what's actually in this PR.

   **First, settle the closing line.** A merged PR must close the issue it implemented without the invoker having to remember to ask for it, so decide this every time — not only when someone thinks to mention an issue:

   - **Find a candidate.** A reference supplied by the invoker wins over anything inferred; put it in its normal form with `tracker: ref <reference>`. Otherwise take the reference leading a branch of the `<prefix>/<N>-<slug>` shape `/gaffer:build` produces, with `tracker: branch-ref <branch>`, so `feature/248-pr-closing-keyword` yields `248`. Where `ref` does not recognise the reference, or `branch-ref` yields none, there is **no candidate**: `feature/build-command` has no reference, and `branch-ref` never takes a number from inside a word, so `feature/net10-upgrade` does not yield `10`. Use the candidate as `<N>` in every check and message below.
   - **A candidate is only ever a candidate.** However it arrived — typed by the invoker or parsed from the branch — it is unverified until the tracker confirms it. The invoker's reference wins the *sourcing*, never the *checking*: a hand-typed digit is if anything easier to get wrong than a parse, so `/gaffer:raise-pr 247` (a PR number) and `/gaffer:raise-pr 24` (a slip for `248`) must not sail through.
   - **Verify it** with `tracker: pr-reference <N>`, which yields one of three outcomes. It is where the checks live that make a closing line safe: that the candidate is an open issue of this repository, and not a pull request, a closed issue or an issue that lives elsewhere.
   - **Report one of three outcomes — never fold the last two together.**
     - **Linked** — an open issue of this repository, with its title and the line that closes it on merge. Put that line, exactly as given, on its own line in **Related**.
     - **No issue** — the lookup settled the question, and says what disqualified the candidate (a pull request, a closed issue, another repository's issue, nothing at that number). Add no closing line. Where the outcome carries a line that only refers to the issue — a real but closed issue in *this* repository — still record that line in **Related**: dropping the closing line is the safety property, dropping every trace of the link is collateral damage.
     - **Unverified** — the lookup could not answer at all: expired auth, no network, rate limit, the tracker's tool missing. Add no closing line, and say the check could not run, quoting what the lookup reported. Reporting a fixable auth failure as "no such issue" sends the invoker looking in the wrong place.
   - A failed lookup here is **not** a stop-on-failure condition for the calling chain — it is an abstain, reported rather than fatal. Compose the rest of the body and carry on.
   - **An abstain is no longer free, and the report must say so.** Where the repository gates pull requests on an issue link (`CONVENTIONS.md` → *Pull requests* names the check), both outcomes above raise a PR whose check reports **red**. Still abstain rather than guess — a wrong closing line is worse than an absent one — but name the red check in the step 7 report so the invoker knows an edit is owed. Such a check re-runs when the body is edited, so fixing it needs no new push.
   - What this proves is bounded, and worth knowing: that `<N>` is an open issue in this repo, never that it is *this branch's* issue, and it can change state between here and merge. Restricting inference to the `/gaffer:build` shape is what keeps that gap narrow.
   - The PR body is the *only* place a closing line belongs, and the only one it carries is the line `pr-reference` gave — never a commit message, which would close the issue as soon as it reached `main`, ahead of review.
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
   - **Related** — the line settled above, as step 4's lookup gave it, whether it closes the issue or only refers to it — plus links to prior PRs or related issues that give context. This section always survives when step 4 settled a line, whatever the PR's size.

   A tiny PR may collapse to two sections. A sprawling PR may use all five. Match the size of the body to the size of the change.

5. **Push branch**: Run `git push -u origin <branch>`.

6. **Create PR**: Write the body from step 4 to a git-ignored scratch file (`CONVENTIONS.md` → *Scratch files* names it) with the native `Write` tool, never a shell heredoc, then run `gh pr create --repo <R> --head <branch> --title "<inferred title>" --body-file <scratch file>` with the title from step 3, adding `--draft` when the invocation carried it. `<R>` is origin's repository under its current name, the one step 4's lookup checked the issue on: the `owner/repo` of `git remote get-url origin`, resolved with `gh repo view <owner/repo> --json nameWithOwner --jq .nameWithOwner`. Left to choose, `gh` opens the pull request on the upstream of a fork clone, where the closing line would close an unrelated issue. Passing the body as a file keeps the backticks and `$` in it out of the shell, where a double-quoted `--body` or an unquoted heredoc would expand them. Capture the PR URL from the output.

7. **Output result**: First say whether the pull request was opened as a draft, then print step 4's outcome in whichever of its three forms applies — `<line> — <issue title>`, with the closing line as the lookup gave it; `No closing line: <reason>` (the branch carries no issue reference; `#<N>` is a pull request; `#<N>` is closed); or `Closing line unverified: <reason>` — so the invoker can see from the output alone what merging this PR will close, if anything. Then give the title, and say whether it was written in the form `CONVENTIONS.md` → *Pull requests* names or by the default rule. Where the form requires an issue key and step 3 left it out, say why, and name the check that enforces the form as one that will report red, so the invoker knows a retitle is owed. Where the form names no check, say the title lacks the key the form requires.

    **Then close the report with the verdict as its last line** — one JSON object on one line, at column 1, nothing else on that line and nothing after it. Exactly one of:

    - `{"schema": 1, "outcome": "raised", "pr": "<url>"}` — naming the pull request this run opened, and only for a pull request this run actually opened.
    - `{"schema": 1, "outcome": "failed", "reason": "<short reason>"}` — if no PR was opened, for any reason. Never the `raised` verdict then, even when the report above quotes the URL of a PR that already exists.

    The schema — its fields, what each outcome carries, and how it is read — is [`docs/verdict-schema.md`](../docs/verdict-schema.md) in the plugin (`${CLAUDE_PLUGIN_ROOT}/docs/verdict-schema.md`). That object is the machine-readable verdict: whatever drives the chain reads only what ends the report, so anything written after it — a next-steps note — costs the run its verdict *after* a real pull request is already open, which is the worst moment to lose it; a code fence around the verdict is tolerated, a sentence after the fence is not. A URL in the prose above is deliberately not enough, because the commonest failure here — a PR already open for this branch — reports an error whose text contains a perfectly good PR URL; the chain reads the `pr` field and nothing else. Two limits apply, and both cost the verdict at that same worst moment: **the URL must be bare**, so write `"pr": "https://github.com/o/r/pull/9"` and not a markdown autolink (`<…>`) or link (`[…](…)`); and **nothing else may share the line**, so a parenthetical such as `{…} (draft, CI red)` is read as no verdict at all.
