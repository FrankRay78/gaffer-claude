# The chain

Two scripts under [`chain/`](../chain/) take an issue from a clean `main` to an open pull request with nobody watching: `chain.sh` runs the build stages for one named issue, and `chain-next.sh` picks the next ready issue and runs the chain against it from a timer. A third, `chain-local.sh`, is for running by hand where neither CI review nor a runner is set up: the chain for one issue, then `/gaffer:review-pr` on the pull request it opened. They are run from a checkout of this repository, not from the installed plugin: each loads the stage commands from the checkout it sits in, so the script reading a verdict and the command writing it always come from one commit.

## `chain.sh` — one issue

```bash
bash /path/to/gaffer-claude/chain/chain.sh [--dry-run] [--skip-permissions] [--settings <file>] <issue>
```

From the root of the repository, on a clean `main`. `<issue>` is the issue as the repository's tracker names it — on GitHub `270` or `#270`, an issue of this repository — and the chain reads nothing from it: it is handed to the stages as typed, and a reference the tracker does not recognise is stopped by the build stage's first read of the issue, before anything changes ([`tracker.md`](tracker.md)). It runs `/gaffer:build <issue>`, `/gaffer:verify`, `/gaffer:raise-pr --draft <issue>` and `/gaffer:pre-review` (below) as four headless `claude -p` sessions, starting each only on the previous one's success verdict, read by position as [`verdict-schema.md`](verdict-schema.md) describes. The first stage that fails — a failure verdict, a verdict it cannot read, an agent error, a non-zero exit or a stall past its time limit — stops the run, and the closing line names the stage, its position and the reason: `chain: FAILED at [2/4] verify — suite red`, followed by the `claude --resume <id>` that reopens that stage. Before that it prints what the branch holds over `main` and whether the tree is dirty, which is the state to read before continuing by hand. A stage the account's Claude usage limit cut off exits 75 and quotes the limit's own reset wording; a settings file or checkout the chain cannot use exits 78, so a runner does not blame the issue for either.

The chain never resets, cleans, checks out, pushes or writes a file: the branch and tree are exactly as the last stage left them. `--dry-run` lists what would run and touches nothing, git included; it still reads the settings file, and refuses one it cannot read as a real run would. Time limits are 2h for build, verify and pre-review and 30m for raise-pr; `CHAIN_STAGE_TIMEOUT=<seconds>` overrides them all and `CHAIN_MODEL=<model>` overrides every stage's model, for a one-off run.

The chain passes its stages no permission rule for the tracker: under the repository's own permissions, a stage needs whatever the tracker skill's calls need allowed, by the repository or the user ([`tracker.md`](tracker.md) → *What a headless stage needs allowed*).

It needs `git`, `claude`, `gh`, `jq` and `timeout` on the path, with `claude` and `gh` signed in. `timeout` is GNU coreutils; on macOS, install coreutils.

## The pre-review

Every chain run reviews its own pull request with the repository's own review before anyone is asked to read it. `raise-pr` opens the pull request as a draft (`/gaffer:raise-pr --draft <issue>`), and a fourth stage, `/gaffer:pre-review`, runs `/gaffer:review-pr --dry-run` against it, fixes once what that review confirms, and marks the pull request ready. Marking it ready is what starts the repository's usual review, which then reads a pull request whose verified findings are already dealt with. No setting turns the stage off; a settings file that still names `pre_review`, the opt-in it once had, is refused.

- **What is fixed:** every Critical and Major finding the dry run confirms and every mechanical note it raises, each in one commit pushed to the pull request after the formatter and the build-and-test command pass against it; and a finding about the pull request body, in the body. A pre-review with nothing to fix adds no commit.
- **What is left:** Minor notes, which need the author's judgement, and anything the review tags Pre-existing, which the branch did not cause. Both are named in the stage's report and carried nowhere else — not to the pull request, and not to the posted review, which judges the pull request on what it sees.
- **It runs once.** The fix is not reviewed again here; the posted review reads it.
- **Nothing is posted** by the dry run: no review, comment, reply or label.
- **On failure** — a finding the fix pass cannot fix, a suite that fails after the fix, a push or `gh` call that fails — nothing failing is pushed, the pull request stays a draft, and the chain stops at `[4/4] pre-review` naming the cause. The runner parks the issue with a comment naming the open draft, and says what to do with it: finish it by hand (fix what stopped the run on its branch, then run `/gaffer:pre-review`, which marks it ready), or close it, delete its branch and remove the label to rebuild. Removing the label alone does not rebuild it, because the runner never builds an issue with an open pull request.

