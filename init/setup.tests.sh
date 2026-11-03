#!/usr/bin/env bash
#
# setup.tests.sh — standalone test matrix for setup.sh.
#
# Every case runs setup.sh against a throwaway git repository under a mktemp sandbox, with a stub
# `gh` first on PATH, so nothing reaches GitHub and your checkout is never touched. Exits non-zero
# on any failure. Run it after any edit to setup.sh.
#
#   Usage:  bash init/setup.tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$HERE/setup.sh"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# The stub gh. Behaviour is driven by files in $STUB_DIR: auth-fail makes `gh auth status` fail,
# repo-fail makes `gh repo view` fail, default-branch holds the default branch name (main if
# absent), labels holds one existing label per line, and label-create-fail makes creation fail.
# Created labels are appended to labels, so a second run sees them.
mkdir -p "$SB/bin"
cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
{ for a in "$@"; do printf '%s|' "$a"; done; printf '\n'; } >> "$STUB_DIR/gh-log"
case "$1 $2" in
  "auth status") [ -f "$STUB_DIR/auth-fail" ] && exit 1; exit 0 ;;
  "repo view")   [ -f "$STUB_DIR/repo-fail" ] && { echo "no remote" >&2; exit 1; }
                 cat "$STUB_DIR/default-branch" 2>/dev/null || echo main ;;
  "label list")  [ -f "$STUB_DIR/labels" ] && cat "$STUB_DIR/labels"; exit 0 ;;
  "label create") [ -f "$STUB_DIR/label-create-fail" ] && exit 1; printf '%s\n' "$3" >> "$STUB_DIR/labels" ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$SB/bin/gh"
export PATH="$SB/bin:$PATH"

PASS=0; FAIL=0
ok() {
  if eval "$2"; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1"; echo "       output: $OUT"; fi
}

# A fresh repository with one commit on main, and a fresh stub state.
N=0
fresh() {
  N=$((N + 1))
  R="$SB/repo$N"; export STUB_DIR="$SB/stub$N"
  mkdir -p "$R" "$STUB_DIR"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@example.invalid
  git -C "$R" config user.name t
  echo "# project" > "$R/README.md"
  git -C "$R" add -A && git -C "$R" commit -qm init
}
run() { OUT=$(bash "$SETUP" "$@" 2>&1); RC=$?; }
snapshot() { (cd "$R" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum); }

echo "check:"
fresh; run check "$R";                         ok "clean default branch → ready" '[ $RC = 0 ] && [ "$OUT" = "ready: main" ]'
fresh; echo x > "$R/x"; run check "$R";        ok "untracked file → not ready" '[ $RC = 1 ] && grep -q "uncommitted" <<<"$OUT"'
fresh; echo y >> "$R/README.md"; run check "$R"; ok "modified file → not ready" '[ $RC = 1 ] && grep -q "uncommitted" <<<"$OUT"'
fresh; git -C "$R" switch -qc other; run check "$R"; ok "not on the default branch → not ready" '[ $RC = 1 ] && grep -q "not the default branch" <<<"$OUT"'
fresh; echo trunk > "$STUB_DIR/default-branch"; git -C "$R" branch -m trunk; run check "$R"; ok "default branch other than main → ready" '[ $RC = 0 ] && [ "$OUT" = "ready: trunk" ]'
fresh; touch "$STUB_DIR/auth-fail"; run check "$R"; ok "gh not signed in → not ready" '[ $RC = 1 ] && grep -q "not signed in" <<<"$OUT"'
fresh; touch "$STUB_DIR/repo-fail"; run check "$R"; ok "no GitHub repository → not ready" '[ $RC = 1 ] && grep -q "no GitHub repository" <<<"$OUT"'
fresh; mkdir "$R/sub"; run check "$R/sub";     ok "not the work-tree root → error" '[ $RC = 1 ] && grep -q "not the root" <<<"$OUT"'
fresh; run frobnicate "$R";                    ok "unknown mode → usage" '[ $RC = 2 ]'

echo "files, on a repository with nothing:"
fresh; run files "$R"
ok "exits 0" '[ $RC = 0 ]'
ok "gaffer marketplace added" 'jq -e ".extraKnownMarketplaces[\"gaffer-claude\"].source.repo == \"FrankRay78/gaffer-claude\"" "$R/.claude/settings.json" >/dev/null'
ok "gaffer enabled" 'jq -e ".enabledPlugins[\"gaffer@gaffer-claude\"] == true" "$R/.claude/settings.json" >/dev/null'
ok "pr-review-toolkit enabled" 'jq -e ".enabledPlugins[\"pr-review-toolkit@claude-plugins-official\"] == true" "$R/.claude/settings.json" >/dev/null'
ok "chmod ask rule added" 'jq -e ".permissions.ask | index(\"Bash(chmod:*)\")" "$R/.claude/settings.json" >/dev/null'
ok "scratch is git-ignored" 'git -C "$R" check-ignore -q .claude/scratch/anything'
ok "memory index created" '[ -f "$R/.claude/memory/MEMORY.md" ]'
ok "CLAUDE.md created importing the memory index" 'grep -qx "@.claude/memory/MEMORY.md" "$R/CLAUDE.md"'
ok "no CONVENTIONS.md → no import of it, and says so" '! grep -q CONVENTIONS "$R/CLAUDE.md" && grep -q "^skipped: CLAUDE.md import of CONVENTIONS.md" <<<"$OUT"'
ok "every change reported as added" '[ "$(grep -c "^added:" <<<"$OUT")" = 7 ] && ! grep -q "^present:" <<<"$OUT"'

