#!/usr/bin/env bash
#
# chain-next.tests.sh — standalone test matrix for chain-next.sh.
#
# The runner's job is choosing: which issue it builds, from what starting point, and what it
# leaves behind when the chain fails. All of that is provable from outside with a stub `gh` first
# on PATH and a stub chain.sh beside the runner in a throwaway plugin checkout, so no model is
# called, nothing reaches GitHub and nothing is spent. Every case runs the runner the way a
# scheduler runs it — from a clone of a plugin origin, against a settings file naming a dedicated
# clone of a target origin — under a mktemp sandbox, so your checkout is never touched. Exits
# non-zero on any failure. Run it after any edit to the runner.
#
# The stub chain stands in for chain.sh: it records the flags it was handed, refuses to start
# anywhere but a clean main and, standing in for /build's stop on an uninspected earlier branch,
# fails at build when a feature/<N>-* branch is already present. A limit-<N> file makes it stop
# the way the real chain stops when the account's usage limit cut a stage off: that closing line,
# and the chain's own usage-limit exit code rather than its ordinary 1. That is what makes "the
# second run starts cleanly" and "an un-parked issue is built from scratch" observable: a runner
# that got the starting point wrong would see the stub refuse.
#
# An installed timer and a real run against GitHub need the build machine, so they are checked by
# hand.
#
#   Usage:  bash chain/chain-next.tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/chain-next.sh"

SB="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$SB"' EXIT
# A developer's ambient overrides would otherwise reach the chain the stub stands in for.
unset CHAIN_MODEL CHAIN_STAGE_TIMEOUT XDG_STATE_HOME

