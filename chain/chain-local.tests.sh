#!/usr/bin/env bash
#
# chain-local.tests.sh — standalone test matrix for chain-local.sh.
#
# What the wrapper adds to the chain is one gate and one stage: the review runs only after the
# chain ends on this branch's pull request, and succeeds only when a qualifying review was posted.
# Both are provable from outside with a stub `claude` and a stub `gh` first on PATH, so no model is
# called and nothing reaches GitHub. The real chain.sh runs against the stubs, inside a throwaway
# git repo under a mktemp sandbox. chain.tests.sh specifies the chain itself; this matrix checks
# what the wrapper passes to it, what it takes from it, and which reviews count.
#
#   Usage:  bash chain/chain-local.tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$HERE/chain-local.sh"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
unset CHAIN_MODEL CHAIN_STAGE_TIMEOUT CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS

PR=https://github.com/o/r/pull/9
HEAD_SHA=abc123
ME=octocat

# The stub claude: one log line per call, arguments `|`-separated; replies with reply-<n>.json and
# exits with rc-<n> where present. A sleep-<n> file makes call n sleep that many seconds instead,
# for the time limit. Stdin reaching it is recorded, as chain.tests.sh records it.
mkdir -p "$SB/bin"
cat > "$SB/bin/claude" <<'STUB'
#!/usr/bin/env bash
{ for a in "$@"; do printf '%s|' "$a"; done; printf '\n'; } >> "$STUB_DIR/log"
printf '%s\n' "${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS-unset}" >> "$STUB_DIR/bg-wait"
if IFS= read -r -t 0.1 _ <&0 2>/dev/null; then printf 'leaked\n' >> "$STUB_DIR/stdin-leak"; fi
n=$(grep -c '' "$STUB_DIR/log")
if [ -f "$STUB_DIR/sleep-$n" ]; then exec sleep "$(cat "$STUB_DIR/sleep-$n")"; fi
cat "$STUB_DIR/reply-$n.json" 2>/dev/null
if [ -f "$STUB_DIR/rc-$n" ]; then exit "$(cat "$STUB_DIR/rc-$n")"; fi
STUB
# The stub gh answers the reads the wrapper makes as real gh does: it builds the JSON object the
# call asks for, keeps only the fields its --json names, and applies its --jq where it has one. It
# fails where a case gave it nothing to answer with. The data:
#   api user                        → `login`
#   pr view --json …                → `branch-pr` as url (the checked-out branch's pull request)
#   pr view <url> --json …          → `head` as headRefOid, and the k-th reviews read's fixture,
#                                     reviews-<k>.json, as reviews
cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
{ for a in "$@"; do printf '%s|' "$a"; done; printf '\n'; } >> "$STUB_DIR/gh-log"
filter=.; fields=; prev=
for a in "$@"; do
  [ "$prev" = --jq ] && filter=$a
  [ "$prev" = --json ] && fields=$a
  prev=$a
done
answer() { jq -c --arg f "$fields" '. as $o | if $f == "" then . else reduce ($f | split(","))[] as $k ({}; .[$k] = $o[$k]) end' | jq -r "$filter"; }
case "$1 $2" in
  "api user")
    [ -f "$STUB_DIR/login" ] || exit 1
    jq -n --rawfile l "$STUB_DIR/login" '{login: ($l | rtrimstr("\n"))}' | answer ;;
  "pr view")
    case "${3-}" in
      https://*)
        reviews=null
        case ",$fields," in *,reviews,*)
          k=$(( $(cat "$STUB_DIR/review-reads" 2>/dev/null || echo 0) + 1 ))
          echo "$k" > "$STUB_DIR/review-reads"
          [ -f "$STUB_DIR/reviews-$k.json" ] || exit 1
          reviews=$(cat "$STUB_DIR/reviews-$k.json") ;;
        esac
        [ -f "$STUB_DIR/head" ] || exit 1
        jq -n --rawfile h "$STUB_DIR/head" --argjson r "$reviews" '{headRefOid: ($h | rtrimstr("\n")), reviews: $r}' | answer ;;
      *)
        [ -f "$STUB_DIR/branch-pr" ] || exit 1
        jq -n --rawfile u "$STUB_DIR/branch-pr" '{url: ($u | rtrimstr("\n"))}' | answer ;;
    esac ;;
  *) exit 1 ;;