echo "files, run twice:"
before=$(snapshot); run files "$R"
ok "second run changes no byte" '[ "$(snapshot)" = "$before" ]'
ok "second run reports everything present" '! grep -q "^added:" <<<"$OUT" && [ "$(grep -c "^present:" <<<"$OUT")" = 7 ]'

echo "files, preserving what is there:"
fresh; mkdir -p "$R/.claude"
cat > "$R/.claude/settings.json" <<'JSON'
{ "model": "opus", "enabledPlugins": { "gaffer@gaffer-claude": false, "other@x": true },
  "permissions": { "allow": ["Bash(ls:*)"], "ask": ["Bash(rm:*)"] } }
JSON
run files "$R"
ok "unrelated settings kept" 'jq -e ".model == \"opus\" and .enabledPlugins[\"other@x\"] == true and .permissions.allow == [\"Bash(ls:*)\"]" "$R/.claude/settings.json" >/dev/null'
ok "a plugin turned off stays off" 'jq -e ".enabledPlugins[\"gaffer@gaffer-claude\"] == false" "$R/.claude/settings.json" >/dev/null && grep -q "^present: .claude/settings.json plugin gaffer@gaffer-claude" <<<"$OUT"'
ok "ask rule appended after existing ones" 'jq -e ".permissions.ask == [\"Bash(rm:*)\", \"Bash(chmod:*)\"]" "$R/.claude/settings.json" >/dev/null'

fresh; mkdir -p "$R/.claude"; echo '[1,2' > "$R/.claude/settings.json"; before=$(snapshot); run files "$R"
ok "unreadable settings → error, nothing changed" '[ $RC = 1 ] && grep -q "not a JSON object" <<<"$OUT" && [ "$(snapshot)" = "$before" ]'

fresh; printf 'bin/' > "$R/.gitignore"; run files "$R"
ok "gitignore without a final newline gets one before the new line" '[ "$(cat "$R/.gitignore")" = "$(printf "bin/\n.claude/scratch/")" ]'

fresh; printf '.claude/\n' > "$R/.gitignore"; run files "$R"
ok "scratch already ignored by a wider rule → gitignore untouched" '[ "$(cat "$R/.gitignore")" = ".claude/" ] && grep -q "^present: .claude/scratch/ git-ignored" <<<"$OUT"'

fresh; printf '# Project\n\nSome context.' > "$R/CLAUDE.md"; echo "# Conventions" > "$R/CONVENTIONS.md"; run files "$R"
ok "existing CLAUDE.md content kept" '[ "$(head -3 "$R/CLAUDE.md")" = "$(printf "# Project\n\nSome context.")" ]'
ok "CONVENTIONS.md imported once it exists" 'grep -qx "@CONVENTIONS.md" "$R/CLAUDE.md"'
ok "memory index imported" 'grep -qx "@.claude/memory/MEMORY.md" "$R/CLAUDE.md"'

fresh; printf '@./CONVENTIONS.md\n# P\n@.claude/memory/MEMORY.md\n' > "$R/CLAUDE.md"; echo c > "$R/CONVENTIONS.md"; before=$(cat "$R/CLAUDE.md"); run files "$R"
ok "imports already present in either form → CLAUDE.md untouched" '[ "$(cat "$R/CLAUDE.md")" = "$before" ]'

fresh; mkdir -p "$R/.claude/memory"; echo "- [A](a.md) — b" > "$R/.claude/memory/MEMORY.md"; run files "$R"
ok "existing memory index kept" '[ "$(cat "$R/.claude/memory/MEMORY.md")" = "- [A](a.md) — b" ]'

echo "labels:"
fresh; printf 'bug\nready\n' > "$STUB_DIR/labels"; run labels "$R"
ok "creates only the missing labels" '[ $RC = 0 ] && grep -qx "added: label needs answers" <<<"$OUT" && grep -qx "added: label parked" <<<"$OUT" && grep -qx "present: label ready" <<<"$OUT"'
ok "each created label carries a description" '[ "$(grep -c "^label|create|.*|--description|.\+|$" "$STUB_DIR/gh-log")" = 2 ]'
run labels "$R"
ok "second run creates nothing" '! grep -q "^added:" <<<"$OUT" && [ "$(grep -c "^label|create" "$STUB_DIR/gh-log")" = 2 ]'
fresh; touch "$STUB_DIR/label-create-fail"; run labels "$R"
ok "gh failure → exit 1 naming the label" '[ $RC = 1 ] && grep -q "could not create label" <<<"$OUT"'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