# The stub gh. One log line per invocation, arguments separated by `|`. Issues live in
# issues.json as [{number, state, labels:[names], author?}] and are filtered by whatever --state
# and --label the runner asks for, so a runner that forgot to ask would see closed or unready ones.
# An issue with no author was raised by the maintainer. Open pull requests live in prs.json;
# blockers in blocked-<n>.json. The GraphQL lookup of who has written on an issue answers with
# that author, always a User, and the timeline nodes in comments-<n>.json, and a comments-fail-<n>
# file makes it fail; a comments-<n>.json that is not JSON is passed through as the reply. A gh-fail file makes every
# call fail, as an outage would; gh-fail-<command> fails only that command (gh-fail-pr, gh-fail-api). Label and comment writes are applied to the stub's own state,
# so a parked issue stays parked for the next firing.
mkdir -p "$SB/bin"
cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
{ for a in "$@"; do printf '%s|' "$a"; done; printf '\n'; } >> "$STUB_DIR/gh-log"
if [ -f "$STUB_DIR/gh-fail" ] || [ -f "$STUB_DIR/gh-fail-$1" ]; then echo "gh: HTTP 502: Bad Gateway" >&2; exit 1; fi
args=("$@")
opt() { local i; for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[i]}" = "$1" ] && { printf '%s' "${args[i+1]}"; return; }; done; }
case "$1 $2" in
  "issue list")
    state=$(opt --state); label=$(opt --label)
    jq -c --arg s "$state" --arg l "$label" '
      map(select(($s == "" or $s == "all" or (.state | ascii_downcase) == $s)
        and ($l == "" or (.labels | index($l)))))
      | map({number, state, labels: (.labels | map({name: .}))})' "$STUB_DIR/issues.json" ;;
  "pr list")
    if [ -f "$STUB_DIR/prs.json" ]; then cat "$STUB_DIR/prs.json"; else echo '[]'; fi ;;
  "issue edit")
    n=$3; add=$(opt --add-label)
    jq --argjson n "$n" --arg l "$add" 'map(if .number == $n then .labels += [$l] else . end)' \
      "$STUB_DIR/issues.json" > "$STUB_DIR/issues.tmp" && mv "$STUB_DIR/issues.tmp" "$STUB_DIR/issues.json" ;;
  "issue comment")
    printf '%s' "$(opt --body)" > "$STUB_DIR/comment-$3.txt" ;;
  *)
    if [ "$1 $2" = "api graphql" ]; then
      n=$(printf '%s\n' "$@" | sed -n 's/^n=//p')
      if [ -f "$STUB_DIR/comments-fail-$n" ]; then echo "gh: HTTP 502: Bad Gateway" >&2; exit 1; fi
      f="$STUB_DIR/comments-$n.json"
      [ -f "$f" ] || f=/dev/null
      jq . "$f" >/dev/null 2>&1 || { cat "$f"; exit 0; }
      jq -n --argjson n "$n" --slurpfile i "$STUB_DIR/issues.json" --slurpfile c "$f" \
        '{data: {repository: {issue: {author: {__typename: "User", login: ($i[0][] | select(.number == $n) | .author // "maintainer")},
          timelineItems: {pageInfo: {hasNextPage: false}, nodes: ($c[0] // [])}}}}}'
      exit $?
    fi
    if [ "$1" = api ]; then
      for a in "$@"; do
        if [[ "$a" =~ issues/([0-9]+)/dependencies/blocked_by ]]; then
          f="$STUB_DIR/blocked-${BASH_REMATCH[1]}.json"
          if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi
          exit 0
        fi
      done
    fi
    echo "stub gh: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$SB/bin/gh"
# chain.sh needs claude; the stub chain never calls it, but the runner checks it is there.
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/claude"
chmod +x "$SB/bin/claude"

# The stub chain, committed beside the runner in each case's plugin origin so the runner meets it
# the way it meets the real one: as chain.sh in its own directory. It records the flags and the
# starting point it was handed, then behaves like a chain run: a feature branch, a commit, and
# either a pushed branch with a linked pull request or a FAILED closing line.
cat > "$SB/stub-chain.sh" <<'STUB'
#!/usr/bin/env bash
flags=; while [ $# -gt 1 ]; do flags="$flags$1|"; shift; done
n=$1
echo "$n" >> "$STUB_DIR/chain-log"
k=$(grep -c '' "$STUB_DIR/chain-log")
{ echo "branch=$(git rev-parse --abbrev-ref HEAD)"; echo "head=$(git rev-parse HEAD)"; echo "status=$(git status --porcelain --ignored | paste -sd,)";
  echo "flags=$flags"; } > "$STUB_DIR/start-$k"
if [ -f "$STUB_DIR/chain-sleep" ]; then sleep "$(cat "$STUB_DIR/chain-sleep")"; fi
if [ -n "$(git status --porcelain)" ] || [ "$(git rev-parse --abbrev-ref HEAD)" != main ]; then
  echo "chain: refused — not a clean main"; exit 1
fi
if [ -n "$(git for-each-ref --format='%(refname)' "refs/heads/feature/$n-*")" ]; then
  echo "chain: [1/3] build — starting"
  echo "chain: FAILED at [1/3] build — feature/$n-work already exists"; exit 1
fi
if [ -f "$STUB_DIR/config-$n" ]; then
  echo "chain: refused — in .gaffer/chain.json, stages.verify.effort is 'hgih', not one of low, medium, high, xhigh, max; no stage was started."
  exit 78
fi
if [ -f "$STUB_DIR/limit-$n" ]; then
  echo "chain: [1/3] build — starting"
  echo "chain: FAILED at [1/3] build — the Claude usage limit was reached — You've hit your session limit · resets 3:20pm (Europe/Berlin)"
  exit 75
fi
git checkout -q -b "feature/$n-work"
git commit -q --allow-empty -m "Refs #$n: stub work"
mkdir -p obj && echo build-output > obj/out.txt && echo half-written > "wip-$n.txt"
echo "chain: [1/3] build — ok"
if [ -f "$STUB_DIR/push-then-fail-$n" ]; then
  git push -q -u origin "feature/$n-work"
  echo "chain: FAILED at [3/3] raise-pr — gh pr create failed"; exit 1
fi
if [ -f "$STUB_DIR/fail-$n" ]; then
  echo "chain: FAILED at [2/$(cat "$STUB_DIR/chain-total" 2>/dev/null || echo 3)] verify — suite red"
  echo "chain: no later stage ran; reopen that stage with \`claude --resume sess-2\`."
  exit 1
fi
git push -q -u origin "feature/$n-work"
prs="$STUB_DIR/prs.json"; [ -f "$prs" ] || echo '[]' > "$prs"
jq --argjson n "$n" '. += [{number: (100 + $n), headRefName: "feature/\($n)-work", closingIssuesReferences: [{number: $n}]}]' \
  "$prs" > "$prs.tmp" && mv "$prs.tmp" "$prs"
echo "chain: done — https://github.com/o/r/pull/$((100 + n))"
STUB

pass=0; fail=0; cases=0
ok() { if eval "$2"; then echo "  ok   $1"; pass=$((pass+1)); else echo "  FAIL $1 -- rc=$RC output:[$OUTPUT]"; fail=$((fail+1)); fi; }

# commit_all <repo> <message> — commit every change as the test identity.
commit_all() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m "$2"; }

# A fresh case: a bare origin standing in for the plugin's repository, whose main carries the
# runner under test and the stub chain under chain/, with the runner's clone of it; a bare origin
# standing in for the target repository, the runner's dedicated clone of it, marked as such, and
# an interactive clone that must never change; a settings file naming that clone; and empty stub
# and state directories.
new_case() {
  cases=$((cases+1))
  local d="$SB/case$cases"
  export STUB_DIR="$d/stub"
  ORIGIN="$d/origin.git"; SEED="$d/seed"; CLONE="$d/runner"; OTHER="$d/interactive"; STATE="$d/state"
  GAFFER_ORIGIN="$d/gaffer-origin.git"; GAFFER_SEED="$d/gaffer-seed"; GAFFER="$d/gaffer"; SETTINGS="$d/chain.json"
  mkdir -p "$STUB_DIR" "$SEED" "$GAFFER_SEED/.claude-plugin" "$GAFFER_SEED/chain"
  git init -q --bare -b main "$GAFFER_ORIGIN"
  git init -q -b main "$GAFFER_SEED"
  git -C "$GAFFER_SEED" remote add origin "$GAFFER_ORIGIN"
  echo '{"name": "gaffer"}' > "$GAFFER_SEED/.claude-plugin/plugin.json"
  cp "$RUNNER" "$GAFFER_SEED/chain/chain-next.sh"
  cp "$SB/stub-chain.sh" "$GAFFER_SEED/chain/chain.sh"
  commit_all "$GAFFER_SEED" "plugin v1"
  git -C "$GAFFER_SEED" push -q origin main
  git clone -q "$GAFFER_ORIGIN" "$GAFFER"
  echo '[]' > "$STUB_DIR/issues.json"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$SEED"
  git -C "$SEED" remote add origin "$ORIGIN"
  printf 'obj/\n' > "$SEED/.gitignore"
  echo readme > "$SEED/README.md"
  commit_all "$SEED" init
  git -C "$SEED" push -q origin main
  git clone -q "$ORIGIN" "$CLONE"
  git -C "$CLONE" config user.name chain-next-tests
  git -C "$CLONE" config user.email chain-next-tests@example.invalid
  git -C "$CLONE" config commit.gpgsign false
  git -C "$CLONE" config chain-next.dedicated true
  git clone -q "$ORIGIN" "$OTHER"
  settings "{\"clone\": \"$CLONE\", \"writers\": [\"User:maintainer\", \"Bot:claude\"], \"state_dir\": \"$STATE\"}"
}
# settings <json> — the case's settings file, as the scheduler would hand it to the runner.
settings() { printf '%s' "$1" > "$SETTINGS"; }

# issues <json> — the repository's issues, as [{number, state, labels}].
issues() { printf '%s' "$1" > "$STUB_DIR/issues.json"; }
unpark() { jq --argjson n "$1" 'map(if .number == $n then .labels -= ["parked"] else . end)' "$STUB_DIR/issues.json" > "$STUB_DIR/i.tmp" && mv "$STUB_DIR/i.tmp" "$STUB_DIR/issues.json"; }

# fire [args…] — one firing of the runner, run as a scheduler runs it: the plugin clone's copy,
# from outside every clone, handed the settings file. Sets OUTPUT (stdout and stderr) and RC,
# which every assertion reads. fire_with <settings> fires against another settings file.
fire() { fire_with "$SETTINGS" "$@"; }
fire_with() {
  local f=$1; shift
  OUTPUT="$(cd "$SB" && PATH="$SB/bin:$PATH" bash "$GAFFER/chain/chain-next.sh" "$@" "$f" </dev/null 2>&1)"; RC=$?
}
# advance_gaffer <message> — a new commit on the plugin origin's main, as a merge there would make,
# fetched into the runner's clone but not merged — the state a scheduler's failed update leaves.
advance_gaffer() { echo "$1" > "$GAFFER_SEED/CHANGE.md"; commit_all "$GAFFER_SEED" "$1"; git -C "$GAFFER_SEED" push -q origin main; git -C "$GAFFER" fetch -q origin; }

chain_calls() { if [ -f "$STUB_DIR/chain-log" ]; then paste -sd, "$STUB_DIR/chain-log"; fi; }
gh_writes() { { grep -E '^issue\|(edit|comment)\|' "$STUB_DIR/gh-log" 2>/dev/null || true; } | grep -c ''; }
start_of() { grep "^$2=" "$STUB_DIR/start-$1" | cut -d= -f2-; }
# Everything about a checkout a firing could change: commit, branch, tree (ignored files too),
# and every local branch.
checkout_state() { git -C "$1" rev-parse HEAD; git -C "$1" rev-parse --abbrev-ref HEAD; git -C "$1" status --porcelain --ignored; git -C "$1" for-each-ref --format='%(refname) %(objectname)' refs/heads; }
labels_of() { jq -r --argjson n "$1" '.[] | select(.number == $n) | .labels | join(",")' "$STUB_DIR/issues.json"; }
origin_main() { git -C "$ORIGIN" rev-parse main; }

echo "Asked what it would pick:"
new_case
issues '[{"number":2,"state":"CLOSED","labels":["ready"]},{"number":3,"state":"OPEN","labels":[]},{"number":7,"state":"OPEN","labels":["ready"]},{"number":5,"state":"OPEN","labels":["ready"]}]'
git -C "$CLONE" checkout -q -b feature/1-left-behind
echo stray > "$CLONE/stray.txt"
before="$(checkout_state "$CLONE")"
fire --dry-run
ok "exits 0" '[ "$RC" = 0 ]'
ok "names the lowest-numbered eligible issue" 'grep -qF "#5" <<<"$OUTPUT" && ! grep -qF "#7" <<<"$OUTPUT"'
ok "no chain started" '[ -z "$(chain_calls)" ]'
ok "no label or comment written" '[ "$(gh_writes)" = 0 ]'
ok "the dedicated clone is not reset, even from a feature branch with a dirty tree" '[ "$(checkout_state "$CLONE")" = "$before" ]'
ok "no state written: no lock, no log" '[ ! -e "$STATE" ]'
new_case
issues '[{"number":3,"state":"OPEN","labels":[]}]'
fire --dry-run
ok "with nothing eligible, says so and exits 0" '[ "$RC" = 0 ] && grep -qi "nothing" <<<"$OUTPUT" && [ -z "$(chain_calls)" ]'

echo "Blocked and already-raised issues are skipped:"
new_case
issues '[{"number":1,"state":"CLOSED","labels":["ready"]},{"number":2,"state":"OPEN","labels":["bug"]},{"number":3,"state":"OPEN","labels":["ready","parked"]},{"number":4,"state":"OPEN","labels":["ready"]},{"number":5,"state":"OPEN","labels":["ready"]},{"number":6,"state":"OPEN","labels":["ready"]},{"number":8,"state":"OPEN","labels":["ready"]},{"number":9,"state":"OPEN","labels":["ready"]}]'
echo '[{"number":40,"state":"open"}]' > "$STUB_DIR/blocked-4.json"
echo '[{"number":50,"headRefName":"some-other-name","closingIssuesReferences":[{"number":5}]},{"number":60,"headRefName":"feature/6-thing","closingIssuesReferences":[]}]' > "$STUB_DIR/prs.json"
echo '[{"number":41,"state":"closed"}]' > "$STUB_DIR/blocked-8.json"
fire --dry-run
ok "closed, not-ready, parked, blocked and already-raised issues are passed over" '[ "$RC" = 0 ] && grep -qF "#8" <<<"$OUTPUT"'
fire
ok "and a real firing builds the first one that is none of those" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 8 ]'
new_case
issues '[{"number":4,"state":"OPEN","labels":["ready"]}]'
echo '[{"number":40,"state":"open"}]' > "$STUB_DIR/blocked-4.json"
fire
ok "an issue whose only blocker is open is not built" '[ "$RC" = 0 ] && [ -z "$(chain_calls)" ]'
echo '[{"number":40,"state":"closed"}]' > "$STUB_DIR/blocked-4.json"
fire
ok "and is picked up once its blocker closes, with nothing restarted" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 4 ]'

