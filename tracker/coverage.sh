#!/usr/bin/env bash
#
# coverage.sh — does an interface file cover every tracker operation?
#
#   bash coverage.sh [<interface file>]   check the file; TRACKER.md beside this script by default
#   bash coverage.sh --list               print the operations, one per line
#
# The list of operations below is the interface: every command that reaches the issue tracker
# performs one of them, as the interface file it loads says how (docs/tracker.md states each one's
# arguments, output and outcome). An interface file covers an operation with a markdown heading, of
# any level, whose text is the operation's name alone — `### view`, or with the name in backticks —
# and something under it before the next heading. None is optional: a missing heading, an empty
# section, or a section that says the operation is unsupported, not supported or not implemented
# fails the check.
#
# The check is static. It reads the file and reaches no tracker, so it says that every operation is
# written down, not that what is written works. Whoever replaces the plugin's interface file with
# one for another tracker runs it against that file after every update from upstream: an operation
# added upstream then fails here, before any command runs.
#
# OUTPUT. One line per fault — `missing: <operation>`, `empty: <operation>` or
# `unsupported: <operation>` — then a summary naming the file.
# EXIT. 0 when every operation is covered; 1 when one is not; 2 on bad usage or a file that cannot
# be read. Tests: coverage.tests.sh beside this file.

set -uo pipefail

OPERATIONS=(setup ref branch-ref view create body-set state-add state-remove comment-find
  comment-post comment-edit comment-delete link close pr-reference marker search-title)

usage() { echo "usage: bash coverage.sh [<interface file>] | --list" >&2; exit 2; }

[ $# -le 1 ] || usage
case "${1:-}" in
  --list) printf '%s\n' "${OPERATIONS[@]}"; exit 0 ;;
  -*) usage ;;
esac
FILE=${1:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/TRACKER.md"}
[ -f "$FILE" ] && [ -r "$FILE" ] || { echo "coverage: cannot read the interface file $FILE" >&2; exit 2; }

HEADING='^#+[[:space:]]+(.*)$'

# section <operation> — the lines under the heading named for the operation, up to the next
# heading; fails where no heading names it. A line inside a code fence is never a heading.
section() {
  local op=$1 line name fence=0 inside=0 found=1
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      '```'*|'~~~'*) fence=$((1 - fence)) ;;
      *)
        if [ "$fence" = 0 ] && [[ $line =~ $HEADING ]]; then
          name=${BASH_REMATCH[1]//\`/}
          name=${name%"${name##*[![:space:]]}"}
          if [ "$name" = "$op" ]; then inside=1; found=0; else inside=0; fi
          continue
        fi ;;
    esac
    [ "$inside" = 0 ] || printf '%s\n' "$line"
  done < "$FILE"
  return "$found"
}

faults=0
for op in "${OPERATIONS[@]}"; do
  if ! text=$(section "$op"); then
    echo "missing: $op"; faults=$((faults + 1))
  elif ! grep -q '[^[:space:]]' <<<"$text"; then
    echo "empty: $op"; faults=$((faults + 1))
  elif grep -qiE 'unsupported|not supported|not implemented' <<<"$text"; then
    echo "unsupported: $op"; faults=$((faults + 1))
  fi
done

if [ "$faults" = 0 ]; then
  echo "coverage: $FILE covers all ${#OPERATIONS[@]} operations"
  exit 0
fi
echo "coverage: $FILE does not cover $faults of the ${#OPERATIONS[@]} operations"
exit 1
