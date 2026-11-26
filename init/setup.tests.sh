#!/usr/bin/env bash
#
# setup.tests.sh — standalone test matrix for setup.sh.
#
# Every case runs setup.sh against a throwaway git repository under a mktemp sandbox, so your
# checkout is never touched. setup.sh reaches no host: a `gh` that only records being called is
# first on PATH, and the last case checks it never was. Exits non-zero on any failure. Run it
# after any edit to setup.sh.
#
#   Usage:  bash init/setup.tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$HERE/setup.sh"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# The heredoc is unquoted, so $SB is fixed when the stub is written; the escaped \$@ stays for gh.
mkdir -p "$SB/bin"
cat > "$SB/bin/gh" <<STUB
#!/usr/bin/env bash
{ for a in "\$@"; do printf '%s|' "\$a"; done; printf '\n'; } >> "$SB/gh-log"
exit 1
STUB
chmod +x "$SB/bin/gh"
export PATH="$SB/bin:$PATH"
# No global or system git config, and no global excludes file, so the runner's own ignore rules
# cannot decide a case.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$SB/xdg"

# A PATH with everything setup.sh needs except jq, for the cases that check jq is required.
mkdir -p "$SB/nojq"
for t in bash git grep sed tail mktemp mv rm mkdir cat dirname env; do ln -s "$(command -v "$t")" "$SB/nojq/$t"; done
BASH_BIN=$(command -v bash)

PASS=0; FAIL=0
ok() {
  if eval "$2"; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1"; echo "       output: $OUT"; fi
}

# A fresh repository with one commit on main and no remote.
N=0
fresh() {
  N=$((N + 1))
  R="$SB/repo$N"
  mkdir -p "$R"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@example.invalid
  git -C "$R" config user.name t
  echo "# project" > "$R/README.md"
  git -C "$R" add -A && git -C "$R" commit -qm init
}
run() { OUT=$(bash "$SETUP" "$@" 2>&1); RC=$?; }
snapshot() { (cd "$R" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum); }
status() { git -C "$R" status --porcelain --untracked-files=all; }
excluded() { grep -v '^#' "$R/.git/info/exclude" 2>/dev/null; }

echo "check:"
fresh; before=$(snapshot); run check "$R";     ok "jq on the path → ready, nothing changed" '[ $RC = 0 ] && [ "$OUT" = "ready" ] && [ "$(snapshot)" = "$before" ]'
fresh; git -C "$R" switch -qc other; echo x > "$R/x"; echo y >> "$R/README.md"; run check "$R"
ok "another branch, uncommitted changes, no remote → still ready" '[ $RC = 0 ] && [ "$OUT" = "ready" ]'
fresh; OUT=$(PATH="$SB/nojq" "$BASH_BIN" "$SETUP" check "$R" 2>&1); RC=$?
ok "jq missing → not ready" '[ $RC = 1 ] && [ "$OUT" = "not ready: jq is not on the path" ]'
fresh; mkdir "$R/sub"; run check "$R/sub";     ok "not the work-tree root → error" '[ $RC = 1 ] && grep -q "not the root" <<<"$OUT"'
fresh; mkdir "$R/sub"; before=$(snapshot); run files "$R/sub"
ok "files, not at the work-tree root → error, nothing changed" '[ $RC = 1 ] && grep -q "not the root" <<<"$OUT" && [ "$(snapshot)" = "$before" ]'
mkdir -p "$SB/plain"; run files "$SB/plain";    ok "not a git repository → error" '[ $RC = 1 ] && grep -q "not a git repository" <<<"$OUT"'
fresh; run frobnicate "$R";                    ok "unknown mode → usage" '[ $RC = 2 ]'
fresh; run files "$R" "$R";                    ok "two repositories → usage" '[ $RC = 2 ]'
fresh; before=$(snapshot); run files --frob "$R"; ok "unknown option → usage, nothing changed" '[ $RC = 2 ] && [ "$(snapshot)" = "$before" ]'
fresh; run check --git-ignore "$R";            ok "--git-ignore belongs to files alone → usage" '[ $RC = 2 ]'
run;                                           ok "no mode → usage" '[ $RC = 2 ]'

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
ok "no allow rule is written: what the tracker skill's calls need allowed is the repository's or the user's to grant" 'jq -e ".permissions.allow == null" "$R/.claude/settings.json" >/dev/null'
ok "every change reported as added" '[ "$(grep -c "^added:" <<<"$OUT")" = 7 ] && ! grep -q "^present:" <<<"$OUT"'
ok "nothing is committed, and this clone's exclude file is untouched" '[ "$(git -C "$R" rev-list --count HEAD)" = 1 ] && [ -n "$(status)" ] && [ -z "$(excluded)" ]'