echo "An issue raised by someone else is not built:"
new_case
issues '[{"number":3,"state":"OPEN","labels":["ready"],"author":"someone-else"},{"number":5,"state":"OPEN","labels":["ready"]}]'
fire --dry-run
ok "the issue someone else raised is passed over, and named as skipped" '[ "$RC" = 0 ] && grep -qF "would build #5" <<<"$OUTPUT" && grep -qF "skipped #3" <<<"$OUTPUT"'
fire
ok "and a real firing builds only the maintainer's, parking nothing" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 5 ] && [ "$(gh_writes)" = 0 ]'

echo "An issue someone else has commented on is not built:"
new_case
issues '[{"number":4,"state":"OPEN","labels":["ready"]},{"number":5,"state":"OPEN","labels":["ready"]},{"number":6,"state":"OPEN","labels":["ready"]},{"number":7,"state":"OPEN","labels":["ready"]}]'
echo '[{"author":{"__typename":"User","login":"someone-else"}}]' > "$STUB_DIR/comments-4.json"
echo '[{"author":{"__typename":"User","login":"claude"}}]' > "$STUB_DIR/comments-5.json"
echo '[{"deletedCommentAuthor":{"__typename":"User","login":"someone-else"}}]' > "$STUB_DIR/comments-6.json"
echo '[{"author":{"__typename":"Bot","login":"claude"}},{"author":{"__typename":"User","login":"maintainer"}},{"deletedCommentAuthor":{"__typename":"Bot","login":"claude"}}]' > "$STUB_DIR/comments-7.json"
fire --dry-run
ok "issues with someone else's comment, live or deleted, are passed over for one only the maintainer and the bot wrote on" '[ "$RC" = 0 ] && grep -qF "would build #7" <<<"$OUTPUT" && grep -qF "skipped #4" <<<"$OUTPUT" && grep -qF "skipped #6" <<<"$OUTPUT"'
ok "a person whose login matches the bot's is someone else too" 'grep -qF "skipped #5" <<<"$OUTPUT"'
fire
ok "and a real firing builds that one, parking nothing" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 7 ] && [ "$(gh_writes)" = 0 ]'

