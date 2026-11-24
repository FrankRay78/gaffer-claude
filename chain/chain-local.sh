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
# WHY A WRAPPER. review-pr writes no verdict: it posts a review and reports. Where a repository's CI
# runs it on a pull request marked ready, the chain must not run it too, so it stays out of
# chain.sh and out of the runner. What stands in for a verdict here is the post-condition
# docs/unattended.md states for it: one more review marked `<!-- review-pr -->` on the pull request
# than before the stage started. A stage that exits 0 having posted nothing is a failure.
#
# WHAT IT LEAVES. A chain failure is the chain's own: its output, its closing lines and its exit
# code — 75 for the usage limit, 78 for a configuration fault — pass through untouched, and no
# review runs. A review failure leaves the pull request open, as the chain raised it; the closing
# line names the pull request and the session to reopen, and the exit codes keep the chain's
# meanings. This script writes nothing itself; only the review stage posts.
#
# Usage: chain-local.sh [--dry-run] [--review-dry-run] [--skip-permissions] [--settings <file>] <issue>
#   Every option but --review-dry-run is chain.sh's and is passed to it. --review-dry-run runs the
#   review with --dry-run, so it prints what it would post and posts nothing. --skip-permissions
#   applies to the review stage too. The review runs on CHAIN_MODEL, else opus, at high effort,
#   within CHAIN_STAGE_TIMEOUT seconds, else 2h. Tests: chain-local.tests.sh beside this file.

set -uo pipefail

CHAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$CHAIN_DIR/.." && pwd)"
CHAIN="$CHAIN_DIR/chain.sh"

# review-pr is a multi-pass review with a verification pass, the shape the chain's verify and
# pre-review stages have, so it takes their limit, model and effort.
REVIEW_LIMIT=${CHAIN_STAGE_TIMEOUT:-7200}
REVIEW_MODEL=${CHAIN_MODEL:-opus}
REVIEW_EFFORT=high
# The chain's own exit codes, kept for the review stage so a caller reads one set of meanings.
USAGE_LIMIT_EXIT=75
MARKER='<!-- review-pr -->'

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

# Report mode: the chain's own listing, then the stage this script adds. The chain refuses bad
# arguments here as it does on a real run, and its exit code is returned unchanged.
if [ "$dry_run" = 1 ]; then
  bash "$CHAIN" "${chain_args[@]}"
  rc=$?
  [ "$rc" = 0 ] || exit "$rc"
  echo "  then review-pr: $(review_prompt '<the pull request raise-pr opens>')"
  [ "$review_dry_run" = 0 ] || echo "  review: dry run, nothing posted"
  exit 0
fi

# The chain's output is shown as it runs and kept, because its last line names the pull request.
# The chain redirects every stage's stdin itself, so nothing here can reach a stage's terminal.
log=$(mktemp)
trap 'rm -f "$log"' EXIT
bash "$CHAIN" "${chain_args[@]}" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
[ "$rc" = 0 ] || exit "$rc"

# Read from the chain's closing line alone, the line its own matrix pins, and held to the pull
# request shape so nothing else on that line is reviewed.
pr=$(tail -n 1 "$log" | sed -n 's/^chain: done — //p')
if ! [[ $pr =~ ^https://[^[:space:]]+/pull/[0-9]+$ ]]; then
  echo "chain-local: FAILED — the chain succeeded but its closing line names no pull request; no review ran."
  exit 1
fi

# review_count — how many reviews on the pull request carry the marker. Fails closed: a gh error
# or an answer that is not a number is no count.
review_count() {
  local n
  n=$(gh pr view "$pr" --json reviews --jq "[.reviews[] | select(.body | startswith(\"$MARKER\"))] | length" 2>/dev/null) || return 1
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  echo "$n"
}

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

before=0
if [ "$review_dry_run" = 0 ]; then
  before=$(review_count) || review_fail "gh could not read the pull request's reviews before the review started"
fi

prompt=$(review_prompt "$pr")
echo "chain-local: review-pr — starting"
# As chain.sh runs a stage: the prompt as the one positional after -p, stdin closed, the
# background-agent ceiling lifted so review-pr's parallel passes finish, and the time limit as the
# stall detector.
cmd=(claude -p "$prompt" --plugin-dir "$PLUGIN_ROOT" --model "$REVIEW_MODEL" --effort "$REVIEW_EFFORT" --output-format json)
[ "$skip_permissions" = 0 ] || cmd+=(--dangerously-skip-permissions)
reply=$(CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 timeout --kill-after=60 "$REVIEW_LIMIT" "${cmd[@]}" </dev/null)
rc=$?

if [ "$(jq -r 'type' 2>/dev/null <<<"$reply")" = object ]; then
  session=$(jq -r '.session_id // empty' <<<"$reply")
  result=$(jq -r '.result // empty' <<<"$reply")
  [ -z "$result" ] || printf '%s\n' "$result"
  # Read from the typed field alone, as chain.sh reads it, never from the report's prose.
  if [ "$(jq -r '.api_error // empty' <<<"$reply")" = usage_limit_reached ]; then
    review_fail "the Claude usage limit was reached — $(printf '%s\n' "$result" | tr -d '\r' | sed -e 's/[[:space:]]*$//' -e '/^$/d' | tail -n 1)" "$USAGE_LIMIT_EXIT"
  fi
  case $rc in
    0) ;;
    124|137) review_fail "stalled or killed (exit $rc), limit ${REVIEW_LIMIT}s" ;;
    *) review_fail "claude exited with $rc" ;;
  esac
  [ "$(jq -r '.is_error // false' <<<"$reply")" != true ] \
    || review_fail "claude reported an error$(s=$(jq -r '.subtype // empty' <<<"$reply"); [ -z "$s" ] || echo " ($s)")"
else
  case $rc in
    0) printf '%s\n' "$reply" >&2; review_fail "reply was not a JSON object (raw reply above)" ;;
    124|137) review_fail "stalled or killed (exit $rc), limit ${REVIEW_LIMIT}s" ;;
    *) review_fail "claude exited with $rc" ;;
  esac
fi

if [ "$review_dry_run" = 1 ]; then
  echo "chain-local: done — $pr reviewed as a dry run; nothing was posted"
  exit 0
fi

# The post-condition, checked on GitHub rather than taken from the report.
after=$(review_count) || review_fail "gh could not read the pull request's reviews after the review"
[ "$after" -gt "$before" ] || review_fail "the review finished but posted no review marked $MARKER"
echo "chain-local: done — $pr reviewed"
exit 0