`/gaffer:pre-review` runs by hand too, against the current branch's open pull request: it marks the pull request ready only if it was a draft.

**The repository's own review must wait for the draft.** The pre-review only helps where the posted review runs when a pull request is marked ready, not when it is opened: a workflow that skips drafts and runs on `ready_for_review`. That is the repository's to configure; the plugin ships no workflow. A branch that edits `REVIEW.md` is pre-reviewed by the branch's copy, where a review in CI uses `main`'s.

## `chain-local.sh` — one issue to a reviewed pull request, by hand

```bash
bash /path/to/gaffer-claude/chain/chain-local.sh [--dry-run] [--review-dry-run] [--skip-permissions] [--settings <file>] <issue>
```

For a repository with no CI review and no runner: started by hand against one confirmed issue, from the same place and with the same prerequisites as `chain.sh`. It runs `chain.sh` unchanged with the options and the issue it was given and, only when the chain ends on `chain: done — <pull request>`, runs `/gaffer:review-pr <pull request>` as one more headless stage, loaded from the same checkout. That is build → verify → raise-pr --draft → pre-review → review-pr: the posted review reads a pull request whose dry-run findings are already fixed.

- **A chain failure is the chain's.** Its output, closing lines and exit code pass through, 75 and 78 included, and no review runs.
- **Only this branch's pull request, on origin's repository, is reviewed.** The pull request the chain names must be on origin's repository under its current name, where `raise-pr` opens it, and must be the one `gh` finds there for the checked-out branch. Otherwise no review runs, the closing line says which check refused it, and the exit code is 1, as it is when the chain's closing line names no pull request. The name comes from a model's verdict, and the review posts under your account. Every pull request call names origin's repository, so a fork clone is not sent to its upstream.
- **The review is checked on GitHub.** `review-pr` writes no verdict, so the stage succeeds only on one more review than before it started that meets the post-condition [`unattended.md`](unattended.md) states for review-pr — marked `<!-- review-pr -->`, carrying the `Risk tier:` line — and is also by the account `gh` is signed in as, submitted rather than pending, and on the head commit as read before the review started. A review someone else posts meanwhile does not count. A review that exits cleanly having posted nothing fails, as does one claude reports as an error, a reply that is not JSON, or a stall; the usage limit exits 75, quoting the limit's reset wording where the reply gives one. A failure leaves the pull request open as the chain raised it, and the closing line names it and the `claude --resume <id>` or `/gaffer:review-pr <pull request>` that continues the review — with `--dry-run` after a `--review-dry-run`, so copying it posts nothing either.
- **It posts under your `gh` account**, as `review-pr` run by hand does. `--review-dry-run` has the review print what it would post and post nothing, and the closing line says so; `--dry-run` prints the chain's dry run, then the review it would run, and starts nothing.
- **The review stage runs as the chain's stages do**: on `CHAIN_MODEL`, else `opus`, at high effort, within `CHAIN_STAGE_TIMEOUT` seconds, else 2h. The settings file's `stages` has no row for it. `--skip-permissions` applies to it too; without it, the review needs its `gh` calls allowed as any headless stage does ([`unattended.md`](unattended.md)).
- **Where CI also reviews, the pull request is reviewed twice.** The pre-review marks the pull request ready, which starts the repository's own review in CI, and this script then posts a second one from your machine: two posted reviews of the same commit, and a second review's model time, on top of the pre-review's dry run. Nothing here detects a CI review and skips its own. In such a repository `chain.sh` alone ends in a reviewed pull request.

## The settings file

`chain.sh` and `chain-next.sh` read one JSON file in the repository they run for, conventionally `.gaffer/chain.json`, committed so a change to it is reviewed. Everything in it has a default except the two things that make the runner safe to leave alone:

