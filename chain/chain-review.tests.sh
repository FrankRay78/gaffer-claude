#!/usr/bin/env bash
#
# chain-review.tests.sh — standalone test matrix for chain-review.sh.
#
# What the wrapper adds to the chain is one gate and one stage: the review runs only after the
# chain ends on a pull request, and succeeds only when a review marked `<!-- review-pr -->` was
# posted. Both are provable from outside with a stub `claude` and a stub `gh` first on PATH, so no
# model is called and nothing reaches GitHub. The real chain.sh runs against the stubs, inside a
# throwaway git repo under a mktemp sandbox. chain.tests.sh specifies the chain itself; this
# matrix only checks what the wrapper passes to it and takes from it.
#
#   Usage:  bash chain/chain-review.tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$HERE/chain-review.sh"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
unset CHAIN_MODEL CHAIN_STAGE_TIMEOUT CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS

PR=https://github.com/o/r/pull/9

# The stub claude: one log line per call, arguments `|`-separated; replies with reply-<n>.json and
# exits with rc-<n> where present. Stdin reaching it is recorded, as chain.tests.sh records it.
mkdir -p "$SB/bin"
cat > "$SB/bin/claude" <<'STUB'
#!/usr/bin/env bash
{ for a in "$@"; do printf '%s|' "$a"; done; printf '\n'; } >> "$STUB_DIR/log"
printf '%s\n' "${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS-unset}" >> "$STUB_DIR/bg-wait"
if IFS= read -r -t 0.1 _ <&0 2>/dev/null; then printf 'leaked\n' >> "$STUB_DIR/stdin-leak"; fi
n=$(grep -c '' "$STUB_DIR/log")
cat "$STUB_DIR/reply-$n.json" 2>/dev/null
if [ -f "$STUB_DIR/rc-$n" ]; then exit "$(cat "$STUB_DIR/rc-$n")"; fi
STUB
# The stub gh: logs each call, and answers call n with the text in gh-<n>, or fails without one —
# so a case that expects no GitHub read fails loudly if one is made.
cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
{ for a in "$@"; do printf '%s|' "$a"; done; printf '\n'; } >> "$STUB_DIR/gh-log"
n=$(grep -c '' "$STUB_DIR/gh-log")
[ -f "$STUB_DIR/gh-$n" ] || exit 1
cat "$STUB_DIR/gh-$n"
STUB
chmod +x "$SB/bin/claude" "$SB/bin/gh"

pass=0; fail=0; cases=0
ok() { if eval "$2"; then echo "  ok   $1"; pass=$((pass+1)); else echo "  FAIL $1 -- rc=$RC output:[$OUTPUT]"; fail=$((fail+1)); fi; }

new_case() {
  cases=$((cases+1))
  REPO="$SB/case$cases/repo"
  export STUB_DIR="$SB/case$cases/stub"
  mkdir -p "$REPO" "$STUB_DIR"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.name chain-tests
  git -C "$REPO" config user.email chain-tests@example.invalid
  git -C "$REPO" config commit.gpgsign false
  git -C "$REPO" commit -q --allow-empty -m init
}

reply() {
  jq -n --arg r "$2" --arg s "sess-$1" \
    '{type:"result",subtype:"success",is_error:false,result:$r,session_id:$s}' > "$STUB_DIR/reply-$1.json"
}
# The three chain stages succeeding, raise-pr naming $PR.
chain_ok() {
  reply 1 '{"schema": 1, "outcome": "ready", "branch": "feature/270-x"}'
  reply 2 '{"schema": 1, "outcome": "verified", "branch": "feature/270-x"}'
  reply 3 "{\"schema\": 1, \"outcome\": \"raised\", \"pr\": \"$PR\"}"
}
# counts <before> <after> — the marked-review counts gh reports either side of the review.
counts() { printf '%s\n' "$1" > "$STUB_DIR/gh-1"; printf '%s\n' "$2" > "$STUB_DIR/gh-2"; }

