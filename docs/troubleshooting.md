# Troubleshooting

## The `/gaffer:` commands are not offered

`claude plugin list` should name `gaffer@gaffer-claude`; if not, run the two commands under *Installing* in the [README](../README.md). A repository's settings can enable the plugin but not install it, so each machine installs it once; `/plugin` then reports "enabled in project settings but isn't installed here". A project not yet trusted gets no commands either.

## `conventions missing: Build, test and format`

`/gaffer:build` or `/gaffer:verify` stopped because no build-and-test command is stated — the one convention with no default. Add the section to the repository's `CONVENTIONS.md`, as [`getting-started.md`](getting-started.md) step 5 shows.

## `/gaffer:build` stops without starting

It checks its starting point first: a clean tree, `main` checked out, no unpushed local commits, an open issue with no open PR, no leftover branch holding uninspected commits, and no new dependency in a library the repository marks as dependency-controlled. Its report names which failed. It never resets, stashes or deletes anything to clear its own way.

## A reviewer subagent could not be found

`/gaffer:verify` spawns its reviewers by their `pr-review-toolkit:` names: `claude plugin install pr-review-toolkit@claude-plugins-official`, and enable it beside `gaffer`.

## `git`, `gh` or `jq` not found; `gh` not signed in

Install the tool; for `gh`, `gh auth login` in the account the remote accepts. A scheduled job starts with a minimal `PATH`, so name where each tool lives.

## A read was denied outside the working directory

A headless run denied the read of the plugin's defaults. Pass `--add-dir <plugin directory>`, or run interactively and accept the prompt ([`unattended.md`](unattended.md)).

## The hook refused a `chmod`

Run the script as `bash script.sh`, or record the bit on a committed file with `git add --chmod=+x <path>`. `GAFFER_ALLOW_CHMOD=1` bypasses the hook for one call and says so; the repository's `ask` rule still applies behind it.

## A CI review ran green but posted nothing

The action exits green whenever the model finishes. Add the post-condition step ([`unattended.md`](unattended.md), *In CI*), then read the log for the refused tool call — usually a `gh` subcommand missing from `--allowedTools`, or a scratch path under `.claude/`.

## A command behaved wrongly for this repository

If the generic rule is wrong, or the command misread a section under the right heading, raise an issue here with the command, the input and what it did. Until the fix lands, a repository section under the matching heading is the workaround, since the repository's file wins. Never edit an installed copy: the next update overwrites it.
