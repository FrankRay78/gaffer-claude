---
description: Turn an idea, a document, a backlog item or an existing issue into a needs-first GitHub issue, and raise it, ready for /gaffer:reviewissue and then /gaffer:build.
argument-hint: "[idea | document path | issue URL | backlog <number>]"
---

# draftissue

Turn an idea, a document or an existing issue into a needs-first GitHub issue, and raise it, ready for `/gaffer:reviewissue` and then `/gaffer:build`.

---

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` names the source of the issue. It is one of:

- **A free-text idea** — a sentence, a paragraph or rough bullets describing what the user wants.
- **An existing issue** — an issue reference the repository's tracker recognises (on GitHub, `#N`, a bare number, or an issue URL). This is a **migration**: the old issue is the raw material, and Step 5 offers to close it once the new one exists.
- **A document** — a URL or a repository path, optionally narrowed to one part of it ("the 'Offline mode' section of docs/ideas.md").
- **A backlog item** — `backlog <number>` or `item <number>`. `CONVENTIONS.md` → *Issue sources* names the backlog it refers to. If that section lists none, ask the user where the backlog is; do not guess.

The argument may add guidance alongside the source ("item 12, but leave CSV out"). That guidance outranks the source.

If `$ARGUMENTS` is empty, ask the user for the source. Do not invent one.

**Every tracker call goes through the tracker interface**, `bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh <operation> …`, never a tracker's own CLI or API: the repository's settings choose the tracker, and [`docs/tracker.md`](../docs/tracker.md) is the contract — each operation's arguments, its JSON output and its exit codes. Write the script's path unquoted, as shown, so the allow rule `/gaffer:init` writes matches it. Put a reference the user typed in single quotes, as shown: unquoted, a leading `#` starts a shell comment and the reference is lost. Tell an existing issue from free text with `bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh ref '<argument>'`: exit 0 means it is an issue reference, and prints the `<ref>` every later call uses.

---

## Repository conventions

The workflow in this file is generic. The conventions it runs on — where the backlog lives, which concerns the repository's issues must settle, how it labels scenarios, where it keeps scratch files — live in two files, read section by section: the plugin's defaults in `${CLAUDE_PLUGIN_ROOT}/defaults/CONVENTIONS.md`, and the repository's own `CONVENTIONS.md` at the root of the repository this command runs in, written as additions to the defaults. Read both with the source; each step then applies its own rule together with the two sections under the matching heading — the default first, then the repository's, which wins where they conflict, and stands alone where its first line is `Replaces the default.`. Wherever this file says `CONVENTIONS.md` → *Heading*, it means those two sections read that way. The headings this command reads:

| Heading | Supplies |
|---|---|
| `Issue sources` | the backlog a `backlog <number>` or `item <number>` argument refers to, how step 1 reads it, and how Related links it |
| `Issue concerns` | what step 3 considers beyond the generic categories |
| `Acceptance criteria` | the drafting conventions step 4 applies, such as scenario labels |
| `Scratch files` | the git-ignored file step 4 writes the body to |

A section under any other heading is read too, and applied where its text says. Where neither file has a heading, the step concerned runs on its generic rule alone, and the report to the user names each heading found in neither. A step whose convention is the thing itself — the file to write, the label to apply — has no generic rule and no default, so where the repository supplies none the command stops and names the heading rather than invent one. The repository's `CONVENTIONS.md` is read from the root of the repository this command runs in, and trusted as this command file is.

---

## Purpose

First stage of the issue chain: `/gaffer:draftissue` → `/gaffer:reviewissue` → `/gaffer:confirmissue` → `/gaffer:build`.

Job: state **what is needed and how anyone can tell it is done** — the user, their job, the scenarios, the scope edges and the acceptance criteria. Not how to build it. Each later stage owns the rest:

- `/gaffer:reviewissue` reads the codebase and surfaces the requirement and technical gaps the issue leaves open; the author answers them.
- `/gaffer:confirmissue` folds those answers into the issue as confirmed decisions.
- `/gaffer:build` makes the remaining technical calls itself, consistent with the codebase, and reports its assumptions.

So this command asks no technical questions and writes no technical design. A technical choice made here arrives at `/gaffer:build` looking settled although nobody reviewed it.

