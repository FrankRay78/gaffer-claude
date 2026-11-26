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

# The identity setup.sh writes is the marketplace manifest's, so what the cases expect is read from
# the manifest too: this matrix names no marketplace of its own and passes unedited in a copy of
# the plugin published under another one. The repository is cut from the URL with sed, not with
# setup.sh's own expression, so the two are checked against each other.
MANIFEST="$HERE/../.claude-plugin/marketplace.json"
MKT=$(jq -r '.name' "$MANIFEST")
SLUG=$(jq -r '.plugins[0].repository' "$MANIFEST" | sed -E -e 's#^https://github\.com/##' -e 's#(\.git)?/?$##')
GAFFER="$(jq -r '.plugins[0].name' "$MANIFEST")@$MKT"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# The stub gh. Behaviour is driven by files in $STUB_DIR: auth-fail makes `gh auth status` fail,
# repo-fail makes `gh repo view` fail, and default-branch holds the default branch name (main if
# absent). Every call is logged, so a case can check the flags a call carried: the stub's replies
# assume them (a bare branch name), and a call that dropped one would get JSON from the real gh.
mkdir -p "$SB/bin"
cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
{ for a in "$@"; do printf '%s|' "$a"; done; printf '\n'; } >> "$STUB_DIR/gh-log"
case "$1 $2" in
  "auth status") [ -f "$STUB_DIR/auth-fail" ] && exit 1; exit 0 ;;
  "repo view")   [ -f "$STUB_DIR/repo-fail" ] && { echo "no remote" >&2; exit 1; }
                 cat "$STUB_DIR/default-branch" 2>/dev/null || echo main ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$SB/bin/gh"
export PATH="$SB/bin:$PATH"

# A PATH with everything setup.sh needs except jq, for the cases that check jq is required.
mkdir -p "$SB/nojq"
for t in bash git gh grep sed tail mktemp mv rm mkdir cat dirname env; do ln -s "$(command -v "$t")" "$SB/nojq/$t"; done
BASH_BIN=$(command -v bash)

PASS=0; FAIL=0
ok() {
  if eval "$2"; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1"; echo "       output: $OUT"; fi
}

# A fresh repository with one commit on main, pushed to a bare origin, and a fresh stub state.
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
  git init -q --bare "$SB/origin$N.git"
  git -C "$R" remote add origin "$SB/origin$N.git"
  git -C "$R" push -q -u origin main 2>/dev/null
}
run() { OUT=$(bash "$SETUP" "$@" 2>&1); RC=$?; }
snapshot() { (cd "$R" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum); }

