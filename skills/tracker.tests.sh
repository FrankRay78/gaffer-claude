#!/usr/bin/env bash
#
# tracker.tests.sh — the tracker skill's calls are made in the skill file and nowhere else.
#
# The calls are read from the shell fences of tracker/SKILL.md, so this file names no tracker of
# its own: replace the skill file and the test follows it. Each call is reduced to a pattern, and a
# command, default, template or script that matches one fails the run. chain/chain-next.sh and its
# matrix are exempt: the runner selects and parks issues itself. docs/ is not searched, because the
# docs name the calls on purpose, and nor is .github/, which is this repository's own CI and ships
# to no consuming repository. Run it after any edit to the skill file, a command or a script.
#
# What it does not hold: a label or a closing keyword written in a command, and a call written in
# another form than the skill file's. Those are held at review (docs/contributing.md).
#
#   Usage:  bash skills/tracker.tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SKILL="$HERE/tracker/SKILL.md"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# Where a tracker call may not appear, relative to a checkout's root.
GUARDED="commands defaults templates chain init hooks"

# calls <skill file> — every line inside a bash, sh or shell fence, one call a line.
calls() {
  awk '/^[[:space:]]*```(bash|sh|shell)([[:space:]].*)?$/ { fenced = 1; next } /^[[:space:]]*```/ { fenced = 0 } fenced' "$1" \
    | sed -e 's/^[[:space:]]*//' -e '/^$/d' -e '/^#/d'
}

# quote <text> — the text with every character an extended regular expression reads specially escaped.
quote() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }

# pattern <call> — the extended regular expression that finds the call elsewhere, or nothing where
# the call is too generic to look for. A call is known by its leading words, up to the first option,
# placeholder or quoted argument, when there are at least three (`tool issue view`). Fewer than
# three say too little (`tool api`), so the call is known by its path instead, each <placeholder>
# standing for any run of non-blank characters. A call with neither is not looked for.
pattern() {
  local -a words lead=()
  local w path=""
  read -r -a words <<<"$1"
  for w in "${words[@]}"; do
    case $w in -*|\"*|\'*|\>*|\$*|*\<*) break ;; esac
    lead+=("$w")
  done
  if [ "${#lead[@]}" -ge 3 ]; then
    quote "${lead[*]}" | sed 's/ /[[:space:]]+/g'
    return
  fi
  for w in "${words[@]}"; do
    case $w in */*\<*|*\<*/*) path=$w; break ;; esac
  done
  [ -n "$path" ] || return 0
  quote "$path" | sed -E 's/<[^>]*>/[^[:space:]]+/g'
}

# violations <root> <skill file> — every line under the guarded paths that makes one of the skill
# file's calls, as file:line:text.
violations() {
  local root=$1 skill=$2 d call pat
  local -a where=()
  for d in $GUARDED; do [ ! -e "$root/$d" ] || where+=("$d"); done
  [ "${#where[@]}" -gt 0 ] || return 0
  calls "$skill" | while IFS= read -r call; do
    pat=$(pattern "$call")
    [ -n "$pat" ] || continue
    (cd "$root" && grep -rnE --exclude=chain-next.sh --exclude=chain-next.tests.sh -e "$pat" "${where[@]}")
  done | sort -u
}