esac
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
  # The defaults every case starts from: signed in as $ME, on the branch whose pull request is $PR.
  printf '%s\n' "$ME" > "$STUB_DIR/login"
  printf '%s\n' "$PR" > "$STUB_DIR/branch-pr"
  printf '%s\n' "$HEAD_SHA" > "$STUB_DIR/head"
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

# A review as `gh pr view --json reviews` shapes it. review <login> <state> <commit> <body>
review() { jq -n -c --arg l "$1" --arg s "$2" --arg c "$3" --arg b "$4" '{author:{login:$l},state:$s,commit:{oid:$c},body:$b}'; }
# What review-pr posts: the marker on the first line, then the tier line.
GOOD_BODY=$'<!-- review-pr -->\n## Review of #9\n\nRisk tier: Low · Human review: Optional\n'
good() { review "$ME" COMMENTED "$HEAD_SHA" "$GOOD_BODY"; }
# reviews <k> <review JSON>… — the fixture for the k-th review read.
reviews() {
  local k=$1; shift
  printf '%s\n' "$@" | jq -s . > "$STUB_DIR/reviews-$k.json"
}
# before_after <review JSON added by the review stage> — no reviews before, that one after.
before_after() { reviews 1; reviews 2 "$1"; }

run() { OUTPUT="$(cd "$REPO" && PATH="$SB/bin:$PATH" bash "$WRAPPER" "$@" <<<'never reaches a stage' 2>&1)"; RC=$?; }
calls() { if [ -f "$STUB_DIR/log" ]; then grep -c '' "$STUB_DIR/log"; else echo 0; fi; }
gh_calls() { if [ -f "$STUB_DIR/gh-log" ]; then grep -c '' "$STUB_DIR/gh-log"; else echo 0; fi; }
review_reads() { if [ -f "$STUB_DIR/gh-log" ]; then grep -c "^pr|view|https://.*|--json|reviews|" "$STUB_DIR/gh-log"; else echo 0; fi; }
call() { sed -n "$1p" "$STUB_DIR/log"; }
last_line() { printf '%s\n' "$OUTPUT" | tail -n 1; }
not_counted() { [ "$RC" = 1 ] && grep -qF "FAILED at review-pr — the review finished but no new review by $ME" <<<"$OUTPUT"; }

echo "One issue to a reviewed pull request:"
new_case; chain_ok; reply 4 "Reviewed."; before_after "$(good)"
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
ok "the reviews are read either side of the review" '[ "$(review_reads)" = 2 ]'
ok "the closing line names the reviewed pull request" 'last_line | grep -qxF "chain-local: done — $PR reviewed"'