echo "check:"
fresh; run check "$R";                         ok "clean default branch → ready" '[ $RC = 0 ] && [ "$OUT" = "ready: main" ]'
fresh; echo x > "$R/x"; run check "$R";        ok "untracked file → not ready" '[ $RC = 1 ] && grep -q "uncommitted" <<<"$OUT"'
fresh; echo y >> "$R/README.md"; run check "$R"; ok "modified file → not ready" '[ $RC = 1 ] && grep -q "uncommitted" <<<"$OUT"'
fresh; git -C "$R" switch -qc other; run check "$R"; ok "not on the default branch → not ready" '[ $RC = 1 ] && grep -q "not the default branch" <<<"$OUT"'
fresh; echo trunk > "$STUB_DIR/default-branch"; git -C "$R" branch -m trunk; git -C "$R" push -q origin trunk 2>/dev/null; run check "$R"; ok "default branch other than main → ready" '[ $RC = 0 ] && [ "$OUT" = "ready: trunk" ]'
fresh; touch "$STUB_DIR/auth-fail"; run check "$R"; ok "gh not signed in → not ready" '[ $RC = 1 ] && grep -q "not signed in" <<<"$OUT"'
fresh; touch "$STUB_DIR/repo-fail"; run check "$R"; ok "no GitHub repository → not ready" '[ $RC = 1 ] && grep -q "no GitHub repository" <<<"$OUT"'
fresh; mkdir "$R/sub"; run check "$R/sub";     ok "not the work-tree root → error" '[ $RC = 1 ] && grep -q "not the root" <<<"$OUT"'
mkdir -p "$SB/plain"; run files "$SB/plain";    ok "not a git repository → error" '[ $RC = 1 ] && grep -q "not a git repository" <<<"$OUT"'
fresh; run frobnicate "$R";                    ok "unknown mode → usage" '[ $RC = 2 ]'
fresh; git -C "$R" config status.showUntrackedFiles no; echo x > "$R/x"; run check "$R"
ok "untracked file hidden by status.showUntrackedFiles=no → still not ready" '[ $RC = 1 ] && grep -q "uncommitted" <<<"$OUT"'
fresh; echo z > "$R/z"; git -C "$R" add z; git -C "$R" commit -qm local; run check "$R"
ok "local commit not on origin → not ready" '[ $RC = 1 ] && grep -q "1 commit(s) not on origin/main" <<<"$OUT"'
fresh; git -C "$R" remote remove origin; run check "$R"
ok "no origin branch to compare with → not ready" '[ $RC = 1 ] && grep -q "no origin/main" <<<"$OUT"'
fresh; before=$(snapshot); OUT=$(PATH="$SB/nojq" "$BASH_BIN" "$SETUP" check "$R" 2>&1); RC=$?
ok "jq missing → not ready, before gh is asked anything" '[ $RC = 1 ] && grep -q "jq is not on the path" <<<"$OUT" && [ ! -s "$STUB_DIR/gh-log" ]'
ok "check changes nothing" '[ "$(snapshot)" = "$before" ]'
fresh; run check "$R"
ok "default branch is read as a bare name (--jq)" 'grep -qxF "repo|view|--json|defaultBranchRef|--jq|.defaultBranchRef.name|" "$STUB_DIR/gh-log"'

echo "files, on a repository with nothing:"
fresh; run files "$R"
ok "exits 0" '[ $RC = 0 ]'
ok "the manifest's marketplace added, from its GitHub repository" '[[ "$SLUG" =~ ^[^/]+/[^/]+$ ]] && jq -e --arg m "$MKT" --arg r "$SLUG" ".extraKnownMarketplaces[\$m] == {source: {source: \"github\", repo: \$r}}" "$R/.claude/settings.json" >/dev/null'
ok "the manifest's plugin enabled" 'jq -e --arg p "$GAFFER" ".enabledPlugins[\$p] == true" "$R/.claude/settings.json" >/dev/null'
ok "pr-review-toolkit enabled" 'jq -e ".enabledPlugins[\"pr-review-toolkit@claude-plugins-official\"] == true" "$R/.claude/settings.json" >/dev/null'
ok "chmod ask rule added" 'jq -e ".permissions.ask | index(\"Bash(chmod:*)\")" "$R/.claude/settings.json" >/dev/null'
ok "scratch is git-ignored" 'git -C "$R" check-ignore -q .claude/scratch/anything'
ok "memory index created" '[ -f "$R/.claude/memory/MEMORY.md" ]'
ok "CLAUDE.md created importing the memory index" 'grep -qx "@.claude/memory/MEMORY.md" "$R/CLAUDE.md"'
ok "no CONVENTIONS.md → no import of it, and says so" '! grep -q CONVENTIONS "$R/CLAUDE.md" && grep -q "^skipped: CLAUDE.md import of CONVENTIONS.md" <<<"$OUT"'
ok "no allow rule is written: what the tracker skill's calls need allowed is the repository's or the user's to grant" 'jq -e ".permissions.allow == null" "$R/.claude/settings.json" >/dev/null'
ok "every change reported as added" '[ "$(grep -c "^added:" <<<"$OUT")" = 7 ] && ! grep -q "^present:" <<<"$OUT"'

