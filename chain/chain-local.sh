#!/usr/bin/env bash
#
# chain-local.sh — run the chain for one issue, then review the pull request it opened, by hand.
#
# For a repository with no CI review and no runner on a timer: the person starts this against one
# confirmed issue from a terminal, and it takes the issue to a reviewed pull request. It runs
# chain.sh beside it unchanged — build, verify, raise-pr and, where the settings opt in, pre-review
# — and, only when the chain ends with `chain: done — <pull request>`, runs /gaffer:review-pr
# against that pull request as one more headless `claude -p` stage, loaded from the same checkout.
#
# THE REVIEW'S RESULT. review-pr writes no verdict, so the stage is judged by what it posted, read
# back from GitHub (review_count): a stage that exits 0 having posted nothing is a failure, and a
# review someone else posts meanwhile does not count. The pull request reviewed must be the one `gh`
# finds for the checked-out branch: the URL arrives through a model's verdict, and the review posts
# under the user's account.
#
# WHAT IT LEAVES. A chain failure is the chain's own: its output, its closing lines and its exit
# code — 75 for the usage limit, 78 for a configuration fault — pass through, and no review runs.
# A review failure leaves the pull request open, as the chain raised it; the closing line names the
# pull request and the session to reopen, and a usage-limit stop exits 75 as the chain's does. This
# script writes nothing itself; only the review stage posts.
#
# Prerequisites: those of chain.sh, which checks them before its first stage.
#
# Usage: chain-local.sh [--dry-run] [--review-dry-run] [--skip-permissions] [--settings <file>] <issue>
#   Every listed option but --review-dry-run is chain.sh's and is passed to it. --review-dry-run runs
#   the review with --dry-run, so it prints what it would post and posts nothing. --skip-permissions
#   applies to the review stage too. The review runs on CHAIN_MODEL, else opus, at high effort,
#   within CHAIN_STAGE_TIMEOUT seconds, else 2h. Tests: chain-local.tests.sh beside this file.

set -uo pipefail

CHAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$CHAIN_DIR/.." && pwd)"
CHAIN="$CHAIN_DIR/chain.sh"

REVIEW_LIMIT=${CHAIN_STAGE_TIMEOUT:-7200}
REVIEW_MODEL=${CHAIN_MODEL:-opus}
REVIEW_EFFORT=high
# chain.sh's code for the usage limit, so a caller reads one meaning for it from either stage.
USAGE_LIMIT_EXIT=75
MARKER='<!-- review-pr -->'
# chain.sh's own pull request shape (chain.sh PR_URL), so nothing it would refuse is reviewed here.
PR_URL='^https://github\.com/[^[:space:]]+/pull/[0-9]+$'

usage() {
  echo "usage: chain-local.sh [--dry-run] [--review-dry-run] [--skip-permissions] [--settings <file>] <issue>" >&2
  echo "  runs chain.sh for the issue, then /gaffer:review-pr on the pull request it opened" >&2
  echo "  --review-dry-run: the review prints what it would post, and posts nothing" >&2
  echo "  every other option is chain.sh's; see docs/chain.md" >&2
}

dry_run=0
review_dry_run=0
skip_permissions=0
chain_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1; chain_args+=("$1"); shift ;;
    --review-dry-run) review_dry_run=1; shift ;;
    --skip-permissions) skip_permissions=1; chain_args+=("$1"); shift ;;
    --settings) [ $# -ge 2 ] || { usage; exit 1; }; chain_args+=("$1" "$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) usage; exit 1 ;;
    *) chain_args+=("$1"); shift ;;
  esac
done

review_prompt() {
  if [ "$review_dry_run" = 1 ]; then echo "/gaffer:review-pr $1 --dry-run"; else echo "/gaffer:review-pr $1"; fi
}

# The guarded expansion: bash before 4.4 (macOS's /bin/bash) treats an empty array as unset under
# `set -u`, so a run with no arguments would die here instead of showing chain.sh's usage.
if [ "$dry_run" = 1 ]; then
  bash "$CHAIN" ${chain_args[@]+"${chain_args[@]}"}
  rc=$?
  [ "$rc" = 0 ] || exit "$rc"
  echo "  then review-pr: $(review_prompt '<the pull request raise-pr opens>')"
  [ "$review_dry_run" = 0 ] || echo "  review: dry run, nothing posted"
  exit 0
fi

# Checked before the chain starts: without the log, a chain that opened a pull request would be
# reported as having named none.
log=$(mktemp) || { echo "chain-local: refused — mktemp failed; no stage was started."; exit 1; }
trap 'rm -f "$log"' EXIT
bash "$CHAIN" ${chain_args[@]+"${chain_args[@]}"} | tee "$log"
rc=${PIPESTATUS[0]}
[ "$rc" = 0 ] || exit "$rc"

pr=$(tail -n 1 "$log" | sed -n 's/^chain: done — //p')
if ! [[ $pr =~ $PR_URL ]]; then
  echo "chain-local: FAILED — the chain succeeded but its closing line names no pull request; no review ran."
  exit 1
fi