echo "Which reviews count:"
new_case; chain_ok; reply 4 "Reviewed."; reviews 1 "$(good)"; reviews 2 "$(good)" "$(good)"
run 270
ok "a qualifying review counts on top of earlier ones" '[ "$RC" = 0 ]'
new_case; chain_ok; reply 4 "Reviewed."; before_after "$(review "$ME" COMMENTED "$HEAD_SHA" $'\n'"$GOOD_BODY")"
run 270
ok "the marker need not open the body" '[ "$RC" = 0 ]'
new_case; chain_ok; reply 4 "Reviewed."; before_after "$(review someone-else COMMENTED "$HEAD_SHA" "$GOOD_BODY")"
run 270
ok "a marked review by another account does not count" 'not_counted'
ok "and the failure says the pull request is open and how to reopen the review" 'grep -qF "$PR is open as the chain left it" <<<"$OUTPUT" && last_line | grep -qF "claude --resume sess-4"'
new_case; chain_ok; reply 4 "Reviewed."; before_after "$(review "$ME" PENDING "$HEAD_SHA" "$GOOD_BODY")"
run 270
ok "a pending review does not count" 'not_counted'
new_case; chain_ok; reply 4 "Reviewed."; before_after "$(review "$ME" COMMENTED other-sha "$GOOD_BODY")"
run 270
ok "a review on another commit does not count" 'not_counted'
ok "the head commit is read once, before the review, so a push during it cannot disown it" '[ "$(grep -c -- "--json|headRefOid|" "$STUB_DIR/gh-log")" = 1 ]'
new_case; chain_ok; reply 4 "Reviewed."; ME=octo_acme; printf '%s\n' "$ME" > "$STUB_DIR/login"
before_after "$(review "$ME" COMMENTED "$HEAD_SHA" "$GOOD_BODY")"
run 270
ok "a login with an underscore, as an Enterprise Managed User has, is accepted" '[ "$RC" = 0 ]'
new_case; chain_ok; reply 4 "Reviewed."; ME='a" or true or "'; printf '%s\n' "$ME" > "$STUB_DIR/login"
before_after "$(review someone-else COMMENTED "$HEAD_SHA" "$GOOD_BODY")"
run 270
ok "a login is matched as data, so one that reads as jq cannot widen the filter" 'not_counted'
ME=octocat
new_case; chain_ok; reply 4 "Reviewed."; before_after "$(review "$ME" COMMENTED "$HEAD_SHA" $'<!-- review-pr -->\nNo tier line.')"
run 270
ok "a review without the Risk tier line does not count" 'not_counted'
new_case; chain_ok; reply 4 "Reviewed."; before_after "$(review "$ME" COMMENTED "$HEAD_SHA" $'Looks good.\nRisk tier: Low')"
run 270
ok "an unmarked review does not count" 'not_counted'
new_case; chain_ok; reply 4 "Reviewed."; reviews 1 "$(good)"; reviews 2 "$(good)"
run 270
ok "a review stage that posts nothing fails" 'not_counted'

echo "The pull request reviewed must be this branch's:"
new_case; chain_ok; printf '%s\n' https://github.com/other/repo/pull/5 > "$STUB_DIR/branch-pr"
run 270
ok "a chain naming another pull request than the branch's runs no review" '[ "$RC" = 1 ] && [ "$(calls)" = 3 ] && grep -qF "the checked-out branch'"'"'s pull request is https://github.com/other/repo/pull/5; no review ran" <<<"$OUTPUT"'
ok "and does not suggest reviewing the refused pull request by hand" '! grep -qF "/gaffer:review-pr" <<<"$OUTPUT"'
new_case; chain_ok; rm "$STUB_DIR/branch-pr"
run 270
ok "a branch gh finds no pull request for runs no review" '[ "$RC" = 1 ] && [ "$(calls)" = 3 ] && grep -qF "gh found no pull request for the checked-out branch" <<<"$OUTPUT"'

echo "The chain's options reach it, and the review's model follows CHAIN_MODEL:"
new_case; chain_ok; reply 4 "Reviewed."; before_after "$(good)"
OUTPUT="$(cd "$REPO" && CHAIN_MODEL=m-test PATH="$SB/bin:$PATH" bash "$WRAPPER" --skip-permissions '#270' </dev/null 2>&1)"; RC=$?
ok "exits 0" '[ "$RC" = 0 ]'
ok "--skip-permissions reaches every chain stage and the review" '[ "$(grep -cF -- "--dangerously-skip-permissions|" "$STUB_DIR/log")" = 4 ]'
ok "the issue reaches the chain as given" 'call 1 | grep -qF -- "-p|/gaffer:build #270|"'
ok "CHAIN_MODEL sets the review's model" 'call 4 | grep -qF -- "--model|m-test|"'
new_case
reply 1 '{"schema": 1, "outcome": "ready", "branch": "feature/270-x"}'
reply 2 '{"schema": 1, "outcome": "verified", "branch": "feature/270-x"}'
reply 3 "{\"schema\": 1, \"outcome\": \"raised\", \"pr\": \"$PR\"}"
reply 4 "{\"schema\": 1, \"outcome\": \"pre-reviewed\", \"pr\": \"$PR\"}"
reply 5 "Reviewed."; before_after "$(good)"
printf '{"pre_review": true}' > "$SB/case$cases/settings.json"
run --settings "$SB/case$cases/settings.json" 270
ok "with the pre-review on, --settings reaches the chain and the review follows the fourth stage" '[ "$RC" = 0 ] && call 3 | grep -qF -- "-p|/gaffer:raise-pr --draft 270|" && call 4 | grep -qF -- "-p|/gaffer:pre-review|" && call 5 | grep -qF -- "-p|/gaffer:review-pr $PR|"'

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
new_case
run
ok "with no arguments, the chain's own usage is shown" '[ "$RC" = 1 ] && grep -qF "usage: chain.sh" <<<"$OUTPUT" && ! grep -qF "unbound variable" <<<"$OUTPUT"'

