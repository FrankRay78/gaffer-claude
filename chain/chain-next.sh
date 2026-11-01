#!/usr/bin/env bash
#
# chain-next.sh — build the next ready issue to a pull request, from a timer, unattended.
#
# Each firing reads one settings file (docs/chain.md), picks the lowest-numbered eligible issue
# of the repository the settings name — open, carrying the ready label, not the parked label,
# with no open pull request linked to it, no open blocking issue, and nothing written on it by
# anyone outside the settings' writers — resets the runner's own dedicated clone of that
# repository to the latest main, and runs chain.sh, beside this file, against the issue there. It
# ends with either an open pull request (the chain's last stage) or the issue labelled parked with
# a comment naming the failed stage, the log and the kept branch. Where the chain's own exit code
# says a stage was cut off by the account's Claude usage limit, that comment says so instead and
# tells the maintainer the issue itself needs only its parked label removed once the limit has
# reset. It never merges, and it never itself deletes or pushes anything on GitHub; only the
# chain's raise-pr stage pushes.
#
# WHY. chain.sh carries one named issue to a pull request, but someone still has to pick the
# issue, and return the checkout to a clean main afterwards — the chain leaves its feature branch
# checked out and refuses to start anywhere else. Doing that in the checkout someone also works
# in interactively lets the two collide. This runner owns a clone nobody else touches.
#
# WHAT IT COSTS. A firing with something eligible spends a full chain run of model time and opens
# a real pull request. An empty firing costs a few gh calls and changes nothing.
#
# THE RESET IS DESTRUCTIVE: `git checkout -f`, `reset --hard` and `clean -fdx`. It runs only in a
# clone marked `git config chain-next.dedicated true`, never in a worktree, and only once an issue
# has been selected. Logs and the lock live outside the clone, or `clean -fdx` would delete them.
#
# WHICH PLUGIN RUNS. The chain loads its stages from this checkout, so every firing runs the
# commit this file belongs to. Bringing that checkout up to date is the scheduler's step, before
# the firing (docs/chain.md shows it); this script never updates itself. It does refuse to run from
# a checkout that is not plainly a plugin main: not on main, with uncommitted or untracked files,
# or with local commits its origin's main does not have — a headless run must use what main holds,
# and a checkout that has been edited is a fault to look at, not one to force past.
#
# Prerequisites: git, gh, jq and flock on PATH, plus chain.sh's own (claude, timeout); gh and
# claude signed in; a git identity in the clone. flock comes from util-linux, so on macOS it is
# installed separately. Tests: chain-next.tests.sh beside this file.

# No -e: every failure below is reported by name rather than killing the firing silently.
set -uo pipefail

CHAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$CHAIN_DIR/.." && pwd)"

usage() {
  echo "usage: chain-next.sh [--dry-run] <settings-file>" >&2
  echo "  <settings-file>: the repository's chain settings, usually its .gaffer/chain.json" >&2
  echo "  --dry-run: name the issue the next firing would build, and change nothing" >&2
}

# chain.sh's exit codes, as the literals it defines. The two files sit in one checkout and change
# together. 75: a stage the account's usage limit cut off — parked, but with a comment saying so.
# 78: the chain's own configuration could not be read, so nothing ran and the issue is not at
# fault; parking it would blame it, and every later firing would park the next issue the same way.
CHAIN_USAGE_LIMIT_EXIT=75
CHAIN_CONFIG_EXIT=78

say() { echo "chain-next: $*"; }
die() { echo "chain-next: $*" >&2; exit 1; }

# expand_home <path> — a leading `~/` as the current user's home, so a committed settings file can
# name a path without naming the machine's user.
expand_home() { case "$1" in "~/"*) printf '%s' "$HOME/${1#\~/}" ;; *) printf '%s' "$1" ;; esac; }