run() { OUTPUT="$(cd "$REPO" && PATH="$SB/bin:$PATH" bash "$WRAPPER" "$@" <<<'never reaches a stage' 2>&1)"; RC=$?; }
calls() { if [ -f "$STUB_DIR/log" ]; then grep -c '' "$STUB_DIR/log"; else echo 0; fi; }
gh_calls() { if [ -f "$STUB_DIR/gh-log" ]; then grep -c '' "$STUB_DIR/gh-log"; else echo 0; fi; }
call() { sed -n "$1p" "$STUB_DIR/log"; }
last_line() { printf '%s\n' "$OUTPUT" | tail -n 1; }

echo "One issue to a reviewed pull request:"
new_case; chain_ok; reply 4 "Reviewed."; counts 0 1
run 270
ok "exits 0" '[ "$RC" = 0 ]'
ok "the chain's three stages, then one review" '[ "$(calls)" = 4 ]'
ok "the review is review-pr on the pull request the chain raised, as the one positional after -p" 'call 4 | grep -qF -- "-p|/gaffer:review-pr $PR|"'
ok "it loads the plugin from this checkout" 'call 4 | grep -qF -- "--plugin-dir|$PLUGIN_ROOT|"'
ok "on opus at high effort by default" 'call 4 | grep -qF -- "--model|opus|" && call 4 | grep -qF -- "--effort|high|"'
ok "it does not skip permissions unless asked" '! call 4 | grep -qF -- "--dangerously-skip-permissions"'
ok "it waits for its own background agents" '[ "$(sed -n 4p "$STUB_DIR/bg-wait")" = 0 ]'
ok "no stage can read the terminal" '[ ! -f "$STUB_DIR/stdin-leak" ]'
ok "the chain's own output is shown" 'grep -qF "chain: done — $PR" <<<"$OUTPUT"'
ok "the review's report is shown" 'grep -qx "Reviewed." <<<"$OUTPUT"'
ok "the marked reviews are counted either side of the review" '[ "$(gh_calls)" = 2 ] && grep -qF "pr|view|$PR|--json|reviews|" "$STUB_DIR/gh-log"'
ok "the closing line names the reviewed pull request" 'last_line | grep -qxF "chain-review: done — $PR reviewed"'

echo "The chain's options reach it, and the review's model follows CHAIN_MODEL:"
new_case; chain_ok; reply 4 "Reviewed."; counts 2 3
OUTPUT="$(cd "$REPO" && CHAIN_MODEL=m-test PATH="$SB/bin:$PATH" bash "$WRAPPER" --skip-permissions '#270' </dev/null 2>&1)"; RC=$?
ok "exits 0 when the pull request already had reviews" '[ "$RC" = 0 ]'
ok "--skip-permissions reaches every chain stage and the review" '[ "$(grep -cF -- "--dangerously-skip-permissions|" "$STUB_DIR/log")" = 4 ]'
ok "the issue reaches the chain as given" 'call 1 | grep -qF -- "-p|/gaffer:build 270|"'
ok "CHAIN_MODEL sets the review's model" 'call 4 | grep -qF -- "--model|m-test|"'

echo "A chain that fails is the chain's failure, and no review runs:"
new_case
reply 1 '{"schema": 1, "outcome": "failed", "reason": "suite red"}'
run 270
ok "exits non-zero" '[ "$RC" = 1 ]'
ok "no later stage, and no review, ran" '[ "$(calls)" = 1 ] && [ "$(gh_calls)" = 0 ]'
ok "the chain's own resume line closes the output" 'last_line | grep -qF "claude --resume sess-1"'
new_case
jq -n '{type:"result",subtype:"success",is_error:true,api_error:"usage_limit_reached",result:"You have hit your limit · resets 3pm",session_id:"s"}' > "$STUB_DIR/reply-1.json"
echo 1 > "$STUB_DIR/rc-1"
run 270
ok "the chain's usage-limit exit code passes through" '[ "$RC" = 75 ] && [ "$(calls)" = 1 ]'
new_case
git -C "$REPO" checkout -q -b elsewhere
run 270
ok "a chain that refuses to start runs nothing, and its exit code passes through" '[ "$RC" = 1 ] && [ "$(calls)" = 0 ] && [ "$(gh_calls)" = 0 ]'