echo "A failed comment lookup selects nothing:"
new_case
issues '[{"number":12,"state":"OPEN","labels":["ready"]}]'
touch "$STUB_DIR/comments-fail-12"
fire
ok "a failed lookup of who wrote on the issue selects nothing" '[ "$RC" != 0 ] && [ -z "$(chain_calls)" ]'
new_case
issues '[{"number":12,"state":"OPEN","labels":["ready"]}]'
printf 'not json' > "$STUB_DIR/comments-12.json"
fire
ok "and so does an unreadable one" '[ "$RC" != 0 ] && [ -z "$(chain_calls)" ]'

echo "A ready issue becomes a pull request:"
new_case
issues '[{"number":12,"state":"OPEN","labels":["ready"]}]'
# What an earlier run could leave behind: a feature branch checked out, a dirty tree, build output.
git -C "$CLONE" checkout -q -b feature/1-left-behind
echo stray > "$CLONE/stray.txt"
mkdir -p "$CLONE/obj" && echo stale > "$CLONE/obj/stale.txt"
# main has moved on since the clone was made.
echo newer > "$SEED/newer.txt"; commit_all "$SEED" newer; git -C "$SEED" push -q origin main
other_before="$(checkout_state "$OTHER")"
fire
ok "exits 0" '[ "$RC" = 0 ]'
ok "the chain ran once, against the issue" '[ "$(chain_calls)" = 12 ]'
ok "it started on main" '[ "$(start_of 1 branch)" = main ]'
ok "at the latest main" '[ "$(start_of 1 head)" = "$(origin_main)" ]'
ok "with nothing left of the earlier run: no change, no stray file, no build output" '[ -z "$(start_of 1 status)" ]'
ok "the issue ends with an open pull request linked to it" '[ "$(jq "[.[] | select(.closingIssuesReferences[].number == 12)] | length" "$STUB_DIR/prs.json")" = 1 ]'
ok "the closing line names the pull request" 'grep -qF "https://github.com/o/r/pull/112" <<<"$OUTPUT"'
ok "the issue is not parked" '[ "$(labels_of 12)" = ready ] && [ "$(gh_writes)" = 0 ]'
ok "the chain's output is kept in a per-issue log outside the clone" 'ls "$STATE"/logs/12-*.log >/dev/null 2>&1 && grep -qF "chain: done" "$STATE"/logs/12-*.log'
ok "no other checkout changed" '[ "$(checkout_state "$OTHER")" = "$other_before" ]'
new_case
issues '[{"number":12,"state":"OPEN","labels":["ready"]}]'
# A branch merged and deleted on GitHub, and a kept earlier attempt with no upstream at all.
git -C "$CLONE" checkout -q -b feature/3-merged
git -C "$CLONE" commit -q --allow-empty -m merged
git -C "$CLONE" push -q -u origin feature/3-merged
git -C "$CLONE" branch -q attempt/4-20260101T000000Z
git -C "$CLONE" checkout -q main
git -C "$ORIGIN" branch -D feature/3-merged >/dev/null
fire
ok "local branches whose upstream is gone are deleted" '[ "$RC" = 0 ] && ! git -C "$CLONE" rev-parse -q --verify refs/heads/feature/3-merged >/dev/null'
ok "kept attempt branches are not" 'git -C "$CLONE" rev-parse -q --verify refs/heads/attempt/4-20260101T000000Z >/dev/null'