echo "files, run twice:"
before=$(snapshot); run files "$R"
ok "second run changes no byte" '[ "$(snapshot)" = "$before" ]'
ok "second run reports everything present" '! grep -q "^added:" <<<"$OUT" && [ "$(grep -c "^present:" <<<"$OUT")" = 7 ]'

echo "files, on another branch with work in progress:"
fresh; git -C "$R" switch -qc work; echo x > "$R/x"; echo y >> "$R/README.md"; run files "$R"
ok "sets up where it stands" '[ $RC = 0 ] && [ "$(grep -c "^added:" <<<"$OUT")" = 7 ] && [ "$(git -C "$R" rev-parse --abbrev-ref HEAD)" = work ]'
ok "the work in progress is as it was" '[ "$(cat "$R/x")" = x ] && [ "$(tail -1 "$R/README.md")" = y ]'

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
fresh; mkdir -p "$R/.claude"; echo '[1,2]' > "$R/.claude/settings.json"; before=$(snapshot); run files "$R"
ok "settings that are JSON but not an object → error, nothing changed" '[ $RC = 1 ] && grep -q "not a JSON object" <<<"$OUT" && [ "$(snapshot)" = "$before" ]'
fresh; mkdir -p "$R/.claude"; echo '{"extraKnownMarketplaces":{"gaffer-claude":{"source":{"source":"directory","path":"/x"}}},"permissions":{"ask":["Bash(rm:*)","Bash(chmod:*)"]}}' > "$R/.claude/settings.json"; run files "$R"
ok "an existing gaffer marketplace entry is kept as it is" 'jq -e ".extraKnownMarketplaces[\"gaffer-claude\"].source.path == \"/x\"" "$R/.claude/settings.json" >/dev/null'
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

echo "files --git-ignore, on a repository with nothing:"
fresh; echo "# Conventions" > "$R/CONVENTIONS.md"; echo "# Review" > "$R/REVIEW.md"; run files --git-ignore "$R"
ok "exits 0, and the setup is all there" '[ $RC = 0 ] && [ -f "$R/.claude/settings.json" ] && [ -f "$R/.claude/memory/MEMORY.md" ] && grep -qx "@CONVENTIONS.md" "$R/CLAUDE.md"'
ok "git sees no change at all" '[ -z "$(status)" ]'
ok ".gitignore is not written" '[ ! -e "$R/.gitignore" ]'
ok "every path init manages is excluded in this clone, anchored at the root" '[ "$(excluded)" = "$(printf "/CONVENTIONS.md\n/REVIEW.md\n/CLAUDE.md\n/.claude/settings.json\n/.claude/memory/\n/.claude/scratch/")" ]'
ok "each is reported as added, with where" '[ "$(grep -c "git-ignored (.git/info/exclude)$" <<<"$OUT")" = 6 ] && grep -qxF "added: .claude/scratch/ git-ignored (.git/info/exclude)" <<<"$OUT"'
ok "nothing is tracked, so nothing is reported so; and no ignored: lines, which the excludes already say" '! grep -q "^tracked:\|^ignored:" <<<"$OUT"'
ok "a later memory entry and scratch file are hidden too" 'echo e > "$R/.claude/memory/e.md" && mkdir -p "$R/.claude/scratch" && echo s > "$R/.claude/scratch/s" && [ -z "$(status)" ]'
before=$(snapshot); ex=$(cat "$R/.git/info/exclude"); run files --git-ignore "$R"
ok "second run changes no byte, the exclude file included" '[ "$(snapshot)" = "$before" ] && [ "$(cat "$R/.git/info/exclude")" = "$ex" ] && ! grep -q "^added:" <<<"$OUT"'
ok "second run reports the six paths present" '[ "$(grep -c "^present: .* git-ignored$" <<<"$OUT")" = 6 ]'
fresh; run files "$R" --git-ignore
ok "the option may follow the repository" '[ $RC = 0 ] && [ -z "$(status)" ]'
fresh; OUT=$(cd "$R" && bash "$SETUP" files --git-ignore 2>&1); RC=$?
ok "the form the command runs, from the root with no repository named" '[ $RC = 0 ] && [ -f "$R/.claude/settings.json" ] && [ -z "$(status)" ] && [ "$(excluded | wc -l)" = 6 ]'

