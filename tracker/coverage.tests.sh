#!/usr/bin/env bash
#
# coverage.tests.sh — standalone test matrix for coverage.sh, and for the interface file it checks.
#
# coverage.sh holds the list of tracker operations and checks that an interface file covers every
# one. This matrix specifies what counts as covering — a heading named for the operation, with
# something under it, not marked unsupported — on throwaway files under a mktemp sandbox, and then
# holds the plugin's own interface file, TRACKER.md, to the check and to its size limit: it is read
# on every run of every command that reaches the tracker. Exits non-zero on any failure.
#
#   Usage:  bash tracker/coverage.tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COVERAGE="$HERE/coverage.sh"
INTERFACE="$HERE/TRACKER.md"
WORD_LIMIT=1000

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

PASS=0; FAIL=0
ok() { if eval "$2"; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 -- rc=${RC:-} output:[${OUT:-}]"; fi; }
# check <args…> — run the check. Sets OUT (stdout and stderr) and RC.
check() { OUT=$(bash "$COVERAGE" "$@" 2>&1); RC=$?; }

OPS=$(bash "$COVERAGE" --list 2>/dev/null)

# full <file> — an interface file with a heading and one line for every operation.
full() {
  local op
  { echo "# An interface file"; echo; echo "Some preamble."; echo
    while IFS= read -r op; do printf '### %s\n\nHow to perform %s here.\n\n' "$op" "$op"; done <<<"$OPS"
  } > "$1"
}
# without <op> <from> <to> — the file with that operation's heading line removed.
without() { grep -vx -- "### $1" "$2" > "$3"; }

echo "The operation list:"
check --list
ok "--list prints the operations, one per line" '[ "$RC" = 0 ] && [ "$(grep -c "" <<<"$OUT")" -ge 17 ]'
for op in setup ref branch-ref view create body-set state-add state-remove comment-find comment-post comment-edit comment-delete link close pr-reference marker search-title; do
  ok "$op is an operation" 'grep -qx -- "$op" <<<"$OPS"'
done
ok "no operation is listed twice" '[ -z "$(sort <<<"$OPS" | uniq -d)" ]'

echo "An interface file that covers every operation:"
full "$SB/full.md"
check "$SB/full.md"
ok "passes, at a path the caller names" '[ "$RC" = 0 ]'
ok "and says which file it checked" 'grep -qF "$SB/full.md" <<<"$OUT"'
sed 's/^### \(.*\)$/## `\1`/' "$SB/full.md" > "$SB/ticked.md"
check "$SB/ticked.md"
ok "a heading of any level, its name in backticks or not, names its operation" '[ "$RC" = 0 ]'
mkdir -p "$SB/a fork/tracker"
cp "$SB/full.md" "$SB/a fork/tracker/TRACKER.md"
check "$SB/a fork/tracker/TRACKER.md"
ok "a path with a space in it is read whole" '[ "$RC" = 0 ]'

echo "An interface file that omits an operation fails, naming it:"
while IFS= read -r op; do
  without "$op" "$SB/full.md" "$SB/missing.md"
  check "$SB/missing.md"
  ok "without $op" '[ "$RC" = 1 ] && grep -qx -- "missing: $op" <<<"$OUT" && [ "$(grep -c "^missing: " <<<"$OUT")" = 1 ]'
done <<<"$OPS"
without view "$SB/full.md" "$SB/two.md"; without close "$SB/two.md" "$SB/two2.md"
check "$SB/two2.md"
ok "every omitted operation is named, not the first alone" '[ "$RC" = 1 ] && grep -qx "missing: view" <<<"$OUT" && grep -qx "missing: close" <<<"$OUT"'
sed 's/^### view$/### view <ref>/' "$SB/full.md" > "$SB/args.md"
check "$SB/args.md"
ok "a heading that is not the operation's name alone does not name it" '[ "$RC" = 1 ] && grep -qx "missing: view" <<<"$OUT"'
{ without link "$SB/full.md" /dev/stdout; printf '```\n### link\n```\n'; } > "$SB/fenced.md"
check "$SB/fenced.md"
ok "nor does a heading inside a code fence" '[ "$RC" = 1 ] && grep -qx "missing: link" <<<"$OUT"'
: > "$SB/empty.md"
check "$SB/empty.md"
ok "an empty file is missing every operation" '[ "$RC" = 1 ] && [ "$(grep -c "^missing: " <<<"$OUT")" = "$(grep -c "" <<<"$OPS")" ]'

echo "No operation is optional:"
sed '/^How to perform comment-delete here\.$/d' "$SB/full.md" > "$SB/bare.md"
check "$SB/bare.md"
ok "a heading with nothing under it fails, naming the operation" '[ "$RC" = 1 ] && grep -qx "empty: comment-delete" <<<"$OUT"'
for words in "Unsupported on this tracker." "This tracker does not support it: not supported." "Not implemented."; do
  sed "s/^How to perform comment-delete here\\.\$/$words/" "$SB/full.md" > "$SB/unsupported.md"
  check "$SB/unsupported.md"
  ok "an operation marked '$words' fails, naming it" '[ "$RC" = 1 ] && grep -qx "unsupported: comment-delete" <<<"$OUT"'
done

echo "Usage:"
check "$SB/no-such.md"
ok "a file that does not exist is a usage error, not a pass" '[ "$RC" = 2 ] && grep -qF "no-such.md" <<<"$OUT"'
check "$SB/full.md" extra
ok "so is more than one file" '[ "$RC" = 2 ]'

echo "The plugin's own interface file:"
check
ok "with no argument the check reads TRACKER.md beside it, which covers every operation" '[ "$RC" = 0 ] && grep -qF "$INTERFACE" <<<"$OUT"'
check "$INTERFACE"
ok "and passes when named" '[ "$RC" = 0 ]'
WORDS=$(wc -w < "$INTERFACE" 2>/dev/null | tr -d ' ')
ok "is at most $WORD_LIMIT words (it is ${WORDS:-missing})" '[ -n "$WORDS" ] && [ "$WORDS" -le "$WORD_LIMIT" ]'
ok "names no tracker setting and no adapter" '[ -f "$INTERFACE" ] && [ "$(grep -ciE "adapter|\"tracker\"" "$INTERFACE")" = 0 ]'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