echo "A failing issue is parked and not retried:"
new_case
issues '[{"number":8,"state":"OPEN","labels":["ready"]}]'
touch "$STUB_DIR/fail-8"
fire
ok "exits non-zero" '[ "$RC" != 0 ]'
ok "the issue is marked parked" '[ "$(labels_of 8)" = "ready,parked" ]'
ok "the comment names the failed stage and its reason" 'grep -qF "stopped at **[2/3] verify** — suite red" "$STUB_DIR/comment-8.txt"'
ok "the comment names no usage limit, and closes the way it always has" '! grep -qi "usage limit" "$STUB_DIR/comment-8.txt" && grep -qF "Remove the \`parked\` label to have the runner build this issue again from scratch." "$STUB_DIR/comment-8.txt"'
log=$(ls "$STATE"/logs/8-*.log 2>/dev/null | head -n 1)
ok "the comment names the log, which holds the chain's full output" '[ -n "$log" ] && grep -qF "$log" "$STUB_DIR/comment-8.txt" && grep -qF "claude --resume sess-2" "$log"'
kept=$(git -C "$CLONE" for-each-ref --format='%(refname:short)' 'refs/heads/attempt/8-*')
ok "the attempt's work is kept on an attempt branch, which the comment names" '[ -n "$kept" ] && grep -qF "$kept" "$STUB_DIR/comment-8.txt" && [ "$(git -C "$CLONE" log -1 --format=%s "$kept")" = "Refs #8: stub work" ]'
ok "no feature branch for the issue is left behind" '[ -z "$(git -C "$CLONE" for-each-ref "refs/heads/feature/8-*")" ]'
ok "nothing is pushed" '[ -z "$(git -C "$ORIGIN" for-each-ref refs/heads/attempt refs/heads/feature)" ]'
fire
ok "a later firing does not select it" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 8 ]'
unpark 8; rm "$STUB_DIR/fail-8"
fire
ok "once un-parked it is picked up, with nothing restarted" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 8,8 ]'
ok "and built from scratch on a clean main" '[ "$(start_of 2 branch)" = main ] && [ -z "$(start_of 2 status)" ] && grep -qF "pull/108" <<<"$OUTPUT"'
ok "the earlier attempt's work is still there" 'git -C "$CLONE" rev-parse -q --verify "refs/heads/$kept" >/dev/null'
ok "the retry has a log of its own; the first is kept" '[ "$(ls "$STATE"/logs/8-*.log | grep -c "")" = 2 ] && [ -f "$log" ]'
# The stage total is matched as any number, so the runner needs no change when the chain gains or
# loses a stage.
new_case
issues '[{"number":8,"state":"OPEN","labels":["ready"]}]'
touch "$STUB_DIR/fail-8"; echo 5 > "$STUB_DIR/chain-total"
fire
ok "a chain with a different number of stages is still parked at its stage" '[ "$RC" != 0 ] && grep -qF "stopped at **[2/5] verify** — suite red" "$STUB_DIR/comment-8.txt"'
new_case
issues '[{"number":8,"state":"OPEN","labels":["ready"]}]'
touch "$STUB_DIR/push-then-fail-8"
fire
ok "a branch pushed without a pull request is named in the comment and left on GitHub" '[ "$RC" != 0 ] && grep -qF "feature/8-work" "$STUB_DIR/comment-8.txt" && git -C "$ORIGIN" rev-parse -q --verify refs/heads/feature/8-work >/dev/null'
kept=$(git -C "$CLONE" for-each-ref --format='%(refname:short)' 'refs/heads/attempt/8-*')
# As the comment advises, someone removes the pushed branch by hand; then another issue is built.
git -C "$ORIGIN" branch -D feature/8-work >/dev/null
issues '[{"number":8,"state":"OPEN","labels":["ready","parked"]},{"number":9,"state":"OPEN","labels":["ready"]}]'
fire
ok "the kept attempt survives its pushed branch being removed from GitHub" '[ "$RC" = 0 ] && [ -n "$kept" ] && git -C "$CLONE" rev-parse -q --verify "refs/heads/$kept" >/dev/null'
new_case
issues '[{"number":8,"state":"OPEN","labels":["ready"]}]'
# A leftover branch that cannot be set aside: a branch named `attempt` blocks every attempt/* name.
git -C "$CLONE" branch -q feature/8-work
git -C "$CLONE" branch -q attempt
fire
ok "a leftover branch that cannot be set aside stops the firing before any chain, parking nothing" '[ "$RC" != 0 ] && [ -z "$(chain_calls)" ] && [ "$(labels_of 8)" = ready ]'
new_case
issues '[{"number":8,"state":"OPEN","labels":["ready"]}]'
# A run killed mid-way (a reboot, a stopped service) leaves its branch but parks nothing.
git -C "$CLONE" checkout -q -b feature/8-work
git -C "$CLONE" commit -q --allow-empty -m "killed mid-run"
fire
ok "an earlier run's leftover branch does not stop the next run" '[ "$RC" = 0 ] && grep -qF "pull/108" <<<"$OUTPUT" && [ -n "$(git -C "$CLONE" for-each-ref "refs/heads/attempt/8-*")" ]'

echo "A chain that stops on its own configuration does not park the issue:"
new_case
issues '[{"number":8,"state":"OPEN","labels":["ready"]}]'
touch "$STUB_DIR/config-8"
fire
ok "exits non-zero" '[ "$RC" != 0 ]'
ok "the issue is not parked, so it is not blamed for the configuration" '[ "$(labels_of 8)" = "ready" ] && [ ! -f "$STUB_DIR/comment-8.txt" ]'
ok "the runner's log says the chain stopped on its configuration" 'grep -qF "configuration" <<<"$OUTPUT"'
rm "$STUB_DIR/config-8"

echo "Usage limit is named in the parked comment:"
new_case
issues '[{"number":8,"state":"OPEN","labels":["ready"]}]'
touch "$STUB_DIR/limit-8"
fire
ok "exits non-zero" '[ "$RC" != 0 ]'
ok "the issue is parked, as any other stop parks it" '[ "$(labels_of 8)" = "ready,parked" ]'
ok "the comment says the usage limit was reached" 'grep -qF "the Claude usage limit was reached" "$STUB_DIR/comment-8.txt"'
ok "the comment carries the reply's own reset wording" 'grep -qF "resets 3:20pm (Europe/Berlin)" "$STUB_DIR/comment-8.txt"'
ok "the comment says the issue itself needs nothing" 'grep -qF "not because anything is wrong with the issue" "$STUB_DIR/comment-8.txt"'
ok "the comment says to remove the label once the limit has reset" 'grep -qF "Remove the \`parked\` label once the limit has reset" "$STUB_DIR/comment-8.txt"'
ok "the runner's own log names the usage limit in the same way" 'grep -qF "the Claude usage limit was reached" <<<"$OUTPUT"'
limit_log=$(ls "$STATE"/logs/8-*.log 2>/dev/null | head -n 1)
ok "so does the chain log the comment points at" '[ -n "$limit_log" ] && grep -qF "the Claude usage limit was reached" "$limit_log"'
unpark 8; rm "$STUB_DIR/limit-8"
fire
ok "removing the label is all it takes: the next firing builds the issue" '[ "$RC" = 0 ] && grep -qF "pull/108" <<<"$OUTPUT"'