# read_settings <file> — every key the runner owns, checked before anything else happens, so a
# fault in the file is reported with nothing selected, reset or run. The clone path and the
# writers have no default: the clone because it is where the destructive reset runs, the writers
# because they are what stops the runner building a stranger's issue on a public repository — a
# file that names none refuses every issue. A key the runner does not know is a typo until proven
# otherwise, and refused, since a misspelt key would otherwise be a silently applied default.
read_settings() {
  local f=$1 s unknown
  [ -f "$f" ] || die "refused — the settings file $f does not exist; nothing was run."
  s=$(jq -e 'if type == "object" then . else error("x") end' "$f" 2>/dev/null) \
    || die "refused — the settings file $f is not a JSON object; nothing was run."
  unknown=$(jq -r 'keys - ["clone", "writers", "labels", "stages", "skip_permissions", "state_dir"] | .[]' <<<"$s" | paste -sd' ')
  [ -z "$unknown" ] || die "refused — $f names a setting this runner does not know: $unknown. Nothing was run."
  CLONE=$(jq -r 'if (.clone | type) == "string" and (.clone | length) > 0 then .clone else error("x") end' <<<"$s" 2>/dev/null) \
    || die "refused — $f must name the runner's dedicated clone as \"clone\"; nothing was run."
  CLONE=$(expand_home "$CLONE")
  WRITERS=$(jq -c 'if (.writers | type) == "array" and (.writers | length) > 0 and all(.writers[]; type == "string" and test("^[A-Za-z]+:.+$")) then .writers else error("x") end' <<<"$s" 2>/dev/null) \
    || die "refused — $f must name the accounts whose issues may be built, as \"writers\": a non-empty list of \"<Type>:<login>\" (\"User:octocat\", \"Bot:claude\"); with none named, no issue is ever built. Nothing was run."
  READY_LABEL=$(jq -r 'if .labels == null then "ready" elif (.labels | type) == "object" and (.labels.ready == null or ((.labels.ready | type) == "string" and (.labels.ready | length) > 0)) then (.labels.ready // "ready") else error("x") end' <<<"$s" 2>/dev/null) \
    || die "refused — in $f, labels.ready is not a non-empty string; nothing was run."
  PARKED_LABEL=$(jq -r 'if .labels == null then "parked" elif (.labels | type) == "object" and (.labels.parked == null or ((.labels.parked | type) == "string" and (.labels.parked | length) > 0)) then (.labels.parked // "parked") else error("x") end' <<<"$s" 2>/dev/null) \
    || die "refused — in $f, labels.parked is not a non-empty string; nothing was run."
  unknown=$(jq -r 'if (.labels | type) == "object" then (.labels | keys - ["ready", "parked"] | .[]) else empty end' <<<"$s" | paste -sd' ')
  [ -z "$unknown" ] || die "refused — in $f, labels names a label this runner does not know: $unknown. Nothing was run."
  [ "$READY_LABEL" != "$PARKED_LABEL" ] || die "refused — in $f, the ready and parked labels are the same label; nothing was run."
  SKIP_PERMISSIONS=$(jq -r 'if .skip_permissions == null then false elif (.skip_permissions | type) == "boolean" then .skip_permissions else error("x") end' <<<"$s" 2>/dev/null) \
    || die "refused — in $f, skip_permissions is not true or false; nothing was run."
  STATE=$(jq -r --arg d "${XDG_STATE_HOME:-$HOME/.local/state}/gaffer-chain/$(basename "$CLONE")" \
      'if .state_dir == null then $d elif (.state_dir | type) == "string" and (.state_dir | length) > 0 then .state_dir else error("x") end' <<<"$s" 2>/dev/null) \
    || die "refused — in $f, state_dir is not a non-empty string; nothing was run."
  STATE=$(expand_home "$STATE")
}

