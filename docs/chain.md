# The chain

Two scripts under [`chain/`](../chain/) take an issue from a clean `main` to an open pull request with nobody watching: `chain.sh` runs the three build stages for one named issue, and `chain-next.sh` picks the next ready issue and runs the chain against it from a timer. They are run from a checkout of this repository, not from the installed plugin: each loads the stage commands from the checkout it sits in, so the script reading a verdict and the command writing it always come from one commit.

## `chain.sh` — one issue

```bash
bash /path/to/gaffer-claude/chain/chain.sh [--dry-run] [--skip-permissions] [--settings <file>] <issue>
```

From the root of the repository, on a clean `main`. It runs `/gaffer:build <issue>`, `/gaffer:verify` and `/gaffer:raise-pr <issue>` as three headless `claude -p` sessions, starting each only on the previous one's success verdict, read by position as [`verdict-schema.md`](verdict-schema.md) describes. The first stage that fails — a failure verdict, a verdict it cannot read, an agent error, a non-zero exit or a stall past its time limit — stops the run, and the closing line names the stage, its position and the reason: `chain: FAILED at [2/3] verify — suite red`, followed by the `claude --resume <id>` that reopens that stage. Before that it prints what the branch holds over `main` and whether the tree is dirty, which is the state to read before continuing by hand. A stage the account's Claude usage limit cut off exits 75 and quotes the limit's own reset wording; a settings file or checkout the chain cannot use exits 78, so a runner does not blame the issue for either.

The chain never resets, cleans, checks out, pushes or writes a file: the branch and tree are exactly as the last stage left them. `--dry-run` lists what would run and touches nothing, git included. Time limits are 2h for build and verify and 30m for raise-pr; `CHAIN_STAGE_TIMEOUT=<seconds>` overrides all three and `CHAIN_MODEL=<model>` overrides every stage's model, for a one-off run.

It needs `git`, `claude`, `gh`, `jq` and `timeout` on the path, with `claude` and `gh` signed in. `timeout` is GNU coreutils; on macOS, install coreutils.

## The settings file

Both scripts read one JSON file in the repository they run for, conventionally `.gaffer/chain.json`, committed so a change to it is reviewed. Everything in it has a default except the two things that make the runner safe to leave alone:

```json
{
  "clone": "~/Repos/my-repo-runner",
  "writers": ["User:octocat", "Bot:claude"],
  "labels": { "ready": "ready", "parked": "parked" },
  "stages": {
    "build": { "model": "opus", "effort": "high" },
    "verify": { "model": "opus", "effort": "high" },
    "raise-pr": { "model": "opus", "effort": "medium" }
  },
  "skip_permissions": false,
  "state_dir": "~/.local/state/gaffer-chain/my-repo-runner"
}
```

| Key | Read by | Default | Meaning |
|---|---|---|---|
| `clone` | runner | none — required | The runner's dedicated clone of the repository, where the destructive reset runs. `~/` is the user's home. |
| `writers` | runner | none — required | The accounts whose issues may be built, as `<Type>:<login>` the way GitHub's GraphQL names them. An issue raised or commented on by anyone else is skipped. With none named, no issue is ever built, which is what keeps a runner on a public repository from building a stranger's issue. |
| `labels.ready`, `labels.parked` | runner | `ready`, `parked` | The opt-in label the runner selects on, and the one it applies when a run fails. `ready` is what `/gaffer:confirmissue` applies, so the default queues every confirmed issue; name another to confirm and queue separately. |
| `stages.<stage>.model`, `.effort` | chain | `opus` and `high` for build and verify, `opus` and `medium` for raise-pr | Each stage's model and reasoning effort. A command run by hand keeps the session's model; these bind only the chain. |
| `skip_permissions` | runner | `false` | Whether the runner passes `--skip-permissions` to the chain. See *Permissions*. |
| `state_dir` | runner | `$XDG_STATE_HOME/gaffer-chain/<clone name>`, or `~/.local/state/…` | Where the runner keeps its lock and `logs/`, outside the clone. Per clone, so two repositories on one machine never share a lock or mix logs. |

`chain.sh` reads only `stages`, from `.gaffer/chain.json` in the current directory when it exists or from `--settings <file>`; without either it runs on the defaults. `chain-next.sh` is handed the file and refuses it when a required key is missing, a value has the wrong shape, or a key is one it does not know — a misspelt key would otherwise be a silently applied default.

## `chain-next.sh` — the runner

```bash
bash /path/to/gaffer-claude/chain/chain-next.sh [--dry-run] <settings-file>
```

