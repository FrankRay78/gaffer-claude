#!/usr/bin/env bash
#
# tracker.tests.sh — standalone test matrix for tracker.sh, the tracker operations on GitHub.
#
# Every case runs in a throwaway git repository under a mktemp sandbox, with a fake `gh` first on
# PATH that keeps a small GitHub — issues, pull requests, comments and labels — in a JSON file, so
# nothing reaches GitHub. It specifies what is refused before GitHub is reached, where the label
# names come from, and the calls each operation makes (the ones the commands made before the
# interface existed). Exits non-zero on any failure.
#
#   Usage:  bash tracker/tracker.tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKER="$HERE/tracker.sh"
COVERAGE="$HERE/coverage.sh"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
unset GAFFER_SETTINGS

# The fake gh. Every call is logged to gh-log, arguments separated by `|`. A file named `fail`
# makes every call print its contents to stderr and exit 1, as gh does on a broken sign-in, and one
# named fail-<command>-<subcommand> (fail-issue-view) does the same for that call alone.
# Comment listings come back two to a page when --paginate is passed, as gh prints them: one array
# per page; without it, the first page alone. Comment timestamps follow `clock`, which each new
# comment advances by one second. The fake's own repository is `repo`, whose issues are keyed by
# number; an issue of any other repository is keyed `<owner>/<repo>#<N>`, and a call reaches it
# only through --repo or its repos/<owner>/<repo>/ path. A call without --repo goes where gh would
# choose, the state's `default`: the fake's own repository unless a case sets another, as
# `gh repo set-default` or an `upstream` remote does in a fork clone. Labels and issues made in
# another repository are kept apart from the fake's own. `gh --version` prints the version in the
# file gh-version, 2.80.0 if there is none.
mkdir -p "$SB/bin"
cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
S="$STUB_DIR/state.json"
{ for a in "$@"; do printf '%s|' "$a"; done; printf '\n'; } >> "$STUB_DIR/gh-log"
if [ -f "$STUB_DIR/fail" ]; then cat "$STUB_DIR/fail" >&2; exit 1; fi
if [ -f "$STUB_DIR/fail-$1-$2" ]; then cat "$STUB_DIR/fail-$1-$2" >&2; exit 1; fi
save() { jq "$@" "$S" > "$S.tmp" && mv "$S.tmp" "$S"; }
filter=; args=()
while [ $# -gt 0 ]; do case $1 in --jq|-q) filter=$2; shift 2 ;; *) args+=("$1"); shift ;; esac; done
set -- "${args[@]}"
out() { if [ -n "$filter" ]; then jq -r "$filter"; else cat; fi; }
repo=$(jq -r .repo "$S"); dflt=$(jq -r '.default // .repo' "$S")
opt() { local want=$1 i; for ((i = 2; i <= $#; i++)); do [ "${!i}" = "$want" ] && { i=$((i + 1)); printf '%s' "${!i}"; return 0; }; done; return 1; }
# key <owner/repo> <N> — the issue's key in the state.
key() { if [ "$1" = "$repo" ]; then echo "$2"; else echo "$1#$2"; fi; }
# The key of issue $3 in the repository --repo or -R names, else the fake's own.
k=; [ "${1:-}" = issue ] && [ -n "${3:-}" ] && k=$(key "$(opt --repo "$@" || opt -R "$@" || echo "$dflt")" "$3")
missing() { echo "GraphQL: Could not resolve to an issue or pull request with the number of $1. (repository.issue)" >&2; exit 1; }
exists() { jq -e --arg n "$1" '.issues[$n] != null' "$S" >/dev/null; }
case "$1 ${2:-}" in
  "--version ") echo "gh version $(cat "$STUB_DIR/gh-version" 2>/dev/null || echo 2.80.0) (2025-06-01)" ;;
  "repo view") jq -n --arg r "$dflt" '{nameWithOwner: $r}' | out ;;
  "issue view")
    exists "$k" || missing "$3"
    jq --arg n "$k" '.issues[$n] | {number, title, body, state, url, labels: [.labels[] | {name: .}],
      closedByPullRequestsReferences: [.closing[] | {url: .}]}' "$S" | out ;;
  "issue create")
    title=$(opt --title "$@"); body=$(cat "$(opt --body-file "$@")")
    labels=$(for ((i = 3; i <= $#; i++)); do [ "${!i}" = --label ] && { j=$((i + 1)); printf '%s\n' "${!j}"; }; done | jq -R . | jq -s .)
    n=$(jq -r '.next' "$S"); r=$(opt --repo "$@" || echo "$dflt")
    save --arg k "$(key "$r" "$n")" --arg n "$n" --arg r "$r" --arg t "$title" --arg b "$body" --argjson l "$labels" \
      '.next += 1 | .issues[$k] = {number: ($n | tonumber), title: $t, body: $b, state: "OPEN", labels: $l, closing: [], url: "https://github.com/\($r)/issues/\($n)"}'
    echo "https://github.com/$r/issues/$n" ;;
  "issue edit")
    exists "$k" || missing "$3"
    if l=$(opt --add-label "$@"); then
      jq -e --arg l "$l" 'any(.labels[]; .name == $l)' "$S" >/dev/null || { echo "failed to update: '$l' not found" >&2; exit 1; }
      save --arg n "$k" --arg l "$l" '.issues[$n].labels |= (. + [$l] | unique)'
    fi
    if l=$(opt --remove-label "$@"); then save --arg n "$k" --arg l "$l" '.issues[$n].labels -= [$l]'; fi ;;
  "issue comment")
    exists "$k" || missing "$3"
    if f=$(opt --body-file "$@"); then body=$(cat "$f"); else body=$(opt --body "$@"); fi
    id=$(jq -r .next_comment "$S")
    url="$(jq -r --arg n "$k" '.issues[$n].url' "$S")#issuecomment-$id"
    save --arg n "$k" --arg b "$body" --arg u "$url" '.clock += 1 | .next_comment += 1
      | .comments += [{id: (.next_comment - 1), issue: $n, body: $b, user: {login: "me"}, created_at: (1767225600 + .clock | todate), html_url: $u}]'
    echo "$url" ;;
  "issue close")
    exists "$k" || missing "$3"
    if c=$(opt --comment "$@"); then printf '%s' "$c" > "$STUB_DIR/close-note"; fi
    save --arg n "$k" '.issues[$n].state = "CLOSED"' ;;
  "issue list")
    s=$(opt --search "$@"); s=${s% in:title}
    jq --arg s "$s" --arg p "https://github.com/$(opt --repo "$@" || echo "$dflt")/issues/" '[.issues[] | select(.url | startswith($p)) | select(.title | contains($s)) | {number, title, state, url}]' "$S" | out ;;
  "label list")
    if [ "$(opt --repo "$@" || echo "$dflt")" = "$repo" ]; then jq '[.labels[] | {name}]' "$S" | out
    else jq --arg r "$(opt --repo "$@" || echo "$dflt")" '[(.foreign_labels[$r] // [])[] | {name}]' "$S" | out; fi ;;
  "label create")
    r=$(opt --repo "$@" || echo "$dflt")
    if [ "$r" = "$repo" ]; then save --arg l "$3" --arg d "$(opt --description "$@")" '.labels += [{name: $l, description: $d}]'
    else save --arg r "$r" --arg l "$3" '.foreign_labels[$r] += [{name: $l}]'; fi ;;
  "api "*)
    method=GET; path=; input=; field=; paginate=0
    shift
    while [ $# -gt 0 ]; do
      case $1 in
        -X|--method) method=$2; shift 2 ;;
        --input) input=$2; shift 2 ;;
        -F|-f) field=$2; shift 2 ;;
        --paginate) paginate=1; shift ;;
        *) path=$1; shift ;;
      esac
    done
    path=${path#/}; path=${path/\{owner\}\/\{repo\}/$dflt}
    [[ $path =~ ^repos/([^/]+/[^/]+)/issues/(.+)$ ]] || { echo "fake gh: unexpected api $method $path" >&2; exit 1; }
    r=${BASH_REMATCH[1]}; rest=${BASH_REMATCH[2]}
    # A comment id is global; it is this repository's only when its issue is.
    owned() { jq -e --argjson id "$1" --arg r "$r" --arg home "$repo" \
      'any(.comments[]; .id == $id and (if $r == $home then (.issue | test("^[0-9]+$")) else (.issue | startswith($r + "#")) end))' "$S" >/dev/null \
      || { echo "HTTP 404: Not Found" >&2; exit 1; }; }
    case "$method $rest" in
      "GET "*/comments)
        n=$(key "$r" "${rest%/comments}")
        # Pages of two, one array each, and one empty page for no comments, as gh prints them.
        # Not jq's _nwise, which was private and is gone from jq 1.8.
        if [ "$paginate" = 1 ]; then pages='if length == 0 then . else range(0; length; 2) as $i | .[$i:$i + 2] end'; else pages='.[:2]'; fi
        jq -c --arg n "$n" "[.comments[] | select(.issue == \$n)] | $pages" "$S" ;;
      "PATCH comments/"*)
        id=${rest#comments/}; body=$(cat "${field#body=@}"); owned "$id"
        save --argjson id "$id" --arg b "$body" '(.comments[] | select(.id == $id) | .body) = $b'
        jq --argjson id "$id" '.comments[] | select(.id == $id)' "$S" | out ;;
      "DELETE comments/"*)
        id=${rest#comments/}; owned "$id"
        save --argjson id "$id" '.comments |= map(select(.id != $id))' ;;
      "PATCH "*)
        n=$(key "$r" "$rest"); exists "$n" || { echo "HTTP 404: Not Found" >&2; exit 1; }
        body=$(jq -r .body "$input")
        save --arg n "$n" --arg b "$body" '.issues[$n].body = $b'
        jq --arg n "$n" '.issues[$n] | {html_url: .url}' "$S" | out ;;
      *) echo "fake gh: unexpected api $method $path" >&2; exit 1 ;;
    esac ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$SB/bin/gh"