echo "files --git-ignore, when git already tracks a file:"
fresh; echo "# Project" > "$R/CLAUDE.md"; echo "# Conventions" > "$R/CONVENTIONS.md"; mkdir -p "$R/.claude"
echo '{"model":"opus","enabledPlugins":{"gaffer@gaffer-claude":false}}' > "$R/.claude/settings.json"
git -C "$R" add CLAUDE.md .claude && git -C "$R" commit -qm tracked; claude_before=$(cat "$R/CLAUDE.md"); settings_before=$(cat "$R/.claude/settings.json"); run files --git-ignore "$R"
ok "a tracked CLAUDE.md and settings.json are reported, and left byte for byte" 'grep -qx "tracked: CLAUDE.md left as it is; its imports go in CLAUDE.local.md" <<<"$OUT" && grep -qx "tracked: .claude/settings.json left as it is; its entries go in .claude/settings.local.json" <<<"$OUT" && [ "$(cat "$R/CLAUDE.md")" = "$claude_before" ] && [ "$(cat "$R/.claude/settings.json")" = "$settings_before" ]'
ok "the imports go in CLAUDE.local.md" '[ "$(cat "$R/CLAUDE.local.md")" = "$(printf "@CONVENTIONS.md\n\n@.claude/memory/MEMORY.md")" ]'
ok "the missing entries go in settings.local.json, and a plugin the tracked file turned off is not turned back on" 'jq -e ".enabledPlugins == {\"pr-review-toolkit@claude-plugins-official\": true} and .permissions.ask == [\"Bash(chmod:*)\"] and .extraKnownMarketplaces[\"gaffer-claude\"] != null" "$R/.claude/settings.local.json" >/dev/null && grep -qx "present: .claude/settings.local.json plugin gaffer@gaffer-claude" <<<"$OUT"'
ok "git sees no change at all, so the next build is not refused" '[ -z "$(status)" ]'
ok "the local files are excluded, the tracked ones are not" '[ "$(excluded)" = "$(printf "/CONVENTIONS.md\n/REVIEW.md\n/CLAUDE.local.md\n/.claude/settings.local.json\n/.claude/memory/\n/.claude/scratch/")" ]'
before=$(snapshot); run files --git-ignore "$R"
ok "second run changes no byte, and finds the imports and entries present" '[ "$(snapshot)" = "$before" ] && ! grep -q "^added:" <<<"$OUT"'
fresh; printf '.claude/\n' > "$R/.gitignore"; mkdir -p "$R/.claude/memory"; echo '{}' > "$R/.claude/settings.json"; echo "- [A](a.md) — b" > "$R/.claude/memory/MEMORY.md"
git -C "$R" add .gitignore && git -C "$R" add -f .claude/settings.json .claude/memory/MEMORY.md && git -C "$R" commit -qm tracked; run files --git-ignore "$R"
ok "a tracked settings.json that an ignore rule also matches is tracked, not present" 'grep -q "^tracked: .claude/settings.json " <<<"$OUT" && ! grep -q "^present: .claude/settings.json" <<<"$OUT" && [ "$(cat "$R/.claude/settings.json")" = "{}" ] && [ -f "$R/.claude/settings.local.json" ] && [ -z "$(status)" ]'
ok "so is a tracked memory folder an ignore rule also matches" 'grep -qx "tracked: .claude/memory/" <<<"$OUT" && ! grep -q "^present: .claude/memory/ git-ignored" <<<"$OUT"'
fresh; mkdir -p "$R/.claude/memory"; echo "- [A](a.md) — b" > "$R/.claude/memory/MEMORY.md"; git -C "$R" add -A && git -C "$R" commit -qm memory; run files --git-ignore "$R"
ok "a directory with a tracked file in it is tracked" 'grep -qx "tracked: .claude/memory/" <<<"$OUT" && ! excluded | grep -q memory'