One firing. It picks the lowest-numbered open issue carrying the ready label that is not parked, has no open pull request linked to it (by `Closes` or by a `feature/<N>-` branch), has no open blocking issue in GitHub's issue dependencies, and has been written on by nobody outside `writers` — a comment counts even after it is deleted. Then it resets the dedicated clone to the latest `origin/main` (`checkout -f`, `clean -fdx`, local branches whose upstream is gone deleted), sets aside any `feature/<N>-*` branch an earlier attempt left as `attempt/<N>-<stamp>`, and runs `chain.sh` there, logging to `logs/<N>-<stamp>.log` in the state directory. On success the issue has an open pull request. On failure the issue is labelled parked with a comment naming the failed stage, the reason, the log, the kept attempt branch and any branch that was pushed without a pull request; removing the label has the next firing build it again from scratch. A usage-limit stop is parked too, with a comment saying nothing on the issue needs looking at. `--dry-run` names the issue the next firing would build and changes nothing.

The runner never merges, never pushes and never deletes anything on GitHub; only the chain's last stage pushes. It changes nothing when nothing is eligible, when another firing holds the lock, or when a GitHub query fails — every query fails closed, selecting nothing rather than guessing. A fault in its own setup — the settings, the plugin checkout, the clone, a missing tool — is refused before anything is selected, so no issue is parked for it. The lock is `flock(1)`, from util-linux: Linux has it, macOS needs it installed, and a scheduler that never overlaps its own runs needs nothing from it.

**Which plugin runs.** The runner refuses to run from a checkout that is not plainly this repository's `main`: on another branch, with uncommitted or untracked files, or with local commits `origin/main` does not have. It never updates the checkout itself; the scheduler does, in the step before the firing, so the run that follows is a known commit, printed in the runner's output as `gaffer at <sha>`.

## Permissions

By default every stage runs under the repository's own permission rules, and a headless session denies anything they do not allow — silently, so a stage can carry on degraded and still report success ([`unattended.md`](unattended.md)). Most repositories' rules do not allow a build, so an unattended runner will want `skip_permissions: true` (or `--skip-permissions` on the chain), which runs every stage with `--dangerously-skip-permissions`: nothing is refused, including a write to any path the user can reach or a command that leaves the clone. Opt in only where that is contained: a clone used by nothing else, a machine or account set aside for the runner — a container or a VM is the right unit — credentials that reach only what the chain must push and comment on, and `writers` naming only accounts you trust to write an issue the chain will build unread. The runner reads the opt-in from the settings file, which is read from the clone's `main` and so changes only by a reviewed pull request.

## Setting it up

1. Clone the repository for the runner alone, as a full clone rather than a worktree, mark it, and give it a git identity if the user has none:

   ```bash
   git clone https://github.com/<owner>/<repo>.git ~/Repos/<repo>-runner
   git -C ~/Repos/<repo>-runner config chain-next.dedicated true
   ```

2. Clone this repository beside it, on `main`. Nobody edits it; the scheduler fast-forwards it before each firing.

   ```bash
   git clone https://github.com/FrankRay78/gaffer-claude.git ~/Repos/gaffer-runner
   ```

3. Commit the settings file to the repository, with `clone` and `writers` at least, and create the labels once — `ready` already exists where the issue stage has run:

   ```bash
   gh label create parked --description "The chain runner stopped on this issue; remove to retry"
   ```

4. Check what the first firing would do. This reads GitHub, confirms both clones are where the runner expects, and changes nothing:

   ```bash
   bash ~/Repos/gaffer-runner/chain/chain-next.sh --dry-run ~/Repos/<repo>-runner/.gaffer/chain.json
   ```

5. Schedule it. The plugin ships no unit; this is the shape, as a systemd user timer with lingering enabled so it survives logout. A user unit starts with a minimal environment, so `PATH` names where `claude`, `gh`, `jq`, `git`, `flock`, `timeout` and the repository's build tools live. The update step is the scheduler's, which is why it is here and not in the runner.

   ```ini
   [Service]
   Type=oneshot
   Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
   ExecStartPre=/usr/bin/git -C %h/Repos/gaffer-runner pull -q --ff-only
   ExecStart=/bin/bash %h/Repos/gaffer-runner/chain/chain-next.sh %h/Repos/<repo>-runner/.gaffer/chain.json
   TimeoutStartSec=infinity
   ```

   with a timer of `OnCalendar=*:0/15`. A firing while a run is in progress does nothing: systemd does not start an active service twice, and the lock covers a run started by hand.

To retry a parked issue, remove the label. To finish a parked attempt instead of rebuilding it, fetch its `attempt/<N>-<stamp>` branch from the runner's clone into a checkout of your own, rebase it onto `main`, and run the stages the chain did not finish by hand — leaving `parked` on until the pull request is open, or the next firing rebuilds the issue beside it.

## Tests

`bash chain/chain.tests.sh` and `bash chain/chain-next.tests.sh`, both run by CI. They use a stub `claude`, a stub `gh` and throwaway repositories under a temp directory, so no model is called, nothing reaches GitHub and your checkout is untouched. The chain matrix is the specification of how a verdict is read; the runner matrix, of what is selected and what a failure leaves behind.
