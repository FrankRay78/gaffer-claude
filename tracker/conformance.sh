#!/usr/bin/env bash
#
# conformance.sh — does an adapter meet the tracker contract (docs/tracker.md)?
#
#   bash conformance.sh
#
# Run from the root of a repository whose settings name the adapter under test — GAFFER_SETTINGS,
# else .gaffer/chain.json, as tracker.sh reads them — against a tracker it may write to: it creates
# two issues, comments on them, sets every state, links them and closes both. Every operation is
# reached through tracker.sh, so what is checked is what a command would see. Prints one line per
# operation — `met: <op>`, `not met: <op> — <why>` or, for an optional one the adapter leaves out,
# `not implemented (optional): <op>` — then a summary, and exits 0 only when every required
# operation is met.
#
# What it cannot check is the tracker's own side: that a state shows where people look, or that a
# link is visible. Those are for the adapter's author to look at once.

set -uo pipefail

TRACKER="bash $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tracker.sh"
WORK=$(mktemp -d) || { echo "conformance: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# One file per operation under $WORK/result: a failure overwrites a pass, never the reverse.
mkdir -p "$WORK/result"
met() { [ -f "$WORK/result/$1" ] || echo met > "$WORK/result/$1"; }
not_met() { echo "not met — $2" > "$WORK/result/$1"; }
result() { cat "$WORK/result/$1" 2>/dev/null || echo "not met — not checked"; }
t() { $TRACKER "$@"; }
# json_has <json> <jq test> — the output is one JSON value passing the test.
json_has() { jq -e "$2" >/dev/null 2>&1 <<<"$1"; }

ops=$(t operations) || { echo "conformance: tracker.sh could not name the adapter's operations; see above." >&2; exit 1; }
echo "conformance: tracker $(jq -r .tracker <<<"$ops"), settings $(jq -r '.settings // "none"' <<<"$ops")"
REQUIRED=($(jq -r '.required[]' <<<"$ops"))
OPTIONAL=($(jq -r '.optional[]' <<<"$ops"))
has() { jq -e --arg o "$1" '.implemented | index($o) != null' >/dev/null <<<"$ops"; }
for op in "${REQUIRED[@]}"; do has "$op" || not_met "$op" "the adapter does not implement it"; done

STATES=(needs-answers ready parked audit)
printf 'Body with `code`, a $dollar, a | pipe and a "quote".\n\nSecond paragraph.\n' > "$WORK/body"
printf 'Replaced body: `x` $y \\ z.\n' > "$WORK/body2"

# setup, twice: the second run finds every state present.
if out=$(t setup); then
  if out2=$(t setup) && ! grep -q '^added:' <<<"$out2"; then met setup; else not_met setup "a second run added something, or failed: $out2"; fi
else
  not_met setup "it failed: $out"
fi

# create
A=; B=
if out=$(t create --title "Conformance A" --body-file "$WORK/body" --state audit) && json_has "$out" '(.ref | type) == "string" and (.url | type) == "string"'; then
  A=$(jq -r .ref <<<"$out"); met create
else
  not_met create "no {ref, url} for a new issue: $out"
fi
if out=$(t create --title "Conformance B" --body-file "$WORK/body"); then B=$(jq -r '.ref // empty' <<<"$out"); fi
[ -n "$A" ] && [ -n "$B" ] || { echo "conformance: no issue could be created, so nothing else can be checked." >&2; exit 1; }

# ref: a created issue's reference is recognised, normalises to itself, and has its two forms.
out=$(t ref --forms "$A" 2>/dev/null)
if [ "$(t ref "$A" 2>/dev/null)" != "$A" ]; then
  not_met ref "the reference create returned does not normalise to itself"
elif ! json_has "$out" '(.ref | type) == "string" and (.branch | type) == "string" and (.branch | test("^[A-Za-z0-9._-]+$")) and (.mention | type) == "string" and (.mention | length) > 0'; then
  not_met ref "ref --forms gave no {ref, branch, mention} with a branch-safe branch: $out"
elif t ref '' >/dev/null 2>&1 || t ref 'not a reference' >/dev/null 2>&1; then
  not_met ref "an empty reference, or one with spaces, was accepted"
else
  met ref
fi

# view
out=$(t view "$A")
if json_has "$out" '(.ref | type) == "string" and .title == "Conformance A" and (.body | type) == "string" and .state == "open"
    and (.states | type) == "array" and (.labels | type) == "array" and (.links | type) == "array" and (.comments | type) == "array"
    and (.states | index("audit")) != null'; then
  if [ "$(jq -r .body <<<"$out" | sed -e 's/[[:space:]]*$//')" = "$(sed -e 's/[[:space:]]*$//' "$WORK/body")" ]; then met view; else not_met view "the body read back is not the body written"; fi
else
  not_met view "the issue read back lacks a field, or the state create set: $out"
fi

# body-set
if t body-set "$A" "$WORK/body2" >/dev/null && [ "$(t view "$A" | jq -r .body | sed -e 's/[[:space:]]*$//')" = "$(sed -e 's/[[:space:]]*$//' "$WORK/body2")" ]; then
  met body-set
else
  not_met body-set "the replaced body did not read back byte for byte"
fi

# state-add and state-remove, for every state; and a name outside the list is refused.
for s in "${STATES[@]}"; do
  if t state-add "$B" "$s" && t view "$B" | jq -e --arg s "$s" '.states | index($s) != null' >/dev/null; then met state-add; else not_met state-add "the $s state did not read back after it was added"; fi
  if t state-remove "$B" "$s" && t view "$B" | jq -e --arg s "$s" '.states | index($s) == null' >/dev/null; then met state-remove; else not_met state-remove "the $s state still read back after it was removed"; fi
done
if t state-add "$B" not-a-state >/dev/null 2>&1; then not_met state-add "a state outside the contract was accepted"; fi

# marker
review=$(t marker review); decided=$(t marker confirmed-decisions); rpr=$(t marker review-pr)
if [ -n "$review" ] && [ -n "$decided" ] && [ "$review" != "$decided" ] && [ "$rpr" = '<!-- review-pr -->' ] \
  && [ "$(grep -c '' <<<"$review$decided")" -le 1 ]; then
  met marker
else
  not_met marker "the markers are not three non-empty single lines, review and confirmed-decisions distinct, review-pr GitHub's"
fi

# comment-post, comment-find, comment-edit: the newest marker comment is the one found.
printf 'First review.\n%s\n' "$review" > "$WORK/c1"
printf 'Second review.\n%s\n' "$review" > "$WORK/c2"
printf 'Second review, edited.\n%s\n' "$review" > "$WORK/c3"
printf 'An ordinary comment.\n' > "$WORK/c0"
if [ "$(t comment-find "$A" review)" != null ]; then not_met comment-find "an issue with no marker comment found one"; fi
c1=$(t comment-post "$A" "$WORK/c1" | jq -r '.id // empty')
t comment-post "$A" "$WORK/c0" >/dev/null
sleep 1
c2=$(t comment-post "$A" "$WORK/c2" | jq -r '.id // empty')
if [ -n "$c1" ] && [ -n "$c2" ] && [ "$c1" != "$c2" ]; then met comment-post; else not_met comment-post "posting gave no {id, url}, or two posts the same id"; fi
found=$(t comment-find "$A" review)
if [ "$(jq -r '.id' <<<"$found")" = "$c2" ] && json_has "$found" '(.body | type) == "string" and (.created_at | type) == "string"'; then met comment-find; else not_met comment-find "the newest marker comment was not the one found: $found"; fi
if t comment-edit "$A" "$c2" "$WORK/c3" >/dev/null && t comment-find "$A" review | jq -e '.body | startswith("Second review, edited.")' >/dev/null; then met comment-edit; else not_met comment-edit "the edited body did not read back"; fi

# comment-delete, optional
if has comment-delete; then
  if t comment-delete "$A" "$c2" && [ "$(t comment-find "$A" review | jq -r .id)" = "$c1" ]; then met comment-delete; else not_met comment-delete "after deleting the newest marker comment, the older one was not the one found"; fi
fi

# link
if t link "$A" "$B" >/dev/null; then met link; else not_met link "it failed"; fi

# pr-reference: an open issue is linked with a line to write; a closed one is not.
out=$(t pr-reference "$A")
if ! json_has "$out" '.outcome == "linked" and (.line | type) == "string" and (.line | length) > 0'; then
  not_met pr-reference "an open issue was not linked: $out"
fi

# close
printf 'Closed by the conformance suite.\n' > "$WORK/note"
if t close "$A" "$WORK/note" >/dev/null && t view "$A" | jq -e '.state == "closed"' >/dev/null; then met close; else not_met close "the issue did not read back closed"; fi
t close "$B" "$WORK/note" >/dev/null
out=$(t pr-reference "$A")
if json_has "$out" '.outcome == "none" and (.reason | type) == "string"'; then met pr-reference; else not_met pr-reference "a closed issue was not refused: $out"; fi

# search-title, optional
if has search-title; then
  if t search-title "Conformance A" | jq -e --arg a "$A" 'type == "array" and any(.[]; .ref == $a and .title == "Conformance A")' >/dev/null; then met search-title; else not_met search-title "the issue was not found by its title"; fi
fi

failed=0
for op in "${REQUIRED[@]}"; do
  r=$(result "$op")
  case $r in met) ;; *) failed=$((failed + 1)) ;; esac
  case $r in met) echo "met: $op" ;; *) echo "not met: $op — ${r#not met — }" ;; esac
done
for op in "${OPTIONAL[@]}"; do
  if ! has "$op"; then echo "not implemented (optional): $op"; continue; fi
  r=$(result "$op")
  case $r in met) echo "met: $op" ;; *) failed=$((failed + 1)); echo "not met: $op — ${r#not met — }" ;; esac
done
if [ "$failed" = 0 ]; then echo "conformance: every operation the adapter implements is met"; exit 0; fi
echo "conformance: $failed operation(s) not met"
exit 1