PASS=0; FAIL=0
ok() { if eval "$2"; then echo "  ok   $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi; }

# A made-up tracker, so the cases below prove the reading and the search without naming a real one.
FIX="$SB/fixture"
mkdir -p "$FIX/skills/tracker" "$FIX/commands" "$FIX/chain" "$FIX/docs"
cat > "$FIX/skills/tracker/SKILL.md" <<'SKILL'
# A made-up tracker

Inline, and so not read: `trk label make "<label>"`.

```bash
trk issue view <N> --json title,body
trk api --paginate things/<R>/issues/<N>/notes
jq -n --rawfile b <file> '{body: $b}' > <patch file>
```

```text
trk issue shown-as-text <N>
```
SKILL
FIXSKILL="$FIX/skills/tracker/SKILL.md"

echo "Reading the skill file's calls:"
ok "every line in a bash fence is a call, and nothing outside one is" '[ "$(calls "$FIXSKILL" | grep -c "")" = 3 ] && ! calls "$FIXSKILL" | grep -q "label make\|shown-as-text"'
ok "a call with three leading words is known by them" '[ "$(pattern "trk issue view <N> --json title,body")" = "trk[[:space:]]+issue[[:space:]]+view" ]'
ok "a call with fewer is known by its path, a placeholder standing for anything" '[ "$(pattern "trk api --paginate things/<R>/issues/<N>/notes")" = "things/[^[:space:]]+/issues/[^[:space:]]+/notes" ]'
ok "a call with neither is too generic to look for" '[ -z "$(pattern "jq -n --rawfile b <file> > <patch file>")" ]'

printf '```sh\ntrk issue one <N>\n```\n\n```shell title=x\ntrk issue two <N>\n```\n' > "$SB/fences.md"
ok "an sh or shell fence, or one with attributes, is read too" '[ "$(calls "$SB/fences.md" | grep -c "")" = 2 ]'

echo "Finding a call outside the skill file:"
ok "a tree that makes none passes" '[ -z "$(violations "$FIX" "$FIXSKILL")" ]'
printf 'Read it with `trk issue view 12`.\n' > "$FIX/commands/a.md"
ok "a command that makes a call is named, with its line" '[ "$(violations "$FIX" "$FIXSKILL")" = "commands/a.md:1:Read it with \`trk issue view 12\`." ]'
rm "$FIX/commands/a.md"
printf 'trk api things/o/r/issues/7/notes\n' > "$FIX/chain/chain.sh"
ok "a script that reaches the same path is named" 'violations "$FIX" "$FIXSKILL" | grep -q "^chain/chain.sh:1:"'
rm "$FIX/chain/chain.sh"
printf 'trk api things/o/r/reviews/7\njq -n --arg a b\ntrk issue list\n' > "$FIX/commands/b.md"
ok "another path of the same tool, a generic tool and a call the skill file does not make are no fault" '[ -z "$(violations "$FIX" "$FIXSKILL")" ]'
printf 'trk issue view "$n"\n' > "$FIX/chain/chain-next.sh"
printf 'trk issue view 12\n' > "$FIX/chain/chain-next.tests.sh"
ok "the runner and its matrix are exempt" '[ -z "$(violations "$FIX" "$FIXSKILL")" ]'
printf 'Allow `trk issue view`.\n' > "$FIX/docs/tracker.md"
ok "the docs are not searched" '[ -z "$(violations "$FIX" "$FIXSKILL")" ]'
printf '# A tracker reached another way\n\nCall the connector.\n' > "$FIX/skills/tracker/SKILL.md"
printf 'trk issue view 12\n' > "$FIX/commands/a.md"
ok "a skill file that makes no shell call leaves nothing to look for" '[ -z "$(calls "$FIXSKILL")" ] && [ -z "$(violations "$FIX" "$FIXSKILL")" ]'

echo "This checkout:"
ok "the skill file is there to read, and yields calls to look for" '[ -f "$SKILL" ] && [ -n "$(calls "$SKILL")" ]'
FOUND="$(violations "$ROOT" "$SKILL")"
ok "no command, default, template or script makes a call the skill file makes" '[ -z "$FOUND" ]'
[ -z "$FOUND" ] || printf '%s\n' "$FOUND" | sed 's/^/       /'
echo "  looked for:"
calls "$SKILL" | while IFS= read -r call; do
  pat=$(pattern "$call")
  if [ -n "$pat" ]; then echo "$pat"; else echo "(too generic to look for) $call"; fi
done | sort -u | sed 's/^/       /'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
