# Troubleshooting

The failures that come up, what each means, and what to do. The chain and runner messages quoted here are the ones a reader that follows [`verdict-schema.md`](verdict-schema.md) reports; a repository's own chain may word them differently.

## The `/gaffer:` commands are not offered

The plugin is not installed, or is installed and not enabled for this repository.

- `claude plugin list` should name `gaffer@gaffer-claude`. If it does not: `claude plugin marketplace add FrankRay78/gaffer-claude` then `claude plugin install gaffer@gaffer-claude`.
- The repository's `.claude/settings.json` should carry the marketplace under `extraKnownMarketplaces` and `"gaffer@gaffer-claude": true` under `enabledPlugins`. That enables the plugin for the repository and, once the project is trusted, fetches the marketplace; it does not install the plugin, so the `claude plugin install` above is still needed once per machine. A project not yet trusted, or a machine with no route to GitHub, gets no commands either. `/plugin` names the case: "enabled in project settings but isn't installed here".
- A checkout can stand in for an installed copy for one session: `claude --plugin-dir /path/to/gaffer-claude`.

## `conventions missing: Build, test and format`

`/gaffer:build` or `/gaffer:verify` stopped because no build-and-test command is stated. It is the one convention with no default, because inventing one unattended is how a run reports green over nothing. Add a *Build, test and format* section to the repository's `CONVENTIONS.md` naming the command, as [`getting-started.md`](getting-started.md) step 5 shows.

## `no readable verdict — …`

A chain stopped because the stage's report did not end on one JSON verdict. The text after the dash says what was wrong: the report does not end with a JSON verdict, carries no schema version, names no outcome, names an outcome that is not this stage's success or `failed`, a success verdict also carries a reason, or the payload is missing.

The commonest cause is a closing sentence after the verdict, or a verdict inside a fence that does not close the report. Reopen the stage's session with the `claude --resume <id>` the chain's closing line gives and read the end of the report. The stage may well have succeeded; what failed is how it reported. The rule the three commands follow is in [`verdict-schema.md`](verdict-schema.md): the verdict is the last thing in the report, bare on one line, and a fence around it is tolerated while a sentence after it is not.

## `the verdict has schema version <v>, which this chain does not read`

The plugin's commands write a newer verdict than the repository's chain reads. Teach the chain the new version before updating the plugin; the schema's *Changing the schema* section says what a version bump means.

## A stage `stalled`, was `killed`, or `claude exited with <code>`

- **Stalled** — the stage ran past its time limit. Reopen the session and see where it was; a verify stage over a large branch, or a build whose suite is slow, may need a longer limit, which is the chain's setting, not the plugin's.
- **Killed before its limit** — something outside the chain ended the process, an out-of-memory kill being the usual case. Look at the machine, not the stage.
- **`claude reported an error`** or a non-zero exit — the reply names the error. The account's usage limit is the one a chain tells apart from the rest; a repository's chain reports it with the reset time and may exit with a code of its own so a runner does not park the issue for it.

## A parked issue

An unattended runner parks an issue — adds the `parked` label and comments — when the chain failed on it. The comment names the stage and the reason from the chain's closing line, the log, and the kept `attempt/<N>-<timestamp>` branch in the runner's clone. Nothing is retried on its own: removing the label is the retry, and it builds the issue again from scratch. To finish the attempt instead, fetch the kept branch into a checkout of your own, rebase it onto `main`, and run the stages the chain did not finish by hand, in order. If the comment says the Claude usage limit was reached, nothing on the issue needs looking at: remove the label once the limit has reset.

## `/gaffer:build` stops without starting

It checks its starting point before branching, and each reason is its own line: the tree is not clean, `main` is not checked out, local `main` has commits the remote does not, the issue is closed or already has an open pull request, the issue's branch already exists with commits it has not inspected, or the issue needs a new dependency in a library the repository has marked as dependency-controlled. Each is deliberate: the stage never resets, stashes or deletes anything to clear its own way.

## A reviewer subagent could not be found

`/gaffer:verify` spawns its reviewers by their `pr-review-toolkit:` names. Install that plugin: `claude plugin install pr-review-toolkit@claude-plugins-official`, and enable it in the repository's settings beside `gaffer`.

## `git`, `gh` or `jq` not found; `gh` not signed in

Every command that touches GitHub calls `gh` and parses with `jq`, and a chain checks for them before spending model time. Install the missing tool and, for `gh`, sign in (`gh auth login`) in the account the repository's remote accepts. A scheduled runner starts with a minimal environment, so its `PATH` must name where each tool lives.

## A read was denied outside the working directory

The defaults the commands read live in the plugin's install directory, outside the repository. A headless `claude -p` run that is not bypassing permissions denies that read and the command stops with a failure verdict saying so. Pass `--add-dir <plugin directory>` to the headless run, as [`ci.md`](ci.md) does, or run interactively and accept the one prompt.

## The hook refused a `chmod`

The `no-chmod` hook refused a `chmod` that would have set the executable bit, because `Bash(chmod:*)` is an `ask` rule that stalls an interactive run and is denied silently in a headless one. Run the script as `bash script.sh`, which needs no bit, or record the bit on a committed file with `git add --chmod=+x <path>`. `GAFFER_ALLOW_CHMOD=1` bypasses the hook for one call and says so on stderr; the `ask` rule still applies behind it.

## A CI review ran green but posted nothing

The action exits successfully whenever the model finishes its turn. The workflow's own post-condition step is what turns a non-posting run red; if the workflow has none, add one as [`ci.md`](ci.md) step 6 describes. Read the run log for the tool call that was refused: the usual causes are a `gh` subcommand missing from `--allowedTools`, or a scratch path under `.claude/` that a headless run will not write to.

## A command behaved wrongly for this repository

If the repository's `CONVENTIONS.md` or `REVIEW.md` has a section under the right heading and the command still misread it, or if the generic rule is wrong, raise an issue on this repository with the command, the input and what it did. Until the fix lands, a repository-side section under the matching heading is the workaround, since the repository's file wins. Never edit an installed copy of the plugin: the next marketplace update overwrites it.
