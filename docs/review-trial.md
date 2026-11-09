# Review trial procedure

How to measure a change to review-pr against `main` on a merged NetPace PR, before the change merges. It applies the decisions confirmed on #23.

### 0. Fixed for every run

Hold these constant across all arms, or the comparison is void:

- **Orchestrator model:** `--model opus` on every run. Arms differ only in what the plugin itself sets, such as arm C's specialist model.
- **Settings:** don't change `/effort`, `settings.json` or installed plugins between runs.
- **One run at a time.** review-pr makes a worktree named after the PR number, so two concurrent runs on the same PR collide.
- **Only the arm's plugin is loaded.** If the installed `gaffer` plugin is also enabled in the trial clone, disable it there for the trial, then check on the first run that the commands came from the arm's directory and not the installed copy. The init message in the run's `--output-format stream-json` output, or `/plugin` interactively, shows which is loaded.

### 1. Arms

Each arm is a gaffer-claude worktree passed as `--plugin-dir`:

```bash
cd ~/Repos/gaffer-claude    # your gaffer-claude clone
git worktree add ../gaffer-arm-A main
git worktree add ../gaffer-arm-B feature/23-minor-notes    # once it exists
git worktree add ../gaffer-arm-C feature/23-sonnet-specialists   # once it exists
```

Record each arm's commit (`git -C ../gaffer-arm-X rev-parse --short HEAD`) in the results. Don't move an arm's branch mid-trial; if it must change, re-run that arm's runs.

### 2. Find the PR's first-round state

For each NetPace PR under trial (start with PR 520, for #494):

```bash
# First-round head: the commit the first review-pr review was posted against
gh api repos/FrankRay78/NetPace/pulls/520/reviews \
  --jq '[.[] | select(.body | contains("<!-- review-pr -->"))] | min_by(.submitted_at) | .commit_id'

# The merge commit, to find the base
gh pr view 520 --repo FrankRay78/NetPace --json mergeCommit,body,title --jq '.mergeCommit.oid'
```

In a NetPace clone with full history, the base is where the branch left `main`:

```bash
BASE=$(git merge-base <first-round-head> <merge-commit>^1)
```

This holds for squash and merge-commit merges. For a rebase merge it doesn't; find the base from the PR's commit list instead.

Also record the real first-round counts by severity, from that first review's summary comment. That is the reference row.

### 3. Build the scratch repository (once per trial, with approval)

This creates a private repository and pushes to it, so it needs the maintainer's go-ahead. Nothing is pushed to NetPace.

```bash
gh repo create FrankRay78/gaffer-trial-netpace --private
cd <netpace-clone>
git remote add trial https://github.com/FrankRay78/gaffer-trial-netpace.git
git push trial $BASE:refs/heads/main <first-round-head>:refs/heads/trial/pr520
```

Then open the PR in the scratch repository. Use the original PR's title and body, with each `Closes #N` / `Refs #N` rewritten to the full NetPace issue URL, so review-pr reads the real issue for intent:

```bash
gh pr create --repo FrankRay78/gaffer-trial-netpace --base main --head trial/pr520 \
  --title "<original title>" --body-file <rewritten body file>
```

Record the scratch PR number. The PR body is the one GitHub holds now, which may have been edited after the first round; note that in the results.

### 4. The trial clone

Runs happen in a local clone of the scratch repository, checked out at `main` (the base). review-pr reads `REVIEW.md` and `CONVENTIONS.md` from the root of the repository it runs in, so this gives every run NetPace's rules as they stood at the base.

```bash
git clone https://github.com/FrankRay78/gaffer-trial-netpace.git ~/Repos/gaffer-trial-netpace
```

Check the clone is clean, and that `.claude/scratch/review-pr-<N>` doesn't exist before each run.

### 5. One run

```bash
cd ~/Repos/gaffer-trial-netpace
claude -p "/gaffer:review-pr <scratch-PR> --dry-run" \
  --plugin-dir ~/Repos/gaffer-arm-X \
  --model opus \
  --output-format json \
  > ~/trial-results/pr520-X-<run>.json
```

Headless runs need permission for `gh`, `git`, Read, Grep and Glob. Grant them with `--allowedTools` (preferred) or a permissive `--permission-mode`. Use the same choice for every arm. review-pr never runs the PR's code.

From the JSON, record the reported total cost and duration. Check the field names on the first run; they are expected to be `total_cost_usd` and `duration_ms`. The `result` field holds the printed review: save it alongside the JSON.

Then remove any leftover worktree: `git worktree remove --force .claude/scratch/review-pr-<N>` if it exists.

### 6. Runs per arm

At least 2 runs per arm, on at least 2 PRs (from #494 / PR 520, #518, #447). Interleave arms (A1, B1, A2, B2, …) rather than running one arm back to back, so a provider slowdown doesn't land on one arm.

Order, per #23:

1. A against B on PR 520 only. If B fails, stop and report.
2. Then A, B and C on the other PRs.

### 7. Results table

One row per run:

| PR | Arm | Arm commit | Run | Cost ($) | Duration (min) | Critical | Major | Minor findings | Notes (unverified) | Verifier runs |
|---|---|---|---|---|---|---|---|---|---|---|

Under the table, list every Critical and Major finding from every run, deduplicated by root cause across arms. Give each one an ID, the runs that found it, `file:line` and a one-line claim.

### 8. Judging and pass rule

The maintainer marks each listed finding **real** or **not real**. Then, per #23's confirmed decisions:

- The bar is every real Critical or Major found in any A run.
- An arm passes if every finding on the bar appears in at least one of its runs, and its mean cost per run is below the arm it's compared with (B against A; C against B).
- A failing arm's change doesn't merge. The results comment says why.

### 9. Post the results

Post one comment on #23 per trial stage, with the arm commits, the table, the judged finding list, the pass/fail call for each arm, and anything that deviated from this procedure.

### 10. Mechanical-fix trial (item 2, later)

This one changes verify, so it needs a build. Copy the NetPace issue into the scratch repository as an issue, run `/gaffer:build` once from the base, then run old and new verify on copies of that branch and review both with the same review-pr arm. This section will be filled in when item 2 is built.

### 11. Cleanup

Keep the scratch repository until #23 closes, so runs can be repeated. Delete it then, with the maintainer's approval.