echo "The review's own failures:"
new_case; chain_ok; before_after "$(good)"; rm "$STUB_DIR/login"
run 270
ok "an account gh cannot name stops before the review starts" '[ "$RC" = 1 ] && [ "$(calls)" = 3 ] && grep -qF "could not name the account" <<<"$OUTPUT"'
ok "and, the pull request being confirmed, names it and offers the review again" 'grep -qF "$PR is open as the chain left it" <<<"$OUTPUT" && last_line | grep -qF "/gaffer:review-pr $PR"'
new_case; chain_ok; reply 4 "Reviewed."; reviews 1
run 270
ok "reviews gh cannot read afterwards fail closed" '[ "$RC" = 1 ] && grep -qF "could not read the pull request'"'"'s reviews after" <<<"$OUTPUT"'
new_case; chain_ok
run 270
ok "reviews gh cannot read beforehand stop before the review starts" '[ "$RC" = 1 ] && [ "$(calls)" = 3 ] && grep -qF "gh could not read the pull request'"'"'s reviews; no review ran" <<<"$OUTPUT"'
new_case; chain_ok; before_after "$(good)"; rm "$STUB_DIR/head"
run 270
ok "a head commit gh cannot read stops before the review starts" '[ "$RC" = 1 ] && [ "$(calls)" = 3 ] && grep -qF "could not read the pull request'"'"'s head commit" <<<"$OUTPUT"'
new_case; chain_ok; before_after "$(good)"
jq -n '{type:"result",subtype:"error_during_execution",is_error:true,result:"",session_id:"sess-4"}' > "$STUB_DIR/reply-4.json"
run 270
ok "a review claude reports as an error fails, naming it" '[ "$RC" = 1 ] && grep -qF "claude reported an error (error_during_execution)" <<<"$OUTPUT"'
new_case; chain_ok; before_after "$(good)"
jq -n '{type:"result",subtype:"success",is_error:true,api_error:"usage_limit_reached",result:"You have hit your limit · resets 3pm",session_id:"sess-4"}' > "$STUB_DIR/reply-4.json"
echo 1 > "$STUB_DIR/rc-4"
run 270
ok "a review the usage limit stopped exits 75, quoting the reset" '[ "$RC" = 75 ] && grep -qF "usage limit was reached — You have hit your limit · resets 3pm" <<<"$OUTPUT"'
new_case; chain_ok; before_after "$(good)"
jq -n '{type:"result",subtype:"success",is_error:true,api_error:"usage_limit_reached",result:"",session_id:"sess-4"}' > "$STUB_DIR/reply-4.json"
echo 1 > "$STUB_DIR/rc-4"
run 270
ok "a usage-limit reply with no text says it gave no reset time" '[ "$RC" = 75 ] && grep -qF "usage limit was reached; the reply gave no reset time" <<<"$OUTPUT"'
new_case; chain_ok; before_after "$(good)"
printf 'not json\n' > "$STUB_DIR/reply-4.json"
run 270
ok "a reply that is not JSON fails" '[ "$RC" = 1 ] && grep -qF "reply was not a JSON object" <<<"$OUTPUT"'
new_case; chain_ok; before_after "$(good)"
printf 'not json\n' > "$STUB_DIR/reply-4.json"; echo 2 > "$STUB_DIR/rc-4"
run 270
ok "a reply that is not JSON from a failed exit names the exit" '[ "$RC" = 1 ] && grep -qF "claude exited with 2" <<<"$OUTPUT"'
new_case; chain_ok; reply 4 "Reviewed."; before_after "$(good)"; echo 3 > "$STUB_DIR/rc-4"
run 270
ok "a non-zero exit fails, naming it" '[ "$RC" = 1 ] && grep -qF "claude exited with 3" <<<"$OUTPUT"'
new_case; chain_ok; before_after "$(good)"; echo 126 > "$STUB_DIR/rc-4"
run 270
ok "an exit of 126 is a review that could not be launched" '[ "$RC" = 1 ] && grep -qF "the review could not be launched (exit 126)" <<<"$OUTPUT"'
new_case; chain_ok; before_after "$(good)"; echo 5 > "$STUB_DIR/sleep-4"
OUTPUT="$(cd "$REPO" && CHAIN_STAGE_TIMEOUT=1 PATH="$SB/bin:$PATH" bash "$WRAPPER" 270 </dev/null 2>&1)"; RC=$?
ok "a review past CHAIN_STAGE_TIMEOUT is stopped and reported as a stall" '[ "$RC" = 1 ] && grep -qF "stalled or killed (exit 124), limit 1s" <<<"$OUTPUT"'