echo "Overlapping triggers do not start a second run:"
new_case
issues '[{"number":20,"state":"OPEN","labels":["ready"]},{"number":21,"state":"OPEN","labels":["ready"]}]'
echo 3 > "$STUB_DIR/chain-sleep"
( cd "$SB" && PATH="$SB/bin:$PATH" bash "$GAFFER/chain/chain-next.sh" "$SETTINGS" </dev/null > "$SB/first.out" 2>&1; echo $? > "$SB/first.rc" ) &
first=$!
for _ in $(seq 1 50); do [ -f "$STUB_DIR/chain-log" ] && break; sleep 0.1; done
during="$(checkout_state "$CLONE")"
fire
ok "the second firing exits 0" '[ "$RC" = 0 ]'
ok "and starts no chain" '[ "$(chain_calls)" = 20 ]'
ok "and leaves the in-progress run's checkout alone" '[ "$(checkout_state "$CLONE")" = "$during" ]'
wait "$first"
ok "the in-progress run finishes unaffected" '[ "$(cat "$SB/first.rc")" = 0 ] && grep -qF "pull/120" "$SB/first.out"'

echo "Back to back without human help:"
new_case
issues '[{"number":11,"state":"OPEN","labels":["ready"]},{"number":10,"state":"OPEN","labels":["ready"]}]'
fire
ok "the first firing builds the lower-numbered issue" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 10 ]'
ok "and leaves its feature branch checked out" '[ "$(git -C "$CLONE" rev-parse --abbrev-ref HEAD)" = feature/10-work ]'
fire
ok "the second firing builds the other" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 10,11 ]'
ok "starting cleanly on main" '[ "$(start_of 2 branch)" = main ] && [ -z "$(start_of 2 status)" ] && [ "$(start_of 2 head)" = "$(origin_main)" ]'
ok "both issues end with a pull request" '[ "$(jq length "$STUB_DIR/prs.json")" = 2 ]'
fire
ok "a third firing finds nothing left and exits 0" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 10,11 ]'

echo "Nothing to do is not an error:"
new_case
issues '[{"number":3,"state":"OPEN","labels":["ready","parked"]}]'
git -C "$CLONE" checkout -q -b feature/1-left-behind
echo stray > "$CLONE/stray.txt"
before="$(checkout_state "$CLONE")"
fire
ok "exits 0, no chain" '[ "$RC" = 0 ] && [ -z "$(chain_calls)" ]'
ok "changes nothing: no reset, no label, no comment" '[ "$(checkout_state "$CLONE")" = "$before" ] && [ "$(gh_writes)" = 0 ]'

echo "A failed GitHub query selects nothing:"
new_case
issues '[{"number":12,"state":"OPEN","labels":["ready"]}]'
touch "$STUB_DIR/gh-fail"
before="$(checkout_state "$CLONE")"
fire
ok "exits non-zero and says why" '[ "$RC" != 0 ] && grep -qF "502" <<<"$OUTPUT"'
ok "no chain, no reset" '[ -z "$(chain_calls)" ] && [ "$(checkout_state "$CLONE")" = "$before" ]'
new_case
issues '[{"number":12,"state":"OPEN","labels":["ready"]}]'
printf 'not json' > "$STUB_DIR/blocked-12.json"
fire
ok "an unreadable blocker list selects nothing rather than assuming unblocked" '[ "$RC" != 0 ] && [ -z "$(chain_calls)" ]'
new_case
issues '[{"number":12,"state":"OPEN","labels":["ready"]}]'
touch "$STUB_DIR/gh-fail-api"
fire
ok "a failed blocker lookup selects nothing rather than assuming unblocked" '[ "$RC" != 0 ] && [ -z "$(chain_calls)" ]'
new_case
issues '[{"number":12,"state":"OPEN","labels":["ready"]}]'
echo '[{"number":112,"headRefName":"feature/12-work","closingIssuesReferences":[{"number":12}]}]' > "$STUB_DIR/prs.json"
touch "$STUB_DIR/gh-fail-pr"
fire
ok "a failed pull request lookup selects nothing rather than assuming none is open" '[ "$RC" != 0 ] && [ -z "$(chain_calls)" ]'

echo "A machine fault is not blamed on the issue:"
new_case
issues '[{"number":12,"state":"OPEN","labels":["ready"]}]'
mv "$ORIGIN" "$ORIGIN.away"
fire
ok "an unreachable origin starts no chain and parks nothing" '[ "$RC" != 0 ] && [ -z "$(chain_calls)" ] && [ "$(labels_of 12)" = ready ]'
mv "$ORIGIN.away" "$ORIGIN"
fire
ok "and the next firing builds the issue" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 12 ]'
issues '[{"number":12,"state":"OPEN","labels":["ready"]},{"number":13,"state":"OPEN","labels":["ready"]}]'
# Every PATH entry that holds a claude, dropped, with the stub gh kept.
mkdir -p "$SB/noclaude" && ln -sf "$SB/bin/gh" "$SB/noclaude/gh"
noclaude="$SB/noclaude:$(tr : '\n' <<<"$PATH" | while read -r d; do [ -x "$d/claude" ] || printf '%s:' "$d"; done)"
OUTPUT="$(cd "$SB" && PATH="$noclaude" bash "$GAFFER/chain/chain-next.sh" "$SETTINGS" </dev/null 2>&1)"; RC=$?
ok "claude missing from PATH starts no chain, parks nothing and says so" '[ "$RC" != 0 ] && grep -qF claude <<<"$OUTPUT" && [ "$(chain_calls)" = 12 ] && [ "$(labels_of 13)" = ready ]'