It raises the issue without a draft-approval pause. `/gaffer:reviewissue` and `/gaffer:confirmissue` are the human checkpoint before anything is built.

---

## Workflow

### 1. Read the source

- **Free text** — the argument is the whole source.
- **Existing issue** — `bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh view <ref>`, which prints the issue's `title`, `body` and `comments` as JSON. Use the body, any comment carrying the review marker (`bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh marker review` prints it; on GitHub `<!-- speckit:review -->`), and any `## Confirmed decisions` section as raw material. An old issue often mixes requirements with technical design: draft from the requirements, and treat its technical content like any source's hints. Tell the user which issues were ingested.
- **Document** — read it: `gh` or `git` for a GitHub-hosted page (a wiki is a git repository), the file itself for a path, a fetch otherwise. Narrow to the part the argument names.
- **Backlog item** — read the item as `CONVENTIONS.md` → *Issue sources* describes, together with whatever the backlog says about it elsewhere: the items it depends on, notes or open questions that name it, and anything listed as rejected or already done next to it.

Keep track of where each fact came from — the Related section links the source.

### 2. Check the source against today

Sources age: a backlog row or an old issue may describe behaviour that has since changed. Check each claim the source makes about **how things work today** against the code, with targeted reads and searches — not a survey of the codebase, which `/gaffer:reviewissue` does next.

- If the capability already exists, **stop** and tell the user what you found. Do not raise an issue.
- If a claim is stale, write the issue from what is true now, and say in the final report which claim you corrected.
- If the source says the work depends on something not yet built, say so in Source notes. Do not stop: whether to build it first is the author's call at review.

### 3. Ask only what the source leaves open

Find the **requirements** decisions the source does not settle — the points where a builder would otherwise have to invent the answer, and the answer changes what the user gets. Consider:

- **User** — who uses this, in what context.
- **Job** — the task they are doing, and what "done" looks like from where they sit.
- **Scenarios** — the 1–3 flows the feature must support, as a user action and the observable response; edge cases the user will meet.
- **Scope edges** — what is deliberately out.
- **Behaviour at the edges** — matching rules, empty and boundary cases, what the user sees.
- **Failure** — what the user sees when something it relies on is missing, slow or refuses them.
- Anything `CONVENTIONS.md` → *Issue concerns* lists.

These are things to consider, not questions to fill. A category the source settles produces no question. A thorough source can produce none at all — then draft without asking. A one-line idea may need several.

Do not ask about where code lives, integration, data shape, libraries, field names or architecture. Those are `/gaffer:reviewissue`'s gaps and `/gaffer:build`'s calls.

**Explore before you ask.** Some decisions are a pick between options the user already understands. Others need research first — how comparable tools behave, what the project's own rules imply, what each option costs the user and what it unlocks. Do that work before raising the decision, to the depth the decision needs: read inline where a few lookups will settle it, and hand the research to a sub-agent only when it spans more sources than that. Find the decision underneath, too: asking whether a new value replaces an old one, before settling what the new value is, gets a question nobody can answer yet.

**Discuss, then confirm.** Raise a decision that needs judgement as a short written assessment, in plain words — what happens today, the realistic options, what each costs and unlocks, and your recommendation as an outcome or a scope call — and let the user reply in their own words. Use a multiple-choice prompt only to confirm a decision whose options are already clear to the user.

**When the user asks for help, stop offering options.** An answer that asks for advice, explanation or more thought ("please advise", "I need help", "we need to think about this") is a request for discussion. Reply in prose with the research and reasoning asked for, end with your recommendation, and wait for their answer — never another set of options. Where the user hands the choice back ("you decide"), take your recommendation.

### 4. Draft the body

Write the body to a git-ignored scratch file (`CONVENTIONS.md` → *Scratch files* names it) with the native `Write` tool; the file is the issue body verbatim. Write repository links as paths relative to the repository root, which is how GitHub resolves links in an issue. Put no H1 in the body; the title goes on the `--title` flag.

**Acceptance criteria** say what an outside observer can check, not how it is delivered. The test: would this criterion still hold under a different reasonable implementation of the same feature? If not, it describes the mechanism.