export PATH="$SB/bin:$PATH"
# A PATH with what the script needs but gh.
mkdir -p "$SB/nogh"
for t in bash git jq sed tr grep mktemp rm cat dirname awk tail; do ln -s "$(command -v "$t")" "$SB/nogh/$t"; done

PASS=0; FAIL=0
ok() {
  if eval "$2"; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1"; echo "       rc=$RC output: $OUT"; fi
}

# A fresh repository and an empty fake GitHub, o/r, holding the labels the plugin has always used.
N=0
fresh() {
  N=$((N + 1))
  R="$SB/repo$N"; export STUB_DIR="$SB/stub$N"
  mkdir -p "$R" "$STUB_DIR"
  git -C "$R" init -q -b main
  git -C "$R" remote add origin https://github.com/o/r.git
  jq -n '{repo: "o/r", next: 1, next_comment: 1001, clock: 0, issues: {}, comments: [],
          labels: [{name: "needs answers"}, {name: "ready"}, {name: "parked"}, {name: "audit"}]}' > "$STUB_DIR/state.json"
}
settings() { mkdir -p "$R/.gaffer"; printf '%s' "$1" > "$R/.gaffer/chain.json"; }
# issue <title> [<label>…] — an issue in the fake, its number on stdout.
issue() {
  local t=$1; shift
  printf 'body of %s\n' "$t" > "$STUB_DIR/new-body"
  local -a l=(); local x; for x in "$@"; do l+=(--label "$x"); done
  gh issue create --title "$t" --body-file "$STUB_DIR/new-body" ${l[@]+"${l[@]}"} | sed 's#.*/##'
}
# pr <number> — a pull request at that number, sharing the issues' sequence as on GitHub.
pr() { jq --arg n "$1" '.issues[$n] = {number: ($n | tonumber), title: "a pull request", body: "", state: "MERGED", labels: [], closing: [], url: "https://github.com/o/r/pull/\($n)"} | .next = (($n | tonumber) + 1)' \
  "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"; }