echo "files --git-ignore, beside ignore rules already there:"
fresh; printf '.claude/\n' > "$R/.gitignore"; git -C "$R" add -A && git -C "$R" commit -qm ignore; before=$(cat "$R/.gitignore"); run files --git-ignore "$R"
ok "a path a .gitignore rule already covers is present, and gets no exclude line" 'grep -qx "present: .claude/settings.json git-ignored" <<<"$OUT" && grep -qx "present: .claude/scratch/ git-ignored" <<<"$OUT" && [ "$(excluded)" = "$(printf "/CONVENTIONS.md\n/REVIEW.md\n/CLAUDE.md")" ]'
ok ".gitignore is left as it was, and git sees no change" '[ "$(cat "$R/.gitignore")" = "$before" ] && [ -z "$(status)" ]'
fresh; printf '.claude/*\n!.claude/settings.json\n' > "$R/.gitignore"; git -C "$R" add -A && git -C "$R" commit -qm negation; run files --git-ignore "$R"
ok "a path a .gitignore negation un-ignores is reported as still showing" 'grep -q "^shows: .claude/settings.json " <<<"$OUT" && ! grep -q "^added: .claude/settings.json git-ignored" <<<"$OUT" && [ "$(status)" = "?? .claude/settings.json" ]'
fresh; printf '# mine\n*.log' > "$R/.git/info/exclude"; run files --git-ignore "$R"
ok "an exclude file without a final newline gets one before the new lines, and keeps what it had" '[ "$(sed -n 1,3p "$R/.git/info/exclude")" = "$(printf "# mine\n*.log\n/CONVENTIONS.md")" ]'
fresh; rm -rf "$R/.git/info"; run files --git-ignore "$R"
ok "no exclude file or directory yet → created" '[ $RC = 0 ] && [ -z "$(status)" ] && [ "$(excluded | wc -l)" = 6 ]'
fresh; git -C "$R" worktree add -q "$SB/wt$N" -b side; OUT=$(bash "$SETUP" files --git-ignore "$SB/wt$N" 2>&1); RC=$?
ok "in a linked work tree, the files are written there, and the excludes land in the clone's one exclude file and hide them" '[ $RC = 0 ] && [ -f "$SB/wt$N/.claude/settings.json" ] && [ -f "$SB/wt$N/CLAUDE.md" ] && [ ! -e "$R/CLAUDE.md" ] && [ -z "$(git -C "$SB/wt$N" status --porcelain --untracked-files=all)" ] && [ "$(excluded | wc -l)" = 6 ]'
fresh; before=$(snapshot); OUT=$(PATH="$SB/nojq" "$BASH_BIN" "$SETUP" files --git-ignore "$R" 2>&1); RC=$?
ok "jq missing → refuses, nothing changed, nothing excluded" '[ $RC = 1 ] && [ "$(snapshot)" = "$before" ] && [ -z "$(excluded)" ]'
fresh; echo "# Conventions" > "$R/CONVENTIONS.md"; mkdir -p "$R/.claude"; echo '[1,2' > "$R/.claude/settings.json"; run files --git-ignore "$R"
ok "unreadable settings → error, but what was already written is hidden" '[ $RC = 1 ] && grep -q "not a JSON object" <<<"$OUT" && [ -z "$(status)" ]'

echo "files, switching between the two modes:"
fresh; run files "$R"; run files --git-ignore "$R"
ok "plain, then --git-ignore: scratch is excluded too, not left to the uncommitted .gitignore line" 'excluded | grep -qx "/.claude/scratch/" && grep -qxF "added: .claude/scratch/ git-ignored (.git/info/exclude)" <<<"$OUT"'
ok "and the .gitignore the first run wrote is reported as still showing" 'grep -q "^shows: .gitignore " <<<"$OUT" && [ "$(status)" = "?? .gitignore" ]'
ok "discarding that .gitignore un-hides nothing" 'rm "$R/.gitignore" && mkdir -p "$R/.claude/scratch" && echo s > "$R/.claude/scratch/s" && [ -z "$(status)" ]'
fresh; run files --git-ignore "$R"; run files "$R"
ok "--git-ignore, then plain: the .gitignore line is written all the same, for the clones a commit reaches" 'grep -qx ".claude/scratch/" "$R/.gitignore" && grep -qxF "added: .claude/scratch/ git-ignored (.gitignore)" <<<"$OUT"'
fresh; printf '.claude/scratch/\n' > "$R/.gitignore"; git -C "$R" add -A && git -C "$R" commit -qm ignore; run files --git-ignore "$R"
ok "--git-ignore beside a committed, unchanged .gitignore rule relies on it, and reports no .gitignore change" 'grep -qx "present: .claude/scratch/ git-ignored" <<<"$OUT" && ! grep -q "^shows:" <<<"$OUT"'

echo "modes that are gone:"
fresh; run labels "$R"
ok "labels — init lists the tracker's states and creates none — is a usage error" '[ $RC = 2 ]'

echo "no host:"
ok "no case called gh" '[ ! -e "$SB/gh-log" ]'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