The line between outcome and mechanism is **who touches it**. Anything users, their scripts or other programs work with directly is part of the outcome, and a criterion may name it exactly — a command, option or flag name, a config key, a field in machine-readable output, an exit code, a file format users write, a library's public members, a network route that clients call. Changing one of those breaks someone, so it is a promise, not a detail. Everything behind it is mechanism and stays out — internal names and paths, data structures and storage, library and framework picks, algorithms, internal timings and polling cadences, log formats, and the exact wording of messages meant for people to read.

| Avoid (mechanism) | Prefer (outcome) |
|---|---|
| "Results are cached in a dictionary keyed by host" | "A second request for the same host in one run does not repeat the lookup" |
| "Failed calls retry with exponential backoff from 200 ms" | "A brief outage is retried before the user sees an error" |
| "The error reads 'Invalid value: expected a number'" | "The user is told the value was rejected and what a valid one looks like" |
| "Settings are written to a SQLite table" | "A changed setting is still in effect after a restart" |
| "Entries are sorted with a stable sort on the name field" | "Entries appear in alphabetical order" |

Contracts a criterion may name exactly:

- "`--format json` reports the duration as a number of seconds, not a string"
- "The command exits non-zero when any check fails"
- "A config file may list servers under a `servers` key"

Project housekeeping — a project exists, a solution file is updated, scaffolding is in place — is not an acceptance criterion. Leave it out; the builder does it on the way.

*Regression exception*: a criterion may pin a mechanism when it exists to prevent a named, previously fixed bug. Name the bug in the criterion.

Use this template. Drop any section with nothing to say, except Summary and Acceptance criteria.

```markdown
## Summary

One short paragraph: what the feature delivers and the outcome the user sees.

## Motivation

Why now, what is missing today, who needs it. Argue from the user's need and the source — what breaks for them, what they cannot do — not from file and line references.

## Users & jobs

Who uses this, in what context, and the task they are trying to get done. A short paragraph, or 2–4 bullets per user.

## Capability

What the feature does, seen from outside, and the 1–3 scenarios that exercise it, each as Given / When / Then. Short sub-sections as the feature needs.

## Out of scope

Deliberate scope decisions, each phrased as "X is not in this issue".

## Acceptance criteria

- [ ] A checklist of outcomes, each checkable by a user or an external test.

## Source notes (non-binding)

Pointers to technical hints from the source that a reviewer or builder would otherwise miss — an existing setting that already does part of the job, a known constraint, an unbuilt dependency, an open question the source records. One line each, saying where the detail lives rather than restating it. These are leads, not decisions: `/gaffer:reviewissue` raises any that matter, and `/gaffer:build` is free to choose otherwise.

## Related

- A link to the source, and to any project document it relies on.
```

Apply any drafting conventions `CONVENTIONS.md` → *Acceptance criteria* lists.

### 5. Raise the issue

Choose a short title naming the capability. First check the tracker can raise it, and for a migration close the source too:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh require create
```

Add `ref close` to that list for a migration. If it exits non-zero, stop here, keep the scratch file, and tell the user its path so they can post it by hand, passing on what the check printed — it names the setting and the operation at fault. Otherwise create the issue:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh create --title "<title>" --body-file <scratch-file>
```

It prints the new issue's `{ref, url}`; then delete the scratch file. If the create fails, stop here the same way, keeping the scratch file.

**Migration — supersede the source issue.** Once the new issue exists, ask the user before closing each source issue, even if the argument said to close it — they may want to read the new one first. Close each one they confirm, one at a time. Write the note `Superseded by <mention>` to a scratch file with the **Write tool**, where `<mention>` is the `mention` that `bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh ref --forms <new ref>` prints (on GitHub, `#<M>`), then:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tracker/tracker.sh close <ref> <note file>
```

The command never edits any other source: not a document, not a backlog.

### 6. Stop

Do not start implementation. The next step is `/gaffer:reviewissue` against the new issue, which the user runs.

---

## Output to the user

Keep it short:

- the new issue's URL
- each decision you asked about and the answer recorded, one line each — or that the source settled everything
- any claim from the source you found stale and corrected
- anything carried into Source notes, in a phrase each

Do not restate the issue in chat — the issue is now canonical.

---

## When NOT to use this command

- The user already has a structured issue body — raise it directly, or go straight to `/gaffer:reviewissue`.
- The change is a small bug fix — write the issue inline; this command's questions do not pay for themselves.
- The user wants it built now — that is `/gaffer:build`, once an issue exists.

---