echo "files, run twice:"
before=$(snapshot); run files "$R"
ok "second run changes no byte" '[ "$(snapshot)" = "$before" ]'
ok "second run reports everything present" '! grep -q "^added:" <<<"$OUT" && [ "$(grep -c "^present:" <<<"$OUT")" = 7 ]'

echo "files, preserving what is there:"
fresh; mkdir -p "$R/.claude"
cat > "$R/.claude/settings.json" <<JSON
{ "model": "opus", "enabledPlugins": { "$GAFFER": false, "other@x": true },
  "permissions": { "allow": ["Bash(ls:*)"], "ask": ["Bash(rm:*)"] } }
JSON
run files "$R"
ok "unrelated settings kept" 'jq -e ".model == \"opus\" and .enabledPlugins[\"other@x\"] == true and .permissions.allow == [\"Bash(ls:*)\"]" "$R/.claude/settings.json" >/dev/null'
ok "a plugin turned off stays off" 'jq -e --arg p "$GAFFER" ".enabledPlugins[\$p] == false" "$R/.claude/settings.json" >/dev/null && grep -qxF "present: .claude/settings.json plugin $GAFFER" <<<"$OUT"'
ok "ask rule appended after existing ones" 'jq -e ".permissions.ask == [\"Bash(rm:*)\", \"Bash(chmod:*)\"]" "$R/.claude/settings.json" >/dev/null'

fresh; mkdir -p "$R/.claude"; echo '[1,2' > "$R/.claude/settings.json"; before=$(snapshot); run files "$R"
ok "unreadable settings → error, nothing changed" '[ $RC = 1 ] && grep -q "not a JSON object" <<<"$OUT" && [ "$(snapshot)" = "$before" ]'
fresh; mkdir -p "$R/.claude"; echo '[1,2]' > "$R/.claude/settings.json"; before=$(snapshot); run files "$R"
ok "settings that are JSON but not an object → error, nothing changed" '[ $RC = 1 ] && grep -q "not a JSON object" <<<"$OUT" && [ "$(snapshot)" = "$before" ]'
fresh; mkdir -p "$R/.claude"; jq -n --arg m "$MKT" '{extraKnownMarketplaces: {($m): {source: {source: "directory", path: "/x"}}}, permissions: {ask: ["Bash(rm:*)", "Bash(chmod:*)"]}}' > "$R/.claude/settings.json"; run files "$R"
ok "an existing entry for the marketplace is kept as it is" 'jq -e --arg m "$MKT" ".extraKnownMarketplaces[\$m] == {source: {source: \"directory\", path: \"/x\"}}" "$R/.claude/settings.json" >/dev/null'
ok "chmod rule already among other ask rules → not added again" 'jq -e ".permissions.ask == [\"Bash(rm:*)\", \"Bash(chmod:*)\"]" "$R/.claude/settings.json" >/dev/null'
fresh; before=$(snapshot); OUT=$(PATH="$SB/nojq" "$BASH_BIN" "$SETUP" files "$R" 2>&1); RC=$?
ok "jq missing → files refuses, nothing changed" '[ $RC = 1 ] && grep -q "jq is not on the path" <<<"$OUT" && [ "$(snapshot)" = "$before" ]'

fresh; printf 'bin/' > "$R/.gitignore"; run files "$R"
ok "gitignore without a final newline gets one before the new line" '[ "$(cat "$R/.gitignore")" = "$(printf "bin/\n.claude/scratch/")" ]'