echo "The review is held to its post-condition:"
new_case; chain_ok; reply 4 "Reviewed."; counts 1 1
run 270
ok "a review that posts nothing fails" '[ "$RC" = 1 ] && grep -qF "FAILED at review-pr — the review finished but posted no review marked" <<<"$OUTPUT"'
ok "and says the pull request is open and how to reopen the review" 'grep -qF "$PR is open as the chain left it" <<<"$OUTPUT" && last_line | grep -qF "claude --resume sess-4"'
new_case; chain_ok; reply 4 "Reviewed."; printf '0\n' > "$STUB_DIR/gh-1"
run 270
ok "a count gh cannot read afterwards fails closed" '[ "$RC" = 1 ] && grep -qF "could not read the pull request'"'"'s reviews after" <<<"$OUTPUT"'
new_case; chain_ok
run 270
ok "a count gh cannot read beforehand stops before the review starts" '[ "$RC" = 1 ] && [ "$(calls)" = 3 ] && grep -qF "reviews before the review started" <<<"$OUTPUT"'
new_case; chain_ok; counts 0 1
jq -n '{type:"result",subtype:"error_during_execution",is_error:true,result:"",session_id:"sess-4"}' > "$STUB_DIR/reply-4.json"
run 270
ok "a review claude reports as an error fails, naming it" '[ "$RC" = 1 ] && grep -qF "claude reported an error (error_during_execution)" <<<"$OUTPUT"'
new_case; chain_ok; counts 0 1
jq -n '{type:"result",subtype:"success",is_error:true,api_error:"usage_limit_reached",result:"You have hit your limit · resets 3pm",session_id:"sess-4"}' > "$STUB_DIR/reply-4.json"
echo 1 > "$STUB_DIR/rc-4"
run 270
ok "a review the usage limit stopped exits 75, quoting the reset" '[ "$RC" = 75 ] && grep -qF "usage limit was reached — You have hit your limit · resets 3pm" <<<"$OUTPUT"'
new_case; chain_ok; counts 0 1
printf 'not json\n' > "$STUB_DIR/reply-4.json"
run 270
ok "a reply that is not JSON fails" '[ "$RC" = 1 ] && grep -qF "reply was not a JSON object" <<<"$OUTPUT"'
new_case; chain_ok; reply 4 "Reviewed."; counts 0 1; echo 3 > "$STUB_DIR/rc-4"
run 270
ok "a non-zero exit fails, naming it" '[ "$RC" = 1 ] && grep -qF "claude exited with 3" <<<"$OUTPUT"'

echo "--review-dry-run posts nothing and reads nothing back:"
new_case; chain_ok; reply 4 "Would post: …"
run --review-dry-run 270
ok "exits 0" '[ "$RC" = 0 ]'
ok "the review runs with --dry-run" 'call 4 | grep -qF -- "-p|/gaffer:review-pr $PR --dry-run|"'
ok "the chain is not told about it" '! call 3 | grep -qF -- "--dry-run"'
ok "and GitHub is not read" '[ "$(gh_calls)" = 0 ]'
ok "the closing line says nothing was posted" 'last_line | grep -qF "nothing was posted"'

echo "--dry-run lists the chain's stages and the review, and runs nothing:"
new_case
run --dry-run 270
ok "exits 0, nothing run" '[ "$RC" = 0 ] && [ "$(calls)" = 0 ] && [ "$(gh_calls)" = 0 ]'
ok "the chain's own listing, then the review" 'grep -qF "1. build: /gaffer:build 270" <<<"$OUTPUT" && last_line | grep -qF "then review-pr: /gaffer:review-pr"'
new_case
run --dry-run --settings "$SB/missing.json" 270
ok "a chain refusal in report mode passes through" '[ "$RC" = 78 ] && ! grep -qF "then review-pr" <<<"$OUTPUT"'

echo "Arguments:"
new_case
run --bogus 270
ok "an unknown option is refused before anything runs" '[ "$RC" = 1 ] && [ "$(calls)" = 0 ] && grep -qF "usage: chain-review.sh" <<<"$OUTPUT"'

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