# foreign <owner/repo> <N> — an issue of another repository in the fake, with one comment.
foreign() {
  jq --arg r "$1" --arg n "$2" '.issues["\($r)#\($n)"] = {number: ($n | tonumber), title: "elsewhere", body: "theirs", state: "OPEN", labels: [], closing: [], url: "https://github.com/\($r)/issues/\($n)"}
    | .comments += [{id: 5000, issue: "\($r)#\($n)", body: "their comment", user: {login: "them"}, created_at: "2026-01-01T00:00:00Z", html_url: "https://github.com/\($r)/issues/\($n)#issuecomment-5000"}]' \
    "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
}
home_state() { jq -c '{issues: (.issues | with_entries(select(.key | test("^[0-9]+$")))), comments: [.comments[] | select(.issue | test("^[0-9]+$"))]}' "$STUB_DIR/state.json"; }
gh_calls() { if [ -f "$STUB_DIR/gh-log" ]; then grep -c '' "$STUB_DIR/gh-log"; else echo 0; fi; }
logged() { grep -qxF -- "$1" "$STUB_DIR/gh-log"; }
reset_log() { rm -f "$STUB_DIR/gh-log"; }
run() { OUT=$(cd "$R" && bash "$TRACKER" "$@" 2>&1); RC=$?; }
# run_out — as run, but stdout alone in OUT.
run_out() { OUT=$(cd "$R" && bash "$TRACKER" "$@" 2>/dev/null); RC=$?; }