session=
review_fail() {
  echo "chain-local: FAILED at review-pr — $1"
  echo "chain-local: $pr is open as the chain left it."
  if [ -n "$session" ]; then
    echo "chain-local: reopen the review with \`claude --resume $session\`, or run \`/gaffer:review-pr $pr\` again."
  else
    echo "chain-local: run \`/gaffer:review-pr $pr\` again."
  fi
  exit "${2:-1}"
}

# A refusal before the review: unlike review_fail, it does not suggest reviewing $pr by hand,
# because what was refused may be the pull request itself.
refuse() {
  echo "chain-local: FAILED before review-pr — $1; no review ran."
  echo "chain-local: the chain's work is on the checked-out branch; check its pull request before reviewing it."
  exit 1
}

branch_pr=$(gh pr view --json url --jq .url 2>/dev/null) \
  || refuse "gh found no pull request for the checked-out branch, so $pr could not be confirmed as this branch's"
[ "$branch_pr" = "$pr" ] || refuse "the chain named $pr, but the checked-out branch's pull request is $branch_pr"

# review_count <head> — the reviews the stage is judged by: those by the signed-in account,
# submitted, on <head>, carrying the marker and the tier line (docs/unattended.md, plus the account
# and state). <head> is the one read before the review, so a push during it does not disown the
# review posted on the commit it read. Fails closed on a gh or jq error.
review_count() {
  local n
  n=$(gh pr view "$pr" --json reviews 2>/dev/null | jq -e --arg me "$me" --arg head "$1" --arg marker "$MARKER" \
      '[.reviews[] | select(.author.login == $me and .state != "PENDING" and .commit.oid == $head
        and (.body | contains($marker)) and (.body | contains("Risk tier:")))] | length' 2>/dev/null) || return 1
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  echo "$n"
}

before=0
if [ "$review_dry_run" = 0 ]; then
  me=$(gh api user --jq .login 2>/dev/null)
  [ -n "$me" ] || refuse "gh could not name the account it is signed in as"
  head=$(gh pr view "$pr" --json headRefOid --jq .headRefOid 2>/dev/null)
  [ -n "$head" ] || refuse "gh could not read the pull request's head commit"
  before=$(review_count "$head") || refuse "gh could not read the pull request's reviews"
fi

echo "chain-local: review-pr — starting"
# Run as chain.sh's run_stage runs a stage; its comment says why each part is there.
cmd=(claude -p "$(review_prompt "$pr")" --plugin-dir "$PLUGIN_ROOT" --model "$REVIEW_MODEL" --effort "$REVIEW_EFFORT" --output-format json)
[ "$skip_permissions" = 0 ] || cmd+=(--dangerously-skip-permissions)
reply=$(CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 timeout --kill-after=60 "$REVIEW_LIMIT" "${cmd[@]}" </dev/null)
rc=$?

exit_reason() {
  case $1 in
    124|137) echo "stalled or killed (exit $1), limit ${REVIEW_LIMIT}s" ;;
    125|126|127) echo "the review could not be launched (exit $1)" ;;
    *) echo "claude exited with $1" ;;
  esac
}

if [ "$(jq -r 'type' 2>/dev/null <<<"$reply")" = object ]; then
  session=$(jq -r '.session_id // empty' <<<"$reply")
  result=$(jq -r '.result // empty' <<<"$reply")
  [ -z "$result" ] || printf '%s\n' "$result"
  # Read from the typed field alone, as chain.sh reads it, never from the report's prose.
  if [ "$(jq -r '.api_error // empty' <<<"$reply")" = usage_limit_reached ]; then
    detail=$(printf '%s\n' "$result" | tr -d '\r' | sed -e 's/[[:space:]]*$//' -e '/^$/d' | tail -n 1)
    if [ -n "$detail" ]; then
      review_fail "the Claude usage limit was reached — $detail" "$USAGE_LIMIT_EXIT"
    fi
    review_fail "the Claude usage limit was reached; the reply gave no reset time" "$USAGE_LIMIT_EXIT"
  fi
  [ "$rc" = 0 ] || review_fail "$(exit_reason "$rc")"
  [ "$(jq -r '.is_error // false' <<<"$reply")" != true ] \
    || review_fail "claude reported an error$(s=$(jq -r '.subtype // empty' <<<"$reply"); [ -z "$s" ] || echo " ($s)")"
else
  [ "$rc" != 0 ] || { printf '%s\n' "$reply" >&2; review_fail "reply was not a JSON object (raw reply above)"; }
  review_fail "$(exit_reason "$rc")"
fi

if [ "$review_dry_run" = 1 ]; then
  echo "chain-local: done — $pr reviewed as a dry run; nothing was posted"
  exit 0
fi

after=$(review_count "$head") || review_fail "gh could not read the pull request's reviews after the review"
[ "$after" -gt "$before" ] \
  || review_fail "the review finished but no new review by $me, submitted on commit ${head:0:7} and carrying the $MARKER marker and the Risk tier line, is on the pull request"
echo "chain-local: done — $pr reviewed"
exit 0