# select_issue — print the number of the lowest-numbered eligible issue, or nothing. Fails closed:
# any GitHub query that fails or returns something unreadable ends the firing with an error
# rather than guessing, because a guess in either direction builds the wrong thing or nothing.
select_issue() {
  local issues prs raised candidates n blockers open writers
  issues=$(gh issue list --state open --label "$READY_LABEL" --json number,labels --limit 1000) \
    || die "refused — could not list $READY_LABEL issues; nothing selected."
  prs=$(gh pr list --state open --json number,headRefName,closingIssuesReferences --limit 1000) \
    || die "refused — could not list open pull requests; nothing selected."
  # An issue is already raised when an open pull request closes it, or — the fallback for a
  # pull request opened without the closing keyword — when its branch is feature/<N>-…, the name
  # /gaffer:build gives it.
  raised=$(jq -r '[.[] | (.closingIssuesReferences // [] | .[].number),
      (.headRefName | capture("^feature/(?<n>[0-9]+)-")? | .n | tonumber)] | unique | .[]' <<<"$prs") \
    || die "refused — the open pull request list was unreadable; nothing selected."
  candidates=$(jq -r --argjson raised "$(jq -s . <<<"$raised")" --arg parked "$PARKED_LABEL" \
      '[.[] | select((.labels | map(.name) | index($parked)) | not) | .number]
       | map(select(. as $n | $raised | index($n) | not)) | sort | .[]' <<<"$issues") \
    || die "refused — the $READY_LABEL issue list was unreadable; nothing selected."
  for n in $candidates; do
    blockers=$(gh api --paginate "repos/{owner}/{repo}/issues/$n/dependencies/blocked_by") \
      || die "refused — could not read what blocks #$n; nothing selected."
    open=$(jq -s '[.[][] | select(.state == "open")] | length' <<<"$blockers") \
      || die "refused — the blocker list for #$n was unreadable; nothing selected."
    [ "$open" = 0 ] || continue
    # Who has written on the issue, as type and login: the type matters because GraphQL names a
    # bot by a login an unrelated person can also hold. Deleted comments count: GitHub records
    # the author of a comment someone else deleted, so a stranger's comment that a confirmation
    # folded in and then deleted still shows here.
    writers=$(gh api graphql --paginate -F owner='{owner}' -F repo='{repo}' -F n="$n" -f query='
      query($owner: String!, $repo: String!, $n: Int!, $endCursor: String) {
        repository(owner: $owner, name: $repo) { issue(number: $n) { author { __typename login }
          timelineItems(first: 100, after: $endCursor, itemTypes: [ISSUE_COMMENT, COMMENT_DELETED_EVENT]) {
            pageInfo { hasNextPage endCursor }
            nodes { ... on IssueComment { author { __typename login } } ... on CommentDeletedEvent { deletedCommentAuthor { __typename login } } } } } } }') \
      || die "refused — could not read who has written on #$n; nothing selected."
    writers=$(jq -s --argjson allowed "$WRITERS" '[.[].data.repository.issue | .author,
        (.timelineItems.nodes[] | .author // .deletedCommentAuthor) | "\(.__typename):\(.login)"] - $allowed | length' <<<"$writers") \
      || die "refused — the writer list for #$n was unreadable; nothing selected."
    if [ "$writers" != 0 ]; then
      say "skipped #$n — someone outside the settings' writers has written on it." >&2
      continue
    fi
    echo "$n"; return 0
  done
}

# free_name <prefix> <exists-command…> — <prefix>, or <prefix>-2, -3… — the first the command
# reports as not existing. Several branches set aside in one firing, or two attempts at one issue
# within a second, would otherwise collide.
free_name() {
  local base=$1 name=$1 i=1; shift
  while "$@" "$name"; do i=$((i+1)); name="$base-$i"; done
  echo "$name"
}
branch_exists() { git rev-parse -q --verify "refs/heads/$1" >/dev/null; }
log_exists() { [ -e "$1.log" ]; }

# keep_attempts <n> — rename every local feature/<n>-* branch to attempt/<n>-<stamp>, printing
# the new names. /build stops when the issue's branch already exists with commits it has not
# inspected, so a branch left by a failed or killed run would park the issue again on retry.
# Renaming keeps the work for diagnosis and lets the next /build start clean. Nothing is pushed.
keep_attempts() {
  local n=$1 b kept
  for b in $(git for-each-ref --format='%(refname:short)' "refs/heads/feature/$n-*"); do
    kept=$(free_name "attempt/$n-$STAMP" branch_exists)
    git branch -m "$b" "$kept" || die "could not rename $b to $kept."
    echo "$kept"
  done
}

# check_plugin — this checkout is a plugin, on main, clean, and holds nothing its origin's main
# does not. Checked against the origin/main the last fetch left, with no network call of its own:
# the scheduler's update step is what fetches, and a checkout that step could not fast-forward is
# refused here rather than run from. Nothing is changed to clear the way.
check_plugin() {
  local branch dirty
  [ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ] \
    || die "refused — $PLUGIN_ROOT is not a plugin checkout (no .claude-plugin/plugin.json); nothing was run."
  branch=$(git -C "$PLUGIN_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) \
    || die "refused — $PLUGIN_ROOT is not a git checkout, so what it holds cannot be checked; nothing was run."
  [ "$branch" = main ] || die "refused — $PLUGIN_ROOT has $branch checked out, not main; nothing was run."
  dirty=$(git -C "$PLUGIN_ROOT" status --porcelain) || die "could not read the state of $PLUGIN_ROOT; nothing was run."
  [ -z "$dirty" ] || die "refused — $PLUGIN_ROOT has uncommitted or untracked files; nothing was run."
  git -C "$PLUGIN_ROOT" rev-parse -q --verify refs/remotes/origin/main >/dev/null \
    || die "refused — $PLUGIN_ROOT has no origin/main to compare with; nothing was run."
  git -C "$PLUGIN_ROOT" merge-base --is-ancestor HEAD refs/remotes/origin/main \
    || die "refused — $PLUGIN_ROOT has local commits its origin's main does not; nothing was run."
}

# reset_clone — the latest main: no local change, no untracked or ignored file, and no local
# feature branch whose upstream is gone (merged and deleted on GitHub). attempt/* branches stay,
# even when a pushed twin they still track has been removed by hand.
reset_clone() {
  local gone
  git fetch -q --prune origin || die "could not fetch origin in $CLONE; nothing was run."
  git checkout -q -f -B main origin/main || die "could not check out origin/main in $CLONE; nothing was run."
  git clean -q -fdx || die "could not clean $CLONE; nothing was run."
  for gone in $(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/feature | awk '$2 == "[gone]" {print $1}'); do
    git branch -q -D "$gone" || say "could not delete $gone, whose upstream is gone; continuing."
  done
}

# park <n> <log> <chain exit code> — label the issue parked and say why on it, from the chain's
# closing line. The exit code, not the closing line's prose, is what tells a usage-limit stop from
# every other failure: the chain decides that from the reply's typed error field, where the prose
# could be a report quoting a limit message it merely read about.
park() {
  local n=$1 log=$2 rc=$3 closing stage reason kept remote body
  closing=$(grep -E '^chain: FAILED at \[[0-9]+/[0-9]+\] ' "$log" | tail -n 1)
  if [ -n "$closing" ]; then
    stage=$(sed -E 's/^chain: FAILED at (\[[0-9]+\/[0-9]+\] [^ ]+) — .*/\1/' <<<"$closing")
    reason=${closing#* — }
  else
    stage="before the first stage"
    reason=$(grep -v '^[[:space:]]*$' "$log" | tail -n 1)
    reason=${reason:-no output}
  fi
  kept=$(keep_attempts "$n" | paste -sd' ')
  remote=$(git ls-remote --heads origin "refs/heads/feature/$n-*" | awk '{sub("refs/heads/", "", $2); print $2}' | paste -sd' ')
  body="Parked by the chain runner: the chain stopped at **$stage** — $reason"$'\n\n'
  body+="- Full log on the build machine: \`$log\`"$'\n'
  if [ -n "$kept" ]; then
    body+="- The attempt's commits are kept locally in the runner's clone on \`$kept\` (not pushed)."$'\n'
  fi
  if [ -n "$remote" ]; then
    body+="- \`$remote\` was pushed but has no open pull request. The runner never deletes anything on GitHub, so remove or reuse it by hand before un-parking, or the next push will be rejected."$'\n'
  fi
  if [ "$rc" = "$CHAIN_USAGE_LIMIT_EXIT" ]; then
    # Nothing to diagnose, so the comment says so first: a usage-limit stop and a genuine failure
    # would otherwise park identically, and the maintainer would read the transcript to tell them
    # apart. "From scratch" stays true — un-parking restarts the issue, it does not resume it.
    body+=$'\n'"Nothing on this issue needs looking at: the chain stopped because the Claude usage limit was reached, not because anything is wrong with the issue. Remove the \`$PARKED_LABEL\` label once the limit has reset, and the runner will build it again from scratch."
  else
    body+=$'\n'"Remove the \`$PARKED_LABEL\` label to have the runner build this issue again from scratch."
  fi
  gh issue edit "$n" --add-label "$PARKED_LABEL" >/dev/null || die "could not label #$n $PARKED_LABEL — it will be selected again. Log: $log"
  gh issue comment "$n" --body "$body" >/dev/null || die "#$n is parked but the comment could not be posted. Log: $log"
  say "#$n parked — $stage — $reason (log: $log)"
}

main() {
  local dry_run=0 settings n log rc kept attempts top git_dir common_dir
  local -a chain_flags
  if [ "${1:-}" = --dry-run ]; then dry_run=1; shift; fi
  if [ $# -ne 1 ]; then usage; exit 1; fi
  case "$1" in --*) usage; exit 1 ;; esac
  # Absolute, because the chain is started from inside the clone and handed the same file.
  settings=$1
  [ -f "$settings" ] || die "refused — the settings file $settings does not exist; nothing was run."
  settings="$(cd "$(dirname "$settings")" && pwd)/$(basename "$settings")"

  for tool in git gh jq flock claude timeout; do
    command -v "$tool" >/dev/null 2>&1 || die "refused — $tool is not on PATH; nothing was run."
  done

  read_settings "$settings"
  # The plugin checkout before the tracker is queried: a machine fault is reported before
  # anything is chosen, and report mode says what the next firing would refuse on.
  check_plugin

  # The reset below is destructive, so the clone must be exactly the one set aside for it: its
  # top level, not a worktree (worktrees share the marker and would share branches with the
  # checkout they belong to), and marked.
  [ -d "$CLONE" ] || die "refused — the runner's clone $CLONE does not exist; create it, or correct \"clone\" in $settings. Nothing was run."
  cd "$CLONE" || die "refused — cannot enter $CLONE."
  top=$(git rev-parse --show-toplevel 2>/dev/null) || die "refused — $CLONE is not a git repository."
  git_dir=$(cd "$(git rev-parse --git-dir)" && pwd -P)
  common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
  if [ "$(cd "$top" && pwd -P)" != "$(pwd -P)" ] || [ "$git_dir" != "$common_dir" ] \
      || [ "$(git config --get chain-next.dedicated)" != true ]; then
    die "refused — $CLONE is not the runner's dedicated clone (a full clone marked with \`git config chain-next.dedicated true\`); nothing was changed."
  fi

  if [ "$dry_run" = 1 ]; then
    n=$(select_issue) || exit 1
    if [ -n "$n" ]; then say "would build #$n"; else say "nothing eligible — the next firing would do nothing"; fi
    exit 0
  fi

  mkdir -p "$STATE/logs" || die "could not create $STATE/logs."
  # One chain at a time. A scheduler never starts an active unit twice, but running the script
  # directly, outside it, could overlap; a firing that finds the lock held is not an error, only a
  # no-op.
  exec 9>>"$STATE/lock" || die "could not open the lock $STATE/lock."
  if ! flock -n 9; then say "a run is already in progress; nothing started."; exit 0; fi

  n=$(select_issue) || exit 1
  if [ -z "$n" ]; then say "nothing eligible."; exit 0; fi

  STAMP=$(date -u +%Y%m%dT%H%M%SZ)
  say "building #$n in $CLONE"
  say "gaffer at $(git -C "$PLUGIN_ROOT" rev-parse --short HEAD) in $PLUGIN_ROOT"
  reset_clone
  attempts=$(keep_attempts "$n") || die "could not set aside an earlier attempt at #$n; nothing was run."
  for kept in $attempts; do say "kept an earlier attempt at #$n as $kept"; done
  log=$(free_name "$STATE/logs/$n-$STAMP" log_exists).log
  chain_flags=(--settings "$settings")
  [ "$SKIP_PERMISSIONS" != true ] || chain_flags+=(--skip-permissions)
  # Started from the freshly reset main. Its stdin is /dev/null and its descriptor 9 is closed, so
  # no stage can hold the lock after the firing ends.
  bash "$CHAIN_DIR/chain.sh" "${chain_flags[@]}" "$n" </dev/null 9>&- 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  if [ "$rc" = 0 ]; then
    say "#$n raised (log: $log)"
    exit 0
  fi
  if [ "$rc" = "$CHAIN_CONFIG_EXIT" ]; then
    die "refused — the chain stopped on its own configuration (the settings, or the plugin checkout; see the log), so #$n was not parked. Log: $log"
  fi
  park "$n" "$log" "$rc"
  exit 1
}

main "$@"