fresh; printf '.claude/\n' > "$R/.gitignore"; run files "$R"
ok "scratch already ignored by a wider rule → gitignore untouched" '[ "$(cat "$R/.gitignore")" = ".claude/" ] && grep -q "^present: .claude/scratch/ git-ignored" <<<"$OUT"'
ok "files written under an ignored .claude/ are reported as ignored" 'grep -qx "ignored: .claude/settings.json" <<<"$OUT" && grep -qx "ignored: .claude/memory/MEMORY.md" <<<"$OUT"'
ok "a file that is not ignored is not reported as ignored" '! grep -q "^ignored: CLAUDE.md" <<<"$OUT"'
fresh; printf '.claude/\n' > "$R/.gitignore"; mkdir -p "$R/.claude"; echo '{}' > "$R/.claude/settings.json"
git -C "$R" add .gitignore && git -C "$R" add -f .claude/settings.json && git -C "$R" commit -qm tracked; run files "$R"
ok "a tracked file under an ignored .claude/ is not reported as ignored" '! grep -q "^ignored: .claude/settings.json" <<<"$OUT" && grep -qx "ignored: .claude/memory/MEMORY.md" <<<"$OUT"'
fresh; run files "$R"
ok "nothing ignored on a plain repository → no ignored lines" '! grep -q "^ignored:" <<<"$OUT"'

fresh; printf '# Project\n\nSome context.' > "$R/CLAUDE.md"; echo "# Conventions" > "$R/CONVENTIONS.md"; run files "$R"
ok "existing CLAUDE.md content kept" '[ "$(head -3 "$R/CLAUDE.md")" = "$(printf "# Project\n\nSome context.")" ]'
ok "CONVENTIONS.md imported once it exists" 'grep -qx "@CONVENTIONS.md" "$R/CLAUDE.md"'
ok "memory index imported" 'grep -qx "@.claude/memory/MEMORY.md" "$R/CLAUDE.md"'

fresh; printf '@./CONVENTIONS.md\n# P\n@.claude/memory/MEMORY.md\n' > "$R/CLAUDE.md"; echo c > "$R/CONVENTIONS.md"; before=$(cat "$R/CLAUDE.md"); run files "$R"
ok "imports already present in either form → CLAUDE.md untouched" '[ "$(cat "$R/CLAUDE.md")" = "$before" ]'

fresh; mkdir -p "$R/.claude/memory"; echo "- [A](a.md) — b" > "$R/.claude/memory/MEMORY.md"; run files "$R"
ok "existing memory index kept" '[ "$(cat "$R/.claude/memory/MEMORY.md")" = "- [A](a.md) — b" ]'

