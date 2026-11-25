#!/usr/bin/env bash
#
# tracker.sh — the one way the commands and the chain reach the issue tracker.
#
#   bash tracker.sh <operation> [arguments…]
#
# Reads which tracker the repository uses from the `tracker` key of its settings file — the file
# GAFFER_SETTINGS names, else .gaffer/chain.json at the root of the repository it runs in; with no
# file or no key it is `github` — checks the operation and its state or marker names against the
# contract, and hands the call to adapters/<tracker>.sh beside this file. docs/tracker.md is the
# contract: every operation, its arguments, its output and its exit codes.
#
# Three operations are the dispatcher's own and reach no tracker: `require` (do the adapter and
# the setting serve these operations?), `operations` (what the adapter implements) and `branch-ref`
# (the issue reference a branch name carries, found with the adapter's own `ref`).
#
# EXIT. 0 success; 1 the operation failed, or a reference is not one the tracker recognises; 2 bad
# usage, including a state or marker name outside the contract's closed lists; 3 the adapter does
# not implement the operation; 78 the setting names no usable adapter. On 2, 3 and 78 nothing has
# reached the tracker. Tests: tracker.tests.sh beside this file, and conformance.sh for an adapter.

set -uo pipefail

TRACKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REQUIRED_OPS=(setup ref view create body-set state-add state-remove comment-find comment-post comment-edit link close pr-reference marker)
OPTIONAL_OPS=(comment-delete search-title)
STATES=(needs-answers ready parked audit)
MARKERS=(review confirmed-decisions review-pr)
CONFIG_EXIT=78

usage() {
  echo "usage: bash tracker.sh <operation> [arguments…]" >&2
  echo "  operations: ${REQUIRED_OPS[*]} ${OPTIONAL_OPS[*]} require operations branch-ref" >&2
  echo "  docs/tracker.md states each one's arguments and output" >&2
  exit 2
}

in_list() { local x=$1; shift; local y; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }
joined() { printf '%s, ' "$@" | sed 's/, $//'; }

[ $# -ge 1 ] || usage
OP=$1; shift

# The settings file and the tracker it names. The file is located once and passed to the adapter,
# so the two never read different files.
if [ -n "${GAFFER_SETTINGS:-}" ]; then
  SETTINGS=$GAFFER_SETTINGS
else
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$PWD
  SETTINGS="$root/.gaffer/chain.json"
  [ -f "$SETTINGS" ] || SETTINGS=
fi

refused() {
  echo "tracker: refused '$OP' — $1; nothing was changed." >&2
  exit "$CONFIG_EXIT"
}

TRACKER=github
if [ -n "$SETTINGS" ]; then
  [ -f "$SETTINGS" ] || refused "the settings file $SETTINGS (GAFFER_SETTINGS) does not exist"
  command -v jq >/dev/null 2>&1 || refused "jq is not on PATH, so the setting \"tracker\" in $SETTINGS cannot be read"
  TRACKER=$(jq -e -r 'if type != "object" then error("x") elif .tracker == null then "github" elif (.tracker | type) == "string" then .tracker else error("x") end' "$SETTINGS" 2>/dev/null) \
    || refused "the setting \"tracker\" in $SETTINGS is not a string, or the file is not a JSON object"
fi
SETTING_NAME="the setting \"tracker\" (${SETTINGS:-no settings file, so the default}) names \"$TRACKER\""
[[ $TRACKER =~ ^[a-z][a-z0-9-]*$ ]] || refused "$SETTING_NAME, which is not an adapter name"
ADAPTER="$TRACKER_DIR/adapters/$TRACKER.sh"
[ -f "$ADAPTER" ] || refused "$SETTING_NAME, which has no adapter (no $ADAPTER)"

export TRACKER_SETTINGS=$SETTINGS
adapter() { bash "$ADAPTER" "$@"; }

implemented() {
  local list
  list=$(adapter operations 2>/dev/null) || refused "$SETTING_NAME, whose adapter cannot list its operations"
  printf '%s\n' "$list"
}

# check_op <op> — the operation is in the contract and the adapter implements it.
check_op() {
  local op=$1
  in_list "$op" "${REQUIRED_OPS[@]}" "${OPTIONAL_OPS[@]}" || { echo "tracker: '$op' is not an operation of the tracker contract" >&2; exit 2; }
  if ! grep -qxF -- "$op" <<<"$IMPLEMENTED"; then
    echo "tracker: refused '$op' — $SETTING_NAME, whose adapter does not implement '$op'; nothing was changed." >&2
    exit 3
  fi
}

check_state() { in_list "$1" "${STATES[@]}" || { echo "tracker: '$1' is not a state; the states are $(joined "${STATES[@]}")" >&2; exit 2; }; }

case "$OP" in
  -h|--help) usage ;;
  require)
    [ $# -ge 1 ] || usage
    IMPLEMENTED=$(implemented)
    for op in "$@"; do check_op "$op"; done
    exit 0 ;;
  operations)
    IMPLEMENTED=$(implemented)
    jq -n --arg t "$TRACKER" --arg s "$SETTINGS" --arg impl "$IMPLEMENTED" \
      --argjson req "$(printf '%s\n' "${REQUIRED_OPS[@]}" | jq -R . | jq -s .)" \
      --argjson opt "$(printf '%s\n' "${OPTIONAL_OPS[@]}" | jq -R . | jq -s .)" \
      '{tracker: $t, settings: (if $s == "" then null else $s end), required: $req, optional: $opt,
        implemented: ($impl | split("\n") | map(select(length > 0)))}'
    exit 0 ;;
  branch-ref)
    [ $# -eq 1 ] || usage
    IMPLEMENTED=$(implemented)
    check_op ref
    # <prefix>/<reference>-<slug>: the shortest run of hyphen-separated words after the prefix that
    # the tracker recognises, so a key that itself holds a hyphen (PROJ-12) is found whole and a
    # slug word with digits in it (net10) is never taken for one.
    case "$1" in */*) rest=${1#*/} ;; *) echo "tracker: the branch $1 has no <prefix>/ to read a reference after" >&2; exit 1 ;; esac
    IFS=- read -r -a words <<<"$rest"
    candidate=
    for ((i = 0; i < ${#words[@]} - 1; i++)); do
      candidate=${candidate:+$candidate-}${words[i]}
      if ref=$(adapter ref "$candidate" 2>/dev/null); then echo "$ref"; exit 0; fi
    done
    echo "tracker: the branch $1 carries no issue reference the $TRACKER tracker recognises" >&2
    exit 1 ;;
esac

IMPLEMENTED=$(implemented)
check_op "$OP"
case "$OP" in
  state-add|state-remove) [ $# -eq 2 ] || usage; check_state "$2" ;;
  marker) [ $# -eq 1 ] || usage
          in_list "$1" "${MARKERS[@]}" || { echo "tracker: '$1' is not a marker; the markers are $(joined "${MARKERS[@]}")" >&2; exit 2; } ;;
  create) args=("$@")
          for ((i = 0; i < ${#args[@]}; i++)); do
            [ "${args[i]}" != --state ] || { [ $((i + 1)) -lt ${#args[@]} ] || usage; check_state "${args[i+1]}"; }
          done ;;
esac
adapter "$OP" "$@"