```json
{
  "clone": "~/Repos/my-repo-runner",
  "writers": ["User:octocat", "Bot:claude"],
  "labels": { "ready": "ready", "parked": "parked" },
  "stages": {
    "build": { "model": "opus", "effort": "high" },
    "verify": { "model": "opus", "effort": "high" },
    "raise-pr": { "model": "opus", "effort": "medium" },
    "pre-review": { "model": "opus", "effort": "high" }
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
| `stages.<stage>.model`, `.effort` | chain | `opus` and `high` for build, verify and pre-review, `opus` and `medium` for raise-pr | Each stage's model and reasoning effort. A command run by hand keeps the session's model; these bind only the chain. |
| `skip_permissions` | runner | `false` | Whether the runner passes `--skip-permissions` to the chain. See *Permissions*. |
| `state_dir` | runner | `$XDG_STATE_HOME/gaffer-chain/<clone name>`, or `~/.local/state/…` | Where the runner keeps its lock and `logs/`, outside the clone. Per clone, so two repositories on one machine never share a lock or mix logs. |

`chain.sh` reads only `stages`, from `.gaffer/chain.json` in the current directory when it exists or from `--settings <file>`; without either it runs on the defaults. Both scripts refuse a file that names `pre_review`, a key that no longer exists, and say so. `chain-next.sh` is handed the file and refuses it when a required key is missing, a value has the wrong shape, or a key is one it does not know — a misspelt key would otherwise be a silently applied default.

Where the file `chain-next.sh` is handed sits inside a git checkout — as the clone's own `.gaffer/chain.json` does — it fetches that checkout's `origin` and reads the file as `origin/main` holds it at the same path, never the copy on disk: a branch an earlier firing left checked out, or an edit left uncommitted, decides nothing, and a broken one stops nothing. It refuses, before anything is selected, when the fetch fails, when `main` has no file at that path, when `main`'s copy is invalid, and when `main`'s `clone` names another checkout than the one the file sits in. A file outside any checkout is read as it stands.

## `chain-next.sh` — the runner

```bash
bash /path/to/gaffer-claude/chain/chain-next.sh [--dry-run] <settings-file>
```

One firing. The runner is GitHub-only: it selects and parks issues with `gh` itself, loads no tracker skill, and refuses a `tracker` setting as a key it does not know. It picks the lowest-numbered open issue carrying the ready label that is not parked, has no open pull request linked to it (by `Closes` or by a `feature/<N>-` branch), has no open blocking issue in GitHub's issue dependencies, and has been written on by nobody outside `writers` — a comment counts even after it is deleted. Then it resets the dedicated clone to the latest `origin/main` (`checkout -f`, `clean -fdx`, local branches whose upstream is gone deleted), sets aside any `feature/<N>-*` branch an earlier attempt left as `attempt/<N>-<stamp>`, and runs `chain.sh` there, logging to `logs/<N>-<stamp>.log` in the state directory. On success the issue has an open pull request. On failure the issue is labelled parked with a comment naming the failed stage, the reason, the log, the kept attempt branch, any branch that was pushed without a pull request, and any draft pull request a failed pre-review left open; removing the label has the next firing build it again from scratch, except where a draft is open — then the comment says to finish the draft or close it first. A usage-limit stop is parked too, with a comment saying nothing on the issue needs looking at. `--dry-run` names the issue the next firing would build, and changes nothing on GitHub or in the clone's branches and working tree; it does fetch, as a firing does, which moves only the clone's remote-tracking refs.

The runner never merges, never pushes and never deletes anything on GitHub; only the chain's raise-pr and pre-review stages push. It changes nothing when nothing is eligible, when another firing holds the lock, or when a GitHub query fails — every query fails closed, selecting nothing rather than guessing. A fault in its own setup — the settings, the plugin checkout, the clone, a missing tool — is refused before anything is selected, so no issue is parked for it. So is a clone `gh` resolves to another repository than its `origin`, as a fork clone with an `upstream` remote or `gh repo set-default` does: the runner's own `gh` calls name no repository, while the tracker skill sends every issue call to `origin`, so the runner would select and park one repository's issue while the chain builds the other's. `gh repo set-default <origin's owner/repo>` in the clone makes them agree. Origin's repository is compared under its current name, so a clone whose origin URL predates a rename or transfer is not refused for it. `chain.sh` run by hand makes no such check, and needs none for the pull request: raise-pr opens it on origin's repository, and pre-review finds it there. The lock is `flock(1)`, from util-linux: Linux has it, macOS needs it installed, and a scheduler that never overlaps its own runs needs nothing from it.

