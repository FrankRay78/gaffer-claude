---
description: Set a repository up for gaffer from what it already contains — the settings, git-ignore line, imports and labels the commands assume, plus a CONVENTIONS.md and REVIEW.md that point at the repository's own files — delivered as a pull request of recommendations to edit or discard. Re-run on a repository already set up, it reports only what is missing.
---

Read `CLAUDE.md` for project context, if there is one, and the conventions as *Repository conventions* below says, before proceeding.

## User Input

```text
$ARGUMENTS
```

Nothing is expected. `/gaffer:init` takes no argument and asks the invoker nothing: it runs from start to finish, and the pull request it raises is where the user reviews, edits or discards what it did.

## Repository conventions

The steps in this file are generic. The conventions they run on live in two files, read section by section: the plugin's defaults in `${CLAUDE_PLUGIN_ROOT}/defaults/CONVENTIONS.md`, and the repository's own `CONVENTIONS.md` at the root of the repository this command runs in, if it has one, written as additions to the defaults. Each step applies its own rule together with the two sections under the matching heading — the default first, then the repository's, which wins where they conflict, and stands alone where its first line is `Replaces the default.`. Wherever this file says `CONVENTIONS.md` → *Heading*, it means those two sections read that way. The headings this command reads:

| Heading | Supplies |
|---|---|
| `Scratch files` | the git-ignored file step 6 writes the pull request body to |

## What it writes, and what it never does

- **It writes what it can point at.** Every line it adds to `CONVENTIONS.md` or `REVIEW.md` names a file that is tracked in the repository — a CI workflow, a script, a guide, a config file. A heading it has nothing to point at for is left out, so the plugin's default applies.
- **It copies only command lines.** Under *Build, test and format* it copies the build, test and format commands **word for word** from the file that runs them, citing that file, because `/gaffer:build` and `/gaffer:verify` stop without a command and a pointer would not supply one. Where the build and the tests are separate lines in that file, join them with ` && ` in the order the file runs them. Everywhere else it writes pointers, not copies.
- **It states no principle, policy or decision** the repository's files do not already record: not a versioning stance, not whether to keep change-intent records, not a risk tier, not a severity. If the repository records one — a `CODEOWNERS` file, a decisions directory with its own README — the line points at it and says only what that file says.
- **It never rewrites.** Text already in `CONVENTIONS.md`, `REVIEW.md`, `CLAUDE.md`, `.gitignore` or `.claude/settings.json` stays byte for byte; a heading the repository already has is never touched, even where the repository has more to say under it. What it adds goes after what is there.
- **It writes no project overview.** `CLAUDE.md` gains import lines only; describing the project is Claude Code's own `/init`.

## Steps

The plugin's own files are read from `${CLAUDE_PLUGIN_ROOT}`: the setup script `init/setup.sh`, the templates under `templates/`, the defaults under `defaults/`. Run the script with `bash`, never by its executable bit.

1. **Check the repository is ready.** From the repository root:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/init/setup.sh" check
   ```

   It prints `ready: <default branch>` or `not ready: <reason>`. On `not ready` — uncommitted changes, not on the default branch, no GitHub repository behind the remote, `gh` not signed in — **stop before changing anything**, and report the reason and what to do about it. Running from somewhere other than the repository root is the same stop.

2. **Branch.** Create `gaffer/init-<UTC timestamp, YYYYMMDD-HHMMSS>` from the default branch. Every run gets its own branch and its own pull request, even while an earlier init pull request is still open: the repository may have changed since, and the user may want to compare the two.

3. **Read the headings and what the repository already has.**
   - The heading list is the `## ` headings of `${CLAUDE_PLUGIN_ROOT}/templates/CONVENTIONS.md` and `${CLAUDE_PLUGIN_ROOT}/templates/REVIEW.md`, in their order. Read the template's placeholder under each heading, and the matching section of the plugin's defaults, for what the heading carries.
   - Read the repository's own `CONVENTIONS.md` and `REVIEW.md` at the root, if they exist. A heading present in either already is **already present**, and nothing more happens to it.