echo "The settings file:"
fresh; n=$(issue "An issue"); settings '{"tracker": "jira", "pre_review": true}'; reset_log; run state-add "$n" ready
ok "no tracker setting is read: a settings file that names one changes nothing" '[ $RC = 0 ] && logged "issue|edit|$n|--repo|o/r|--add-label|ready|"'
with_label() { jq --arg l "$1" '.labels += [{name: $l}]' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"; }
fresh; n=$(issue "An issue"); with_label go; settings '{"github": {"labels": {"ready": "go"}}}'; mkdir -p "$R/sub"; reset_log
OUT=$(cd "$R/sub" && bash "$TRACKER" state-add "$n" ready 2>&1); RC=$?
ok "the repository's .gaffer/chain.json is found from a subdirectory" '[ $RC = 0 ] && logged "issue|edit|$n|--repo|o/r|--add-label|go|"'
with_label queued; printf '{"github": {"labels": {"ready": "queued"}}}' > "$SB/other.json"; reset_log
OUT=$(cd "$R" && GAFFER_SETTINGS="$SB/other.json" bash "$TRACKER" state-add "$n" ready 2>&1); RC=$?
ok "GAFFER_SETTINGS names the file read, over the repository's own" '[ $RC = 0 ] && logged "issue|edit|$n|--repo|o/r|--add-label|queued|"'
reset_log; OUT=$(cd "$R" && GAFFER_SETTINGS="$SB/none.json" bash "$TRACKER" view "$n" 2>&1); RC=$?
ok "a GAFFER_SETTINGS file that does not exist is refused: exit 78, naming it, before gh is run" '[ $RC = 78 ] && grep -qF "$SB/none.json" <<<"$OUT" && [ "$(gh_calls)" = 0 ]'
fresh; settings '[1]'; run view 7
ok "a settings file that is not an object is refused" '[ $RC = 78 ] && [ "$(gh_calls)" = 0 ]'
fresh; n=$(issue "An issue"); reset_log; run state-add "$n" needs-answers
ok "with no settings file every state has its default label" '[ $RC = 0 ] && logged "issue|edit|$n|--repo|o/r|--add-label|needs answers|"'

echo "Refused before GitHub is reached:"
fresh; run frobnicate 7
ok "an operation that is not one of the interface's: exit 2" '[ $RC = 2 ] && [ "$(gh_calls)" = 0 ]'
ok "… naming exactly the operations the coverage check lists" '[ "$(sed -n "s/.*the operations are //p" <<<"$OUT" | sed "s/, /\n/g" | sort)" = "$(bash "$COVERAGE" --list | sort)" ]'
for c in operations "require view"; do
  run $c; ok "'$c', the dispatcher's own, is gone: exit 2" '[ $RC = 2 ] && [ "$(gh_calls)" = 0 ]'
done
while IFS= read -r c; do
  [ "$c" = setup ] && continue
  run "$c"; ok "$c, an operation the coverage check lists, is one the script performs: with no argument, a usage error" '[ $RC = 2 ] && grep -qF "usage: bash tracker.sh $c" <<<"$OUT" && [ "$(gh_calls)" = 0 ]'
done < <(bash "$COVERAGE" --list)
fresh; run state-add 7 needs_answers
ok "a state outside the closed list: exit 2, naming the states" '[ $RC = 2 ] && grep -qF "needs-answers, ready, parked, audit" <<<"$OUT" && [ "$(gh_calls)" = 0 ]'
run state-remove 7 Ready
ok "… on state-remove too" '[ $RC = 2 ] && [ "$(gh_calls)" = 0 ]'
run state-add not-a-reference needs_answers
ok "… and it is the state that is refused, whatever the reference" '[ $RC = 2 ]'
fresh; printf b > "$R/b"; run create --title t --body-file b --state Ready
ok "a state outside the list on create: exit 2" '[ $RC = 2 ] && [ "$(gh_calls)" = 0 ]'
fresh; run marker speckit
ok "a marker outside the list: exit 2, naming the markers" '[ $RC = 2 ] && grep -qF "review, confirmed-decisions, review-pr" <<<"$OUT"'
run comment-find 7 speckit
ok "comment-find with a marker outside the list: exit 2, before gh is run" '[ $RC = 2 ] && [ "$(gh_calls)" = 0 ]'
for c in "--body-file b --title" "--title t --body-file" "--title t" "--body-file b" "--title t --body-file b --state" "--title t --body-file b --labels x"; do
  OUT=$(cd "$R" && timeout 10 bash "$TRACKER" create $c 2>&1); RC=$?
  ok "create with an argument missing or unknown fails rather than hangs: $c" '[ $RC = 2 ] && grep -q usage <<<"$OUT" && [ "$(gh_calls)" = 0 ]'
done
fresh
for c in "setup now" "ref" "ref --forms" "branch-ref" "view" "view 7 8" "body-set 7" "state-add 7" "state-remove 7" "comment-find 7" \
  "comment-post 7" "comment-edit 7 1" "comment-delete 7" "link 7" "close 7" "pr-reference" "marker" "search-title"; do
  run $c; ok "'$c' with an argument missing or to spare: exit 2, before gh is run" '[ $RC = 2 ] && [ "$(gh_calls)" = 0 ]'
done
for c in "body-set 7 no-such-file" "comment-post 7 no-such-file" "comment-edit 7 1 no-such-file" "close 7 no-such-file"; do
  run $c; ok "'$c': a file that does not exist is a failure, exit 1, before gh is run" '[ $RC = 1 ] && grep -qF "no-such-file" <<<"$OUT" && [ "$(gh_calls)" = 0 ]'
done

echo "References (github):"
fresh
for c in "50|50" "#50|50" "007|007" "https://github.com/a/b/issues/5|a/b#5" "a/b#5|a/b#5"; do
  run_out ref "${c%%|*}"; ok "ref ${c%%|*} → ${c#*|}" '[ $RC = 0 ] && [ "$OUT" = "${c#*|}" ]'
done
for c in "" "abc" "5a" "#" "##5" "https://github.com/a/b/pull/5" 'https://github.com/a/b$(id)/issues/1'; do
  run ref "$c"; ok "ref '$c' is not recognised: exit 1" '[ $RC = 1 ]'
done
run_out ref --forms 50
ok "ref --forms 50: the number in branch names, #50 in commit subjects" '[ "$OUT" = "{\"ref\":\"50\",\"branch\":\"50\",\"mention\":\"#50\"}" ]'
run_out ref https://github.com/o/r/issues/5
ok "an issue URL of this repository (the origin remote) is its bare number" '[ "$OUT" = 5 ]'
run_out ref --forms https://github.com/O/R/issues/5
ok "… whatever its case, so its mention is #5" '[ "$(jq -r .mention <<<"$OUT")" = "#5" ]'
run_out ref "o/r#5"
ok "owner/repo#N naming this repository is the bare number too" '[ "$OUT" = 5 ]'
run ref --forms https://github.com/a/b/issues/5
ok "ref --forms of another repository's issue: exit 1, as a branch name would carry only its number" '[ $RC = 1 ] && grep -qF "another repository" <<<"$OUT"'
ok "ref reaches no tracker" '[ "$(gh_calls)" = 0 ]'
run_out branch-ref feature/248-pr-closing-keyword; ok "branch-ref feature/248-pr-closing-keyword → 248" '[ $RC = 0 ] && [ "$OUT" = 248 ]'
run branch-ref feature/build-command; ok "branch-ref of a branch with no number: no candidate" '[ $RC = 1 ]'
run branch-ref feature/net10-upgrade; ok "branch-ref never takes a number from inside a word" '[ $RC = 1 ]'
run_out branch-ref docs/12-fix-the-guide; ok "branch-ref reads the number after any prefix" '[ $RC = 0 ] && [ "$OUT" = 12 ]'
run branch-ref feature/248; ok "branch-ref needs the <N>-<slug> shape" '[ $RC = 1 ]'
run branch-ref main; ok "branch-ref of main: no candidate" '[ $RC = 1 ]'
settings '{"github": 5}'
run ref 50; ok "a github key that is not an object is refused: exit 78" '[ $RC = 78 ]'
settings '{"github": {"labels": {"ready": ""}}}'
run ref 50; ok "a malformed github.labels is refused by ref too, so a command's first read meets it" '[ $RC = 78 ]'
run branch-ref feature/248-x; ok "branch-ref passes on a refusal rather than reading it as no candidate" '[ $RC = 78 ] && grep -qF "github.labels" <<<"$OUT"'
rm -f "$R/.gaffer/chain.json"

echo "The GitHub calls are the ones the commands made:"
fresh; n=$(issue "An issue"); reset_log
run state-add "$n" needs-answers; ok "state-add needs-answers adds the 'needs answers' label, on the origin repository" '[ $RC = 0 ] && logged "issue|edit|$n|--repo|o/r|--add-label|needs answers|"'
run state-remove "$n" needs-answers; ok "state-remove needs-answers removes it" '[ $RC = 0 ] && logged "issue|edit|$n|--repo|o/r|--remove-label|needs answers|"'
run state-add "$n" ready; ok "state-add ready adds 'ready'" 'logged "issue|edit|$n|--repo|o/r|--add-label|ready|"'
foreign a/b "$n"; before=$(home_state); reset_log
run state-add "https://github.com/a/b/issues/$n" parked; ok "another repository's issue URL passes its --repo, and this repository's issue is untouched" '[ $RC = 0 ] && logged "issue|edit|$n|--repo|a/b|--add-label|parked|" && [ "$(home_state)" = "$before" ]'
run state-add "https://github.com/o/r/issues/$n" parked; ok "this repository's issue URL passes the origin repository" 'logged "issue|edit|$n|--repo|o/r|--add-label|parked|"'
# A fork clone: gh would resolve a bare number to the upstream remote; the script names origin.
git -C "$R" remote add upstream https://github.com/up/r.git; reset_log
run state-add "$n" ready; ok "with an upstream remote beside origin, a bare number still goes to origin" 'logged "issue|edit|$n|--repo|o/r|--add-label|ready|"'
git -C "$R" remote remove upstream
jq '.labels += [{name: "go"}]' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
settings '{"github": {"labels": {"ready": "go"}}, "labels": {"ready": "queued"}}'; reset_log
run state-add "$n" ready; ok "github.labels names the label a state maps to; the runner's labels key does not" '[ $RC = 0 ] && logged "issue|edit|$n|--repo|o/r|--add-label|go|"'
settings '{"github": {"labels": {"done": "x"}}}'; run state-add "$n" ready
ok "github.labels naming no state is refused: exit 78" '[ $RC = 78 ]'
settings '{"github": {"labels": {"ready": ""}}}'; run state-add "$n" ready
ok "an empty label name is refused: exit 78" '[ $RC = 78 ]'
rm -f "$R/.gaffer/chain.json"
for m in "review|<!-- speckit:review -->" "confirmed-decisions|<!-- confirmed-decisions -->" "review-pr|<!-- review-pr -->"; do
  run_out marker "${m%%|*}"; ok "marker ${m%%|*} is ${m#*|}" '[ "$OUT" = "${m#*|}" ]'
done
printf 'A comment with `code` and $HOME.\n' > "$R/c"; reset_log
run_out comment-post "$n" c
ok "comment-post posts the file as the body, and returns its id and URL" 'logged "issue|comment|$n|--repo|o/r|--body-file|c|" && [ "$(jq -r .id <<<"$OUT")" = 1001 ] && [ "$(jq -r ".comments[] | select(.id == 1001) | .body" "$STUB_DIR/state.json")" = "A comment with \`code\` and \$HOME." ]'
printf 'Edited.\n' > "$R/e"; reset_log
run_out comment-edit "$n" 1001 e
ok "comment-edit patches the comment over REST by its numeric id" 'logged "api|-X|PATCH|repos/o/r/issues/comments/1001|-F|body=@e|--jq|{id, url: .html_url}|" && [ "$(jq -r .id <<<"$OUT")" = 1001 ]'
reset_log; run comment-delete "$n" 1001
ok "comment-delete deletes it over REST" '[ $RC = 0 ] && logged "api|--method|DELETE|repos/o/r/issues/comments/1001|" && ! jq -e "any(.comments[]; .id == 1001)" "$STUB_DIR/state.json" >/dev/null'
printf 'New body: `x` $y \\ "q"\n' > "$R/b"; reset_log
run_out body-set "$n" b
ok "body-set patches the issue with the file's bytes as the body" 'logged "api|--method|PATCH|repos/o/r/issues/$n|--input|-|--jq|.html_url|" && [ "$(jq -r --arg n "$n" ".issues[\$n].body" "$STUB_DIR/state.json")" = "$(cat "$R/b")" ]'
printf 'Superseded by #9' > "$R/note"; reset_log
run close "$n" note
ok "close closes with the note as its comment" 'logged "issue|close|$n|--repo|o/r|--comment|Superseded by #9|" && [ "$(jq -r --arg n "$n" ".issues[\$n].state" "$STUB_DIR/state.json")" = CLOSED ]'
reset_log; printf 'An audit.\n' > "$R/ab"; run_out create --title "Codebase audit" --body-file ab --state audit
ok "create with a state labels the new issue, and returns its reference" 'logged "issue|create|--repo|o/r|--title|Codebase audit|--body-file|ab|--label|audit|" && [ "$(jq -r .ref <<<"$OUT")" = 2 ]'
reset_log; run_out search-title "Codebase audit"
ok "search-title searches every issue's title" 'logged "issue|list|--repo|o/r|--state|all|--search|Codebase audit in:title|--json|number,title,state,url|--limit|100|" && [ "$(jq -r ".[0].ref" <<<"$OUT")" = 2 ]'
touch "$STUB_DIR/fail-issue-list"; run search-title "Codebase audit"
ok "a search that fails: exit 1, never an empty list" '[ $RC = 1 ] && ! grep -q "^\[" <<<"$OUT"'
rm -f "$STUB_DIR/fail-issue-list"
reset_log; m=$(issue "Other"); reset_log; run link "$n" "$m"
ok "link mentions the other issue on this one" '[ $RC = 0 ] && logged "issue|comment|$n|--repo|o/r|--body|Related: #$m|"'
foreign a/b 5; reset_log; run link a/b#5 "$m"
ok "on another repository's issue, link names this repository in the mention" '[ $RC = 0 ] && logged "issue|comment|5|--repo|a/b|--body|Related: o/r#$m|"'

echo "A fork clone, where gh's own choice is the upstream repository:"
fork() { git -C "$R" remote add upstream https://github.com/up/r.git
  jq '.default = "up/r" | .labels = []' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"; }
fresh; fork; printf 'A body.\n' > "$R/b"
run_out create --title "Made here" --body-file b
ok "create makes the issue in origin's repository, not upstream's" '[ $RC = 0 ] && [ "$(jq -r .ref <<<"$OUT")" = 1 ] && [ "$(jq -r .url <<<"$OUT")" = https://github.com/o/r/issues/1 ] && [ "$(home_state | jq -r ".issues[\"1\"].title")" = "Made here" ]'
jq '.issues["up/r#1"] = {number: 1, title: "upstream one", body: "", state: "OPEN", labels: [], closing: [], url: "https://github.com/up/r/issues/1"}' \
  "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
run_out view 1
ok "… and view of the reference it returned reads that issue" '[ $RC = 0 ] && [ "$(jq -r .title <<<"$OUT")" = "Made here" ]'
run_out search-title "Made"
ok "search-title searches origin's issues" '[ $RC = 0 ] && [ "$(jq -r ".[0].url" <<<"$OUT")" = https://github.com/o/r/issues/1 ]'
reset_log; run_out pr-reference 1
ok "pr-reference checks the issue against origin's repository, without asking gh which" '[ "$(jq -r .outcome <<<"$OUT")" = linked ] && [ "$(jq -r .title <<<"$OUT")" = "Made here" ] && ! grep -q "^repo|view" "$STUB_DIR/gh-log"'
run_out setup
ok "setup creates the labels in origin's repository" '[ $RC = 0 ] && [ "$(jq -c "[.labels[].name] | sort" "$STUB_DIR/state.json")" = "[\"audit\",\"needs answers\",\"parked\",\"ready\"]" ] && [ "$(jq -c ".foreign_labels // {}" "$STUB_DIR/state.json")" = "{}" ]'
run state-add 1 ready
ok "… so state-add on the issue create made finds its label" '[ $RC = 0 ] && [ "$(home_state | jq -c ".issues[\"1\"].labels")" = "[\"ready\"]" ]'
fresh; git -C "$R" remote remove origin; printf 'A body.\n' > "$R/b"; reset_log
run_out create --title "No origin" --body-file b
ok "with no origin on GitHub, create leaves the repository to gh" '[ $RC = 0 ] && logged "issue|create|--title|No origin|--body-file|b|"'
reset_log; run_out pr-reference 1
ok "… and pr-reference asks gh which repository this is" '[ "$(jq -r .outcome <<<"$OUT")" = linked ] && grep -q "^repo|view" "$STUB_DIR/gh-log"'

echo "Another repository's issue, over REST:"
fresh; n=$(issue "Ours"); printf 'ours\n' > "$R/c"; gh issue comment "$n" --body-file "$R/c" >/dev/null
foreign a/b "$n"; before=$(home_state)
printf 'replaced\n' > "$R/b"; reset_log; run_out body-set "a/b#$n" b
ok "body-set a/b#N patches a/b's issue, not this repository's" '[ $RC = 0 ] && logged "api|--method|PATCH|repos/a/b/issues/$n|--input|-|--jq|.html_url|" && [ "$(jq -r --arg k "a/b#$n" ".issues[\$k].body" "$STUB_DIR/state.json")" = replaced ] && [ "$(home_state)" = "$before" ]'
reset_log; run_out comment-find "a/b#$n" review
ok "comment-find a/b#N lists a/b's comments" '[ $RC = 0 ] && logged "api|--paginate|repos/a/b/issues/$n/comments|" && [ "$OUT" = null ]'
run_out view "a/b#$n"
ok "view a/b#N reads a/b's issue and its comments only" '[ $RC = 0 ] && [ "$(jq -r .title <<<"$OUT")" = elsewhere ] && [ "$(jq -c "[.comments[].id]" <<<"$OUT")" = "[5000]" ]'
reset_log; run comment-edit "a/b#$n" 1001 b
ok "comment-edit a/b#N of this repository's comment id: refused by a/b, and ours is unchanged" '[ $RC = 1 ] && logged "api|-X|PATCH|repos/a/b/issues/comments/1001|-F|body=@b|--jq|{id, url: .html_url}|" && [ "$(home_state)" = "$before" ]'
run_out comment-edit "a/b#$n" 5000 b
ok "comment-edit a/b#N edits a/b's comment" '[ $RC = 0 ] && [ "$(jq -r ".comments[] | select(.id == 5000) | .body" "$STUB_DIR/state.json")" = replaced ]'
reset_log; run comment-delete "a/b#$n" 1001
ok "comment-delete a/b#N of this repository's comment id: refused by a/b, and ours is kept" '[ $RC = 1 ] && logged "api|--method|DELETE|repos/a/b/issues/comments/1001|" && [ "$(home_state)" = "$before" ]'
run comment-delete "a/b#$n" 5000
ok "comment-delete a/b#N deletes a/b's comment" '[ $RC = 0 ] && ! jq -e "any(.comments[]; .id == 5000)" "$STUB_DIR/state.json" >/dev/null'

echo "view and comment-find:"
fresh; n=$(issue "Read me" ready "needs answers" bug)
jq --arg n "$n" '.issues[$n].closing = ["https://github.com/o/r/pull/40"]' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
for b in "first <!-- speckit:review -->" "plain" "second <!-- speckit:review -->"; do printf '%s\n' "$b" > "$R/c"; gh issue comment "$n" --body-file "$R/c" >/dev/null; done
# The newest comment gets the lowest id, so only selection by created_at finds it.
jq '.comments |= map(if .id == 1003 then .id = 900 else . end)' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
run_out view "$n"
ok "view: title, body, state, labels and the states among them" '[ "$(jq -r .title <<<"$OUT")" = "Read me" ] && [ "$(jq -r .state <<<"$OUT")" = open ] && [ "$(jq -c .states <<<"$OUT")" = "[\"needs-answers\",\"ready\"]" ] && [ "$(jq -c .labels <<<"$OUT")" = "[\"ready\",\"needs answers\",\"bug\"]" ]'
ok "view: the closing pull requests as links" '[ "$(jq -c .links <<<"$OUT")" = "[{\"kind\":\"closing-pull-request\",\"url\":\"https://github.com/o/r/pull/40\"}]" ]'
ok "view: every comment, across pages (--paginate), with numeric ids" '[ "$(jq ".comments | length" <<<"$OUT")" = 3 ] && [ "$(jq -c "[.comments[].id]" <<<"$OUT")" = "[1001,1002,900]" ]'
run_out comment-find "$n" review
ok "comment-find: the newest marker comment by time, not by id" '[ "$(jq -r .id <<<"$OUT")" = 900 ] && grep -q "^second" <<<"$(jq -r .body <<<"$OUT")"'
run_out comment-find "$n" confirmed-decisions
ok "comment-find with no such comment prints null" '[ $RC = 0 ] && [ "$OUT" = null ]'
run view 999
ok "view of no issue: exit 1" '[ $RC = 1 ]'
pr 40; run view 40
ok "view of a pull request's number: exit 1, naming it a pull request" '[ $RC = 1 ] && grep -qF "pull request" <<<"$OUT"'
echo 2.72.1 > "$STUB_DIR/gh-version"; reset_log; run view "$n"
ok "view with gh older than 2.73.0: exit 1 naming the version needed, before the issue is read" '[ $RC = 1 ] && grep -qF "gh 2.73.0 or later" <<<"$OUT" && ! grep -q "^issue|view" "$STUB_DIR/gh-log"'
echo 3.0.0 > "$STUB_DIR/gh-version"; run_out view "$n"
ok "… and a later major version passes" '[ $RC = 0 ]'
rm -f "$STUB_DIR/gh-version"
fresh; n=$(issue "Mapped" go Ready)
settings '{"github": {"labels": {"ready": "go"}}}'
run_out view "$n"
ok "view reads states through github.labels" '[ "$(jq -c .states <<<"$OUT")" = "[\"ready\"]" ]'
rm -f "$R/.gaffer/chain.json"; run_out view "$n"
ok "view reads a label of another case as its state" '[ "$(jq -c .states <<<"$OUT")" = "[\"ready\"]" ]'

echo "pr-reference (github):"
fresh; open=$(issue "Open one"); closed=$(issue "Closed one"); gh issue close "$closed" >/dev/null; pr 4
run_out pr-reference "$open"
ok "an open issue of this repository: linked, Closes #N" '[ "$(jq -r .outcome <<<"$OUT")" = linked ] && [ "$(jq -r .line <<<"$OUT")" = "Closes #$open" ] && [ "$(jq -r .title <<<"$OUT")" = "Open one" ]'
run_out pr-reference "000$open"
ok "leading zeros are dropped" '[ "$(jq -r .line <<<"$OUT")" = "Closes #$open" ]'
run_out pr-reference 000
ok "a number that is all zeros: none" '[ $RC = 0 ] && [ "$(jq -r .outcome <<<"$OUT")" = none ]'
OUT=$(cd "$R" && PATH="$SB/nogh" bash "$TRACKER" pr-reference "$open" 2>/dev/null); RC=$?
ok "with gh not on PATH: unverified, and exit 0" '[ $RC = 0 ] && [ "$(jq -r .outcome <<<"$OUT")" = unverified ]'
run_out pr-reference "https://github.com/o/r/issues/$open"
ok "this repository's issue URL: linked as #N" '[ "$(jq -r .line <<<"$OUT")" = "Closes #$open" ]'
run_out pr-reference 4
ok "a pull request at that number: none" '[ "$(jq -r .outcome <<<"$OUT")" = none ] && grep -q "pull request" <<<"$(jq -r .reason <<<"$OUT")" && [ "$(jq -r .line <<<"$OUT")" = null ]'
run_out pr-reference "$closed"
ok "a closed issue: none, with Refs #N to keep the trace" '[ "$(jq -r .outcome <<<"$OUT")" = none ] && [ "$(jq -r .line <<<"$OUT")" = "Refs #$closed" ]'
run_out pr-reference 99
ok "no issue or pull request at that number: none" '[ "$(jq -r .outcome <<<"$OUT")" = none ] && grep -q "no issue or pull request #99" <<<"$(jq -r .reason <<<"$OUT")"'
reset_log; run_out pr-reference https://github.com/cli/cli/issues/14353
ok "another repository's issue: none, without looking it up" '[ "$(jq -r .outcome <<<"$OUT")" = none ] && ! grep -qs "issue|view" "$STUB_DIR/gh-log"'
jq --arg n "$open" '.issues[$n].url = "https://github.com/o/r/issues/77"' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
run_out pr-reference "$open"
ok "an issue that resolves elsewhere (transferred): none" '[ "$(jq -r .outcome <<<"$OUT")" = none ]'
echo "HTTP 502: Bad Gateway" > "$STUB_DIR/fail-issue-view"; run_out pr-reference "$closed"
ok "an issue lookup that fails for another reason: unverified, never none" '[ $RC = 0 ] && [ "$(jq -r .outcome <<<"$OUT")" = unverified ] && grep -q "Bad Gateway" <<<"$(jq -r .reason <<<"$OUT")"'
rm -f "$STUB_DIR/fail-issue-view"
echo "HTTP 401: Bad credentials (https://api.github.com/graphql)" > "$STUB_DIR/fail"; run_out pr-reference "$open"
ok "a lookup that cannot answer: unverified, quoting gh, and exit 0" '[ $RC = 0 ] && [ "$(jq -r .outcome <<<"$OUT")" = unverified ] && grep -q "Bad credentials" <<<"$(jq -r .reason <<<"$OUT")"'

echo "setup (github):"
fresh; jq '.labels = [{name: "Ready"}]' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
run_out setup
ok "setup creates every state's missing label, and counts Ready as ready" '[ $RC = 0 ] && grep -qxF "present: label ready" <<<"$OUT" && grep -qxF "added: label needs answers" <<<"$OUT" && grep -qxF "added: label parked" <<<"$OUT" && grep -qxF "added: label audit" <<<"$OUT"'
ok "… with the descriptions the labels have always had" 'logged "label|create|needs answers|--repo|o/r|--description|A review is posted and awaiting the author'"'"'s answers|" && logged "label|create|parked|--repo|o/r|--description|An unattended run stopped on this issue; remove to retry|"'
ok "labels are listed by name, beyond the default page" 'logged "label|list|--repo|o/r|--limit|1000|--json|name|--jq|.[].name|"'
run_out setup
ok "a second setup adds nothing" '[ $RC = 0 ] && ! grep -q "^added:" <<<"$OUT"'
fresh; jq '.labels = []' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
touch "$STUB_DIR/fail-label-create"; run setup
ok "a label that cannot be created: exit 1, naming it" '[ $RC = 1 ] && grep -qF "could not create label" <<<"$OUT"'
touch "$STUB_DIR/fail"; run setup
ok "a label listing that fails: exit 1" '[ $RC = 1 ]'

echo "What is written reads back:"
fresh; n=$(issue "Round trip")
for st in needs-answers ready parked audit; do
  run state-add "$n" "$st"; run_out view "$n"
  ok "state-add $st: view reads the issue in it" '[ "$(jq --arg s "$st" ".states | index(\$s) != null" <<<"$OUT")" = true ]'
  run state-add "$n" "$st"
  ok "… and adding it again is no error" '[ $RC = 0 ]'
  run state-remove "$n" "$st"; rc=$RC; run_out view "$n"
  ok "state-remove $st: view reads it out again" '[ "$rc" = 0 ] && [ "$(jq --arg s "$st" ".states | index(\$s) == null" <<<"$OUT")" = true ]'
  run state-remove "$n" "$st"
  ok "… and removing it again is no error" '[ $RC = 0 ]'
done
printf 'Body with `code`, a $dollar, a | pipe and a "quote".\n\nSecond paragraph.\n' > "$R/b"
run body-set "$n" b; run_out view "$n"
ok "body-set: the body view reads is the file's" '[ "$(jq -r .body <<<"$OUT")" = "$(cat "$R/b")" ]'
printf 'Done.\n' > "$R/note"; run close "$n" note; run_out view "$n"
ok "close: view reads the issue closed" '[ "$(jq -r .state <<<"$OUT")" = closed ]'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