echo "Only its own checkout is ever touched:"
new_case
issues '[{"number":12,"state":"OPEN","labels":["ready"]}]'
git -C "$OTHER" checkout -q -b feature/2-mine
echo mine > "$OTHER/mine.txt"
other_before="$(checkout_state "$OTHER")"
settings "{\"clone\": \"$OTHER\", \"writers\": [\"User:maintainer\"], \"state_dir\": \"$STATE\"}"
fire
ok "a checkout not marked as the runner's is refused" '[ "$RC" != 0 ] && grep -qF "$OTHER" <<<"$OUTPUT" && [ -z "$(chain_calls)" ]'
ok "and left exactly as it was" '[ "$(checkout_state "$OTHER")" = "$other_before" ]'
git -C "$CLONE" worktree add -q "$SB/case$cases/wt" -b wt-branch
settings "{\"clone\": \"$SB/case$cases/wt\", \"writers\": [\"User:maintainer\"], \"state_dir\": \"$STATE\"}"
fire
ok "a worktree of the runner's clone is refused too" '[ "$RC" != 0 ] && [ -z "$(chain_calls)" ]'
settings "{\"clone\": \"$CLONE\", \"writers\": [\"User:maintainer\", \"Bot:claude\"], \"state_dir\": \"$STATE\"}"
fire
ok "while a run in its own clone leaves the other checkout alone" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 12 ] && [ "$(checkout_state "$OTHER")" = "$other_before" ]'

echo "Wrong invocation is refused:"
new_case
fire --bogus
ok "an unknown argument exits 1 with usage, starting nothing" '[ "$RC" = 1 ] && grep -q usage <<<"$OUTPUT" && [ -z "$(chain_calls)" ]'
OUTPUT="$(cd "$SB" && PATH="$SB/bin:$PATH" bash "$GAFFER/chain/chain-next.sh" </dev/null 2>&1)"; RC=$?
ok "no settings file named exits 1 with usage" '[ "$RC" = 1 ] && grep -q usage <<<"$OUTPUT"'

# SCENARIO: The runner brings the plugin clone up to date before a firing
echo "The settings file is read before anything else:"
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
before="$(checkout_state "$CLONE")"
fire_with "$SB/case$cases/no-such.json"
ok "a settings file that does not exist is refused, naming it" '[ "$RC" != 0 ] && grep -qF "no-such.json" <<<"$OUTPUT"'
ok "before anything was queried, reset or run" '[ -z "$(chain_calls)" ] && ! grep -q "^issue|list|" "$STUB_DIR/gh-log" 2>/dev/null && [ "$(checkout_state "$CLONE")" = "$before" ] && [ ! -e "$STATE" ]'
for bad in \
  '{"writers": ["User:maintainer"]}' \
  '{"clone": "CLONE"}' \
  '{"clone": "CLONE", "writers": []}' \
  '{"clone": "CLONE", "writers": ["maintainer"]}' \
  '{"clone": "CLONE", "writers": "User:maintainer"}' \
  '{"clone": "CLONE", "writers": ["User:maintainer"], "writer": ["User:x"]}' \
  '{"clone": "CLONE", "writers": ["User:maintainer"], "labels": {"ready": 1}}' \
  '{"clone": "CLONE", "writers": ["User:maintainer"], "labels": {"queued": "x"}}' \
  '{"clone": "CLONE", "writers": ["User:maintainer"], "labels": {"ready": "same", "parked": "same"}}' \
  '{"clone": "CLONE", "writers": ["User:maintainer"], "skip_permissions": "yes"}' \
  '{"clone": "CLONE", "writers": ["User:maintainer"], "state_dir": ""}' \
  '["not", "an", "object"]' \
  '{"clone": '
do
  new_case
  issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
  settings "${bad//CLONE/$CLONE}"
  fire
  ok "refused with nothing queried, reset or run: $bad" '[ "$RC" != 0 ] && grep -qF "chain.json" <<<"$OUTPUT" && [ -z "$(chain_calls)" ] && ! grep -q "^issue|list|" "$STUB_DIR/gh-log" 2>/dev/null && [ ! -e "$STATE" ]'
done
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
settings "{\"clone\": \"$CLONE\"}"
fire --dry-run
ok "with no writers named, report mode refuses too and says why" '[ "$RC" != 0 ] && grep -qF "writers" <<<"$OUTPUT" && grep -qF "no issue is ever built" <<<"$OUTPUT"'