4. **Look for what the repository already records.** For each heading not already present, look at the tracked files (`git ls-files`) for something that answers it. Read a candidate before citing it: a file is cited for what it actually says, not for its name. Where to look, as a starting point rather than a limit:

   | Heading | Look for |
   |---|---|
   | *Build, test and format* | CI workflows, `Makefile`, `package.json` scripts, `justfile`, build scripts, a contributing guide's build section — the commands themselves, copied as above |
   | *Testing* | test directories or projects and their naming pattern, a testing guide |
   | *Acceptance criteria* | a traceability or acceptance check script, a contributing guide's section on criteria |
   | *Code quality* | linter and formatter configs (`.editorconfig`, analyzer or lint configs), a style guide |
   | *Dependencies* | the dependency manifests, `dependabot.yml` or `renovate.json`, a dependency or licence policy document |
   | *Public API and breaking changes* | a published package manifest, an API or versioning document, a changelog policy |
   | *Commit messages* | a commit-message config or hook, a contributing guide's commit section |
   | *Documentation* | user guides, API docs, release documents, and the kind of change each describes |
   | *Change-intent records* | a decisions or ADR directory and any convention file that governs it |
   | *Pull requests* | PR templates, workflows that check a PR's body or links |
   | *Issue sources* | issue templates, a backlog document |
   | *Hooks, scripts and plugins* | hooks in `.claude/settings.json`, `.claude/hooks/`, a scripts directory, other enabled plugins |
   | *Where it runs* | a workflow that runs `/gaffer:review-pr` or `/gaffer:review-followup` |
   | *What not to flag* | the checks CI already gates, by workflow |
   | *Always a person* | `CODEOWNERS` |
   | *Contracts* | CLI reference, API reference, output-format documents |
   | *Context to load* | architecture and convention guides, and the layer each covers |
   | *Change map* | the top-level directories that group the code |
   | *Tests* | a testing guide |

   Headings such as *Severity*, *Risk tier*, *Test-driven development*, *Issue concerns*, *Issue review checks* and *Audit* are mostly decisions: fill one only where a tracked file already states it.

5. **Write the files.**
   - **A file that does not exist yet** starts with the template's title and opening paragraph, copied from `${CLAUDE_PLUGIN_ROOT}/templates/`, then the filled headings in template order. Write the file only if at least one heading was filled.
   - **A file that exists** gains the filled headings appended at its end, in template order, after a blank line.
   - Under each heading, one bullet per thing found: what it is, then the file as a relative markdown link — e.g. ``- **Testing guide** — [`docs/testing.md`](docs/testing.md).`` A copied command keeps its own code span and is followed by its source.
   - Then run the setup, which must come after `CONVENTIONS.md` is written, since it imports that file into `CLAUDE.md` only once it exists, and then the labels:

     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/init/setup.sh" files
     bash "${CLAUDE_PLUGIN_ROOT}/init/setup.sh" labels
     ```

     Each prints one `added:` or `present:` line per item (`files` also prints `skipped:` for the `CONVENTIONS.md` import when there is no such file). Keep both outputs for the body. A non-zero exit from either is a stop: report its error, leave the branch as it is for the user to inspect, and raise nothing.

6. **Raise the pull request, or report that nothing is missing.**
   - **Nothing changed** — `git status --porcelain` is empty: switch back to the default branch, delete the init branch, raise nothing, and report that the repository is already set up. Say whether `labels` created any label, since that happens outside any pull request.
   - **Otherwise**: `git add -A`, commit as `Set up gaffer: conventions, review criteria and settings`, push with `-u`, and open a pull request against the default branch titled `Set up gaffer`. Write the body to the scratch file `CONVENTIONS.md` → *Scratch files* names (`init-pr-body.md` by default) with the `Write` tool and pass it with `--body-file`. The body is:

     ```markdown
     Recommendations from `/gaffer:init`, read from what this repository already contains. Edit anything on this branch before merging, or close the pull request to discard it. A heading marked *nothing found* runs on the plugin's default until you write a section for it.

     ## CONVENTIONS.md

     | Heading | Outcome |
     |---|---|
     | Build, test and format | filled from `<file>`, `<file>` |
     | Test-driven development | nothing found, default applies |
     | … | already present |

     ## REVIEW.md

     | Heading | Outcome |
     |---|---|
     | … | … |

     ## Setup

     - <each `added:` line from `files`, in plain words>

     ## Labels

     - <each label created, or "All present already.">
     ```

     Every heading of both templates gets a row, in template order, with exactly one of: *filled from* and the files cited, *already present*, or *nothing found, default applies*. Write a `|` in a cell as `\|`. Setup items that were already present are left out of *Setup*; if all were, write "All present already."
   - Then switch back to the default branch, so the next run starts where this one did.

## Output to the user

Keep it short:

- the pull request URL — or that nothing was missing, or the `not ready` reason and what to do
- how many headings were filled, already present and left to the default, per file
- the setup items and labels added
- a reminder to check the copied build-and-test command in particular, since `/gaffer:build` will run it as written

## When NOT to use this command

- The repository is not on GitHub — the command needs a pull request to deliver its recommendations.
- To check existing conventions for staleness rather than gaps — that is `/gaffer:context-gardening`, or lens 4 of `/gaffer:audit-codebase`.
