#!/usr/bin/env bash
#
# boundary.tests.sh — nothing the plugin runs reaches GitHub issues except through tracker.sh.
#
# Scans what the plugin runs or tells a model to run — every committed file under commands/,
# defaults/ and templates/, and every committed shell script that is not a test matrix — for a
# `gh issue` call, an issue REST path, an issue search, or a label call. Two files are exempt by
# name: the GitHub adapter, which is where those calls belong, and chain/chain-next.sh, the runner,
# which selects and parks issues on GitHub alone. Test matrices stub gh, and docs describe rather
# than run, so neither is scanned. The scanner is checked against planted calls first, so a pattern
# that matches nothing cannot pass the repository vacuously.
#
#   Usage:  bash tracker/boundary.tests.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXEMPT=(tracker/adapters/github.sh chain/chain-next.sh)
PATTERN='gh issue|gh label|gh search issues|search/issues|repos/[^[:space:]]*/(issues|labels)|issues/[^[:space:]]*comments|--(add|remove)-label'

# scan <root> — every offending line under <root>'s committed files, as path:line:text.
scan() {
  local root=$1 f e
  git -C "$root" ls-files -- 'commands/*' 'defaults/*' 'templates/*' '*.sh' | while IFS= read -r f; do
    case $f in *.tests.sh) continue ;; esac
    for e in "${EXEMPT[@]}"; do [ "$f" = "$e" ] && continue 2; done
    grep -nE -- "$PATTERN" "$root/$f" | sed "s#^#$f:#"
  done
}

PASS=0; FAIL=0
ok() { if eval "$2"; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1"; echo "$OUT" | sed 's/^/       /'; fi; }

SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
git -C "$SB" init -q
mkdir -p "$SB/commands" "$SB/chain" "$SB/tracker/adapters" "$SB/docs"
printf 'Run `gh issue view 5`.\n' > "$SB/commands/a.md"
printf 'gh api repos/o/r/issues/comments/9 -X PATCH\n' > "$SB/commands/b.md"
printf 'gh api --paginate "repos/{owner}/{repo}/issues/5/comments"\n' > "$SB/commands/c.md"
printf 'gh label create x\n' > "$SB/commands/d.md"
printf 'gh api repos/o/r/issues/5/labels -f labels[]=x\n' > "$SB/commands/e.md"
printf 'x() { gh pr edit 5 --add-label ready; }\n' > "$SB/chain/run.sh"
printf 'gh issue view 5\n' > "$SB/chain/chain-next.sh"
printf 'gh issue view 5\n' > "$SB/tracker/adapters/github.sh"
printf 'gh issue view 5\n' > "$SB/chain/run.tests.sh"
printf 'gh issue view 5\n' > "$SB/docs/guide.md"
printf 'gh pr view 5; gh api repos/o/r/pulls/5/reviews\n' > "$SB/commands/f.md"
printf 'gh api --method PATCH repos/<owner>/<repo>/issues/<number> --input p.json\n' > "$SB/commands/g.md"
printf 'gh api repos/{owner}/{repo}/issues -f title=x\n' > "$SB/commands/h.md"
printf 'gh search issues "audit in:title"\n' > "$SB/commands/i.md"
printf 'gh api "search/issues?q=repo:o/r+audit"\n' > "$SB/commands/j.md"
printf 'gh api repos/o/r/labels -f name=ready\n' > "$SB/commands/k.md"
git -C "$SB" add -A
OUT=$(scan "$SB")
echo "The scanner:"
for f in commands/a.md commands/b.md commands/c.md commands/d.md commands/e.md commands/g.md commands/h.md commands/i.md commands/j.md commands/k.md chain/run.sh; do
  ok "finds the planted call in $f" 'grep -q "^$f:" <<<"$OUT"'
done
for f in chain/chain-next.sh tracker/adapters/github.sh chain/run.tests.sh docs/guide.md commands/f.md; do
  ok "leaves $f alone" '! grep -q "^$f:" <<<"$OUT"'
done

echo "This repository:"
OUT=$(scan "$ROOT")
ok "no command, default, template or script reaches GitHub issues outside the adapter and the runner" '[ -z "$OUT" ]'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