echo "The settings name the labels, the clone, the permissions and the state:"
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]},{"number":6,"state":"OPEN","labels":["queued"]},{"number":7,"state":"OPEN","labels":["queued","on-hold"]}]'
settings "{\"clone\": \"$CLONE\", \"writers\": [\"User:maintainer\"], \"labels\": {\"ready\": \"queued\", \"parked\": \"on-hold\"}, \"state_dir\": \"$STATE\"}"
touch "$STUB_DIR/fail-6"
fire
ok "the ready label is the one the settings name, and the parked one is passed over" '[ "$RC" != 0 ] && [ "$(chain_calls)" = 6 ]'
ok "a failure parks with the settings' parked label, and the comment names it" '[ "$(labels_of 6)" = "queued,on-hold" ] && grep -qF "Remove the \`on-hold\` label" "$STUB_DIR/comment-6.txt"'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
fire
ok "without skip_permissions the chain is not told to skip them" '[ "$RC" = 0 ] && [ "$(start_of 1 flags)" = "--settings|$SETTINGS|" ]'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
settings "{\"clone\": \"$CLONE\", \"writers\": [\"User:maintainer\"], \"skip_permissions\": true, \"state_dir\": \"$STATE\"}"
fire
ok "with skip_permissions true the chain is handed the opt-in, and the settings file" '[ "$RC" = 0 ] && [ "$(start_of 1 flags)" = "--settings|$SETTINGS|--skip-permissions|" ]'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
HOME="$SB/case$cases/home"; mkdir -p "$HOME/Repos"; mv "$CLONE" "$HOME/Repos/runner"; CLONE="$HOME/Repos/runner"
settings "{\"clone\": \"~/Repos/runner\", \"writers\": [\"User:maintainer\"]}"
fire
ok "a clone written with ~/ is found under the user's home" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 5 ]'
ok "and with no state_dir named, state lives under the user's state directory, per clone" 'ls "$HOME/.local/state/gaffer-chain/runner/logs"/5-*.log >/dev/null 2>&1 && [ -f "$HOME/.local/state/gaffer-chain/runner/lock" ]'
HOME=$(cd ~ && pwd)
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
settings "{\"clone\": \"$SB/case$cases/no-such-clone\", \"writers\": [\"User:maintainer\"], \"state_dir\": \"$STATE\"}"
fire
ok "a clone that does not exist is refused, naming it and the setting" '[ "$RC" != 0 ] && grep -qF "no-such-clone" <<<"$OUTPUT" && grep -qF "clone" <<<"$OUTPUT" && [ -z "$(chain_calls)" ] && [ ! -e "$STATE" ]'

echo "The runner runs only from a plugin checkout that is plainly main:"
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
fire
ok "a clean checkout at its origin's main runs the chain from beside itself" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 5 ]'
ok "and the runner's own output names the plugin commit" 'grep -qF "gaffer at $(git -C "$GAFFER" rev-parse --short HEAD)" <<<"$OUTPUT"'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
advance_gaffer "plugin v2"
fire
ok "a checkout behind its origin's main still runs: being behind is the scheduler's update step to fix, not a fault here" '[ "$RC" = 0 ] && [ "$(chain_calls)" = 5 ]'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
# The local commit touches a file the incoming one does not, so a plain merge would succeed with
# a merge commit: only the ancestry rule refuses this checkout.
echo local-edit > "$GAFFER/LOCAL.md"; commit_all "$GAFFER" "a local commit nobody should lose"
advance_gaffer "plugin v2"
local_head="$(git -C "$GAFFER" rev-parse HEAD)"
before="$(checkout_state "$CLONE")"
fire
ok "a checkout whose main has diverged stops the firing" '[ "$RC" != 0 ] && grep -qF "local commits" <<<"$OUTPUT" && [ -z "$(chain_calls)" ]'
ok "and loses nothing: the local commit is still its head" '[ "$(git -C "$GAFFER" rev-parse HEAD)" = "$local_head" ]'
ok "and the issue is not parked, the clone not reset" '[ "$(gh_writes)" = 0 ] && [ "$(labels_of 5)" = ready ] && [ "$(checkout_state "$CLONE")" = "$before" ]'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
git -C "$GAFFER" checkout -q -b experiment
fire
ok "a checkout on another branch stops the firing, naming the branch" '[ "$RC" != 0 ] && grep -qF experiment <<<"$OUTPUT" && [ -z "$(chain_calls)" ] && [ "$(gh_writes)" = 0 ]'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
echo local-commit > "$GAFFER/CHANGE.md"; commit_all "$GAFFER" "a local commit, origin unmoved"
local_head="$(git -C "$GAFFER" rev-parse HEAD)"
fire
ok "a checkout with local commits stops the firing even when origin has not moved" '[ "$RC" != 0 ] && grep -qF "local commits" <<<"$OUTPUT" && [ -z "$(chain_calls)" ] && [ "$(gh_writes)" = 0 ]'
ok "and its local commit is still its head" '[ "$(git -C "$GAFFER" rev-parse HEAD)" = "$local_head" ]'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
echo "an edit" >> "$GAFFER/.claude-plugin/plugin.json"
fire
ok "a checkout with an uncommitted edit stops the firing" '[ "$RC" != 0 ] && grep -qF "uncommitted or untracked" <<<"$OUTPUT" && [ -z "$(chain_calls)" ] && [ "$(gh_writes)" = 0 ]'
ok "and the edit is kept" 'grep -qF "an edit" "$GAFFER/.claude-plugin/plugin.json"'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
mkdir -p "$GAFFER/commands"; echo "# planted" > "$GAFFER/commands/planted.md"
fire
ok "a checkout with an untracked file stops the firing" '[ "$RC" != 0 ] && grep -qF "uncommitted or untracked" <<<"$OUTPUT" && [ -z "$(chain_calls)" ] && [ "$(gh_writes)" = 0 ]'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
echo "an edit" >> "$GAFFER/.claude-plugin/plugin.json"
fire --dry-run
ok "report mode refuses an edited checkout too, so the fault is seen before the next firing" '[ "$RC" != 0 ] && grep -qF "uncommitted or untracked" <<<"$OUTPUT"'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
rm "$GAFFER/.claude-plugin/plugin.json"; commit_all "$GAFFER" "not a plugin"; git -C "$GAFFER" push -q origin main
fire
ok "a checkout that is not a plugin is refused before selecting anything" '[ "$RC" != 0 ] && grep -qF "plugin.json" <<<"$OUTPUT" && [ -z "$(chain_calls)" ] && ! grep -q "^issue|list|" "$STUB_DIR/gh-log" 2>/dev/null'
new_case
issues '[{"number":5,"state":"OPEN","labels":["ready"]}]'
rm -rf "$GAFFER/.git"
fire
ok "a copy of the plugin that is not a git checkout is refused, since what it holds cannot be checked" '[ "$RC" != 0 ] && grep -qF "not a git checkout" <<<"$OUTPUT" && [ -z "$(chain_calls)" ]'

echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" = 0 ]