echo "--review-dry-run posts nothing and reads no reviews:"
new_case; chain_ok; reply 4 "Would post: …"
run --review-dry-run 270
ok "exits 0" '[ "$RC" = 0 ]'
ok "the review runs with --dry-run" 'call 4 | grep -qF -- "-p|/gaffer:review-pr $PR --dry-run|"'
ok "the chain runs its own stages, not told about it" '[ "$(calls)" = 4 ] && call 1 | grep -qF -- "-p|/gaffer:build 270|"'
ok "the branch's pull request is still checked, and no review is read" '[ "$(gh_calls)" = 1 ] && [ "$(review_reads)" = 0 ]'
ok "the closing line says nothing was posted" 'last_line | grep -qF "nothing was posted"'

echo "--dry-run lists the chain's stages and the review, and runs nothing:"
new_case
run --dry-run 270
ok "exits 0, nothing run" '[ "$RC" = 0 ] && [ "$(calls)" = 0 ] && [ "$(gh_calls)" = 0 ]'
ok "the chain's own listing, then the review" 'grep -qF "1. build: /gaffer:build 270" <<<"$OUTPUT" && last_line | grep -qF "then review-pr: /gaffer:review-pr"'
new_case
run --dry-run --review-dry-run 270
ok "with --review-dry-run too, the listing says the review posts nothing" 'grep -qF "review-pr <the pull request raise-pr opens> --dry-run" <<<"$OUTPUT" && last_line | grep -qF "review: dry run, nothing posted"'
new_case
run --dry-run --settings "$SB/missing.json" 270
ok "a chain refusal in report mode passes through" '[ "$RC" = 78 ] && ! grep -qF "then review-pr" <<<"$OUTPUT"'

echo "Arguments:"
new_case
run --bogus 270
ok "an unknown option is refused before anything runs" '[ "$RC" = 1 ] && [ "$(calls)" = 0 ] && grep -qF "usage: chain-local.sh" <<<"$OUTPUT"'
new_case
run --settings
ok "--settings with no file is refused before anything runs" '[ "$RC" = 1 ] && [ "$(calls)" = 0 ] && grep -qF "usage: chain-local.sh" <<<"$OUTPUT"'
new_case
run -h
ok "-h shows the usage and runs nothing" '[ "$RC" = 0 ] && [ "$(calls)" = 0 ] && grep -qF "usage: chain-local.sh" <<<"$OUTPUT"'

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