# A copy of the plugin is this checkout with another marketplace manifest and nothing else changed,
# so the copy here is setup.sh beside a manifest of its own. These cases fix their own identity, so
# they hold whichever checkout the matrix runs in.
NC=0
copy() { # copy [<manifest text>] — a plugin checkout at $C; with no argument it has no manifest
  NC=$((NC + 1)); C="$SB/copy$NC"
  mkdir -p "$C/init" "$C/.claude-plugin"
  cp "$SETUP" "$C/init/setup.sh"
  [ $# = 0 ] || printf '%s\n' "$1" > "$C/.claude-plugin/marketplace.json"
}
run_copy() { OUT=$(bash "$C/init/setup.sh" "$@" 2>&1); RC=$?; }

echo "files, run from a copy published under another marketplace:"
fresh; copy '{"name":"other-market","plugins":[{"name":"gaffer","source":"./","repository":"https://github.com/someone/other-repo"}]}'
run_copy files "$R"
ok "exits 0" '[ $RC = 0 ]'
ok "the copy's marketplace and repository are proposed, and no other marketplace" 'jq -e ".extraKnownMarketplaces == {\"other-market\": {source: {source: \"github\", repo: \"someone/other-repo\"}}}" "$R/.claude/settings.json" >/dev/null'
ok "the copy's plugin id is enabled, and no other gaffer" 'jq -e ".enabledPlugins == {\"gaffer@other-market\": true, \"pr-review-toolkit@claude-plugins-official\": true}" "$R/.claude/settings.json" >/dev/null'
ok "the report names the copy" 'grep -qxF "added: .claude/settings.json marketplace other-market" <<<"$OUT" && grep -qxF "added: .claude/settings.json plugin gaffer@other-market" <<<"$OUT"'
before=$(snapshot); run_copy files "$R"
ok "second run from the copy changes no byte" '[ "$(snapshot)" = "$before" ] && ! grep -q "^added:" <<<"$OUT"'
fresh; copy '{"name":"m2","plugins":[{"name":"tool","source":"./","repository":"https://github.com/o/r.git"}]}'; run_copy files "$R"
ok "a repository URL ending .git, and a plugin of another name" 'jq -e ".extraKnownMarketplaces.m2.source.repo == \"o/r\" and .enabledPlugins[\"tool@m2\"] == true" "$R/.claude/settings.json" >/dev/null'
fresh; copy '{"name":"m3","plugins":[{"name":"gaffer","source":"./","repository":"https://github.com/o/r/"}]}'; run_copy files "$R"
ok "a repository URL ending in a slash" 'jq -e ".extraKnownMarketplaces.m3.source.repo == \"o/r\"" "$R/.claude/settings.json" >/dev/null'
fresh; copy '{"name":"m4","plugins":[{"name":"gaffer","source":"./","repository":"https://github.com/o/r"}]}'
OUT=$(cd "$SB" && bash "copy$NC/init/setup.sh" files "repo$N" 2>&1); RC=$?
ok "called by a path relative to another directory, the manifest is still found" '[ $RC = 0 ] && jq -e ".extraKnownMarketplaces.m4.source.repo == \"o/r\"" "$R/.claude/settings.json" >/dev/null'

echo "files, when the manifest does not give the identity:"
refused() { [ $RC = 1 ] && grep -q "marketplace" <<<"$OUT" && grep -q "nothing was changed" <<<"$OUT" && [ "$(snapshot)" = "$before" ]; }
fresh; copy; before=$(snapshot); run_copy files "$R"
ok "no manifest → error, nothing changed" 'refused && grep -q "no marketplace manifest" <<<"$OUT"'
fresh; copy '{"name":"m","plugins":[{"name":"gaffer","source":"./"}]}'; before=$(snapshot); run_copy files "$R"
ok "no repository → error naming the field, nothing changed" 'refused && grep -qF ".plugins[0].repository" <<<"$OUT"'
fresh; copy '{"name":"m","plugins":[{"name":"gaffer","source":"./","repository":"https://gitlab.com/o/r"}]}'; before=$(snapshot); run_copy files "$R"
ok "a repository that is not on github.com → error, nothing changed" 'refused'
fresh; copy '{"name":"m","plugins":[{"name":"gaffer","source":"./","repository":"https://github.com/o"}]}'; before=$(snapshot); run_copy files "$R"
ok "a repository URL with no repository in it → error, nothing changed" 'refused'
fresh; copy '{"name":"m","plugins":[{"name":"gaffer","source":"./","repository":"https://github.com/o/r/tree/main"}]}'; before=$(snapshot); run_copy files "$R"
ok "a repository URL that goes past the repository → error, nothing changed" 'refused'
fresh; copy '{"plugins":[{"name":"gaffer","source":"./","repository":"https://github.com/o/r"}]}'; before=$(snapshot); run_copy files "$R"
ok "no marketplace name → error, nothing changed" 'refused'
fresh; copy '{"name":"m","plugins":[]}'; before=$(snapshot); run_copy files "$R"
ok "no plugin entry → error, nothing changed" 'refused'
fresh; copy '{"name":'; before=$(snapshot); run_copy files "$R"
ok "a manifest that is not JSON → error, nothing changed" 'refused'
fresh; copy; run_copy check "$R"
ok "check reads no manifest: it is ready without one" '[ $RC = 0 ] && [ "$OUT" = "ready: main" ]'

echo "labels:"
fresh; run labels "$R"
ok "the labels mode is gone — init lists the tracker's states and creates none — so it is a usage error" '[ $RC = 2 ] && [ ! -s "$STUB_DIR/gh-log" ]'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