**Which plugin runs.** The runner refuses to run from a checkout that is not plainly this repository's `main`: on another branch, with uncommitted or untracked files, or with local commits `origin/main` does not have. It never updates the checkout itself; the scheduler does, in the step before the firing, so the run that follows is a known commit, printed in the runner's output as `gaffer at <sha>`.

## Permissions

By default every stage runs under the repository's own permission rules, and a headless session denies anything they do not allow — silently, so a stage can carry on degraded and still report success ([`unattended.md`](unattended.md)). Most repositories' rules do not allow a build, so an unattended runner will want `skip_permissions: true` (or `--skip-permissions` on the chain), which runs every stage with `--dangerously-skip-permissions`: nothing is refused, including a write to any path the user can reach or a command that leaves the clone. Opt in only where that is contained: a clone used by nothing else, a machine or account set aside for the runner — a container or a VM is the right unit — credentials that reach only what the chain must push and comment on, and `writers` naming only accounts you trust to write an issue the chain will build unread. The runner reads the opt-in from the settings file as `origin/main` holds it, fetched at the start of every firing, so it changes only by a reviewed pull request: an edit on a branch the previous firing left checked out is not read.

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

3. Commit the settings file to the repository's `main`, with `clone` and `writers` at least. Each firing fetches the clone's `origin` and reads the file as `origin/main` holds it, whatever branch the clone was left on, so a change takes effect at the first firing that starts after it merges. Create the runner's parked label once, unless it exists already:

   ```bash
   gh label create parked --description "An unattended run stopped on this issue; remove to retry"
   ```

   The runner parks with its own `labels.parked`; name another there and create that label by hand.

4. Check what the first firing would do. This reads GitHub, confirms both clones are where the runner expects, and changes nothing but the clone's remote-tracking refs, which it fetches:

   ```bash
   bash ~/Repos/gaffer-runner/chain/chain-next.sh --dry-run ~/Repos/<repo>-runner/.gaffer/chain.json
   ```

5. Schedule it. The plugin ships no unit; this is the shape, as a systemd user timer with lingering enabled so it survives logout. A user unit starts with a minimal environment, so `PATH` names where `claude`, `gh`, `jq`, `git`, `flock`, `timeout` and the repository's build tools live. The update step is the scheduler's, which is why it is here and not in the runner.

   ```ini
   [Service]
   Type=oneshot
   Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
   ExecStartPre=/bin/mkdir -p %h/.local/state/gaffer-chain/<repo>-runner
   ExecStartPre=/usr/bin/flock -n %h/.local/state/gaffer-chain/<repo>-runner/lock /usr/bin/git -C %h/Repos/gaffer-runner pull -q --ff-only
   ExecStart=/bin/bash %h/Repos/gaffer-runner/chain/chain-next.sh %h/Repos/<repo>-runner/.gaffer/chain.json
   TimeoutStartSec=infinity
   ```

   with a timer of `OnCalendar=*:0/15`. A firing while a run is in progress does nothing: systemd does not start an active service twice, and the lock covers a run started by hand — including the update step, which takes the runner's own lock so a run in progress is never updated beneath; a held lock fails the step, and the firing with it, which is right.

To retry a parked issue, remove the label. To finish a parked attempt instead of rebuilding it, fetch its `attempt/<N>-<stamp>` branch from the runner's clone into a checkout of your own, rebase it onto `main`, and run the stages the chain did not finish by hand — leaving `parked` on until the pull request is open, or the next firing rebuilds the issue beside it.

## Tests

`bash chain/chain.tests.sh`, `bash chain/chain-next.tests.sh` and `bash chain/chain-local.tests.sh`, all run by CI. They use a stub `claude`, a stub `gh` and throwaway repositories under a temp directory, so no model is called, nothing reaches GitHub and your checkout is untouched. The chain matrix is the specification of how a verdict is read; the runner matrix, of what is selected and what a failure leaves behind; the local matrix, of when the hand-run wrapper reviews and which reviews count as posted.
