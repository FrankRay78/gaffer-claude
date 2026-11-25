#!/usr/bin/env bash
#
# tracker.tests.sh — standalone test matrix for tracker.sh and the GitHub adapter.
#
# Every case runs in a throwaway git repository under a mktemp sandbox, with a fake `gh` first on
# PATH that keeps a small GitHub — issues, pull requests, comments and labels — in a JSON file, so
# nothing reaches GitHub. It specifies which adapter a setting selects and what is refused before
# the tracker is reached, the calls the GitHub adapter makes (the ones the commands made before the
# interface existed), and it runs conformance.sh against the GitHub adapter. Exits non-zero on any
# failure.
#
#   Usage:  bash tracker/tracker.tests.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKER="$HERE/tracker.sh"
CONFORMANCE="$HERE/conformance.sh"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
unset GAFFER_SETTINGS

# The fake gh. Every call is logged to gh-log, arguments separated by `|`. A file named `fail`
# makes every call print its contents to stderr and exit 1, as gh does on a broken sign-in, and one
# named fail-<command>-<subcommand> (fail-issue-view) does the same for that call alone.
# Comment listings come back two to a page, as --paginate prints them: one array per page.
# Comment timestamps follow `clock`, which each new comment advances by one second.
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
repo=$(jq -r .repo "$S")
opt() { local want=$1 i; for ((i = 2; i <= $#; i++)); do [ "${!i}" = "$want" ] && { i=$((i + 1)); printf '%s' "${!i}"; return 0; }; done; return 1; }
other_repo() { local r; r=$(opt --repo "$@" || opt -R "$@") || return 1; [ "$r" != "$repo" ]; }
missing() { echo "GraphQL: Could not resolve to an issue or pull request with the number of $1. (repository.issue)" >&2; exit 1; }
exists() { jq -e --arg n "$1" '.issues[$n] != null' "$S" >/dev/null; }
case "$1 $2" in
  "repo view") jq -n --arg r "$repo" '{nameWithOwner: $r}' | out ;;
  "issue view")
    other_repo "$@" && missing "$3"
    exists "$3" || missing "$3"
    jq --arg n "$3" '.issues[$n] | {number, title, body, state, url, labels: [.labels[] | {name: .}],
      closedByPullRequestsReferences: [.closing[] | {url: .}]}' "$S" | out ;;
  "issue create")
    title=$(opt --title "$@"); body=$(cat "$(opt --body-file "$@")")
    labels=$(for ((i = 3; i <= $#; i++)); do [ "${!i}" = --label ] && { j=$((i + 1)); printf '%s\n' "${!j}"; }; done | jq -R . | jq -s .)
    n=$(jq -r '.next' "$S")
    save --arg n "$n" --arg t "$title" --arg b "$body" --argjson l "$labels" \
      '.next += 1 | .issues[$n] = {number: ($n | tonumber), title: $t, body: $b, state: "OPEN", labels: $l, closing: [], url: "https://github.com/\(.repo)/issues/\($n)"}'
    echo "https://github.com/$repo/issues/$n" ;;
  "issue edit")
    exists "$3" || missing "$3"
    if l=$(opt --add-label "$@"); then
      jq -e --arg l "$l" 'any(.labels[]; .name == $l)' "$S" >/dev/null || { echo "failed to update: '$l' not found" >&2; exit 1; }
      save --arg n "$3" --arg l "$l" '.issues[$n].labels |= (. + [$l] | unique)'
    fi
    if l=$(opt --remove-label "$@"); then save --arg n "$3" --arg l "$l" '.issues[$n].labels -= [$l]'; fi ;;
  "issue comment")
    exists "$3" || missing "$3"
    if f=$(opt --body-file "$@"); then body=$(cat "$f"); else body=$(opt --body "$@"); fi
    id=$(jq -r .next_comment "$S")
    save --arg n "$3" --arg b "$body" '.clock += 1 | .next_comment += 1
      | .comments += [{id: (.next_comment - 1), issue: ($n | tonumber), body: $b, user: {login: "me"}, created_at: (1767225600 + .clock | todate),
        html_url: "https://github.com/\(.repo)/issues/\($n)#issuecomment-\(.next_comment - 1)"}]'
    echo "https://github.com/$repo/issues/$3#issuecomment-$id" ;;
  "issue close")
    exists "$3" || missing "$3"
    if c=$(opt --comment "$@"); then printf '%s' "$c" > "$STUB_DIR/close-note"; fi
    save --arg n "$3" '.issues[$n].state = "CLOSED"' ;;
  "issue list")
    s=$(opt --search "$@"); s=${s% in:title}
    jq --arg s "$s" '[.issues[] | select(.url | contains("/issues/")) | select(.title | contains($s)) | {number, title, state, url}]' "$S" | out ;;
  "label list") jq '[.labels[] | {name}]' "$S" | out ;;
  "label create") save --arg l "$3" --arg d "$(opt --description "$@")" '.labels += [{name: $l, description: $d}]' ;;
  "api "*)
    method=GET; path=; input=; field=
    shift
    while [ $# -gt 0 ]; do
      case $1 in
        -X|--method) method=$2; shift 2 ;;
        --input) input=$2; shift 2 ;;
        -F|-f) field=$2; shift 2 ;;
        --paginate) shift ;;
        *) path=$1; shift ;;
      esac
    done
    path=${path#/}; path=${path/\{owner\}\/\{repo\}/$repo}
    case "$method $path" in
      "GET repos/$repo/issues/"*/comments)
        n=${path#repos/$repo/issues/}; n=${n%/comments}
        jq -c --arg n "$n" '[.comments[] | select(.issue == ($n | tonumber))] | _nwise(2)' "$S" ;;
      "PATCH repos/$repo/issues/comments/"*)
        id=${path##*/}; body=$(cat "${field#body=@}")
        jq -e --argjson id "$id" 'any(.comments[]; .id == $id)' "$S" >/dev/null || { echo "HTTP 404: Not Found" >&2; exit 1; }
        save --argjson id "$id" --arg b "$body" '(.comments[] | select(.id == $id) | .body) = $b'
        jq --argjson id "$id" '.comments[] | select(.id == $id)' "$S" | out ;;
      "DELETE repos/$repo/issues/comments/"*)
        id=${path##*/}
        jq -e --argjson id "$id" 'any(.comments[]; .id == $id)' "$S" >/dev/null || { echo "HTTP 404: Not Found" >&2; exit 1; }
        save --argjson id "$id" '.comments |= map(select(.id != $id))' ;;
      "PATCH repos/$repo/issues/"*)
        n=${path##*/}; exists "$n" || { echo "HTTP 404: Not Found" >&2; exit 1; }
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
gh_calls() { if [ -f "$STUB_DIR/gh-log" ]; then grep -c '' "$STUB_DIR/gh-log"; else echo 0; fi; }
logged() { grep -qxF -- "$1" "$STUB_DIR/gh-log"; }
reset_log() { rm -f "$STUB_DIR/gh-log"; }
run() { OUT=$(cd "$R" && bash "$TRACKER" "$@" 2>&1); RC=$?; }
# run_out — as run, but stdout alone in OUT.
run_out() { OUT=$(cd "$R" && bash "$TRACKER" "$@" 2>/dev/null); RC=$?; }

echo "The setting:"
fresh; run_out operations
ok "no settings file: the github adapter" '[ $RC = 0 ] && [ "$(jq -r .tracker <<<"$OUT")" = github ]'
fresh; settings '{"pre_review": true}'; run_out operations
ok "a settings file without the key: the github adapter" '[ "$(jq -r .tracker <<<"$OUT")" = github ]'
fresh; settings '{"tracker": "github"}'; mkdir -p "$R/sub"; OUT=$(cd "$R/sub" && bash "$TRACKER" operations 2>/dev/null)
ok "the settings file is found from a subdirectory of the repository" '[ "$(jq -r .settings <<<"$OUT")" = "$R/.gaffer/chain.json" ]'
fresh; settings '{"tracker": "jira"}'; run state-add 7 ready
ok "a tracker with no adapter: exit 78, naming the setting, the tracker and the operation" '[ $RC = 78 ] && grep -qF "\"tracker\"" <<<"$OUT" && grep -qF "\"jira\"" <<<"$OUT" && grep -qF "'"'"'state-add'"'"'" <<<"$OUT"'
ok "… and nothing reached the tracker" '[ "$(gh_calls)" = 0 ]'
fresh; settings '{"tracker": "../github"}'; run view 7
ok "a tracker name that is a path is refused, not followed" '[ $RC = 78 ] && [ "$(gh_calls)" = 0 ]'
fresh; settings '{"tracker": 5}'; run view 7
ok "a tracker that is not a string is refused" '[ $RC = 78 ] && [ "$(gh_calls)" = 0 ]'
fresh; settings '[1]'; run view 7
ok "a settings file that is not an object is refused" '[ $RC = 78 ] && [ "$(gh_calls)" = 0 ]'
fresh; settings '{"tracker": "github"}'; printf '{"tracker": "jira"}' > "$SB/other.json"
OUT=$(cd "$R" && GAFFER_SETTINGS="$SB/other.json" bash "$TRACKER" view 7 2>&1); RC=$?
ok "GAFFER_SETTINGS names the file read, over the repository's own" '[ $RC = 78 ] && grep -qF "$SB/other.json" <<<"$OUT"'
OUT=$(cd "$R" && GAFFER_SETTINGS="$SB/none.json" bash "$TRACKER" view 7 2>&1); RC=$?
ok "a GAFFER_SETTINGS file that does not exist is refused" '[ $RC = 78 ] && [ "$(gh_calls)" = 0 ]'

echo "The contract, before the tracker is reached:"
fresh; run frobnicate 7
ok "an operation outside the contract: exit 2" '[ $RC = 2 ] && [ "$(gh_calls)" = 0 ]'
fresh; run state-add 7 needs_answers
ok "a state outside the closed list: exit 2, naming the states" '[ $RC = 2 ] && grep -qF "needs-answers, ready, parked, audit" <<<"$OUT" && [ "$(gh_calls)" = 0 ]'
fresh; printf b > "$R/b"; run create --title t --body-file b --state Ready
ok "a state outside the list on create: exit 2" '[ $RC = 2 ] && [ "$(gh_calls)" = 0 ]'
fresh; run marker speckit
ok "a marker outside the list: exit 2" '[ $RC = 2 ]'
run comment-find 7 speckit
ok "comment-find with a marker outside the list: exit 2, before gh is run" '[ $RC = 2 ] && [ "$(gh_calls)" = 0 ]'
for c in "--body-file b --title" "--title t --body-file"; do
  OUT=$(cd "$R" && timeout 10 bash "$TRACKER" create $c 2>&1); RC=$?
  ok "create ending in a flag with no value fails rather than hangs: $c" '[ $RC = 1 ] && grep -q usage <<<"$OUT"'
done
fresh; run require view state-add comment-delete search-title
ok "require: every operation the github adapter implements" '[ $RC = 0 ] && [ -z "$OUT" ]'

# A copy of the dispatcher with adapters written here: "partial" implements only ref and view;
# "fake" implements every required operation, writing each call to FAKE_LOG, and recognises keys like PROJ-12.
P="$SB/plugin/tracker"; mkdir -p "$P/adapters"; cp "$TRACKER" "$P/tracker.sh"
cat > "$P/adapters/partial.sh" <<'A'
case $1 in operations) printf 'ref\nview\n' ;; *) echo "partial $*" >> "$FAKE_LOG" ;; esac
A
cat > "$P/adapters/fake.sh" <<'A'
case $1 in
  operations) printf '%s\n' setup ref view create body-set state-add state-remove comment-find comment-post comment-edit link close pr-reference marker ;;
  ref) [ "$2" = --forms ] && shift; [[ $2 =~ ^[A-Z]+-[0-9]+$ ]] || exit 1; echo "$2" ;;
  *) echo "fake $*" >> "$FAKE_LOG" ;;
esac
A
export FAKE_LOG="$SB/fake-log"
prun() { OUT=$(cd "$R" && bash "$P/tracker.sh" "$@" 2>&1); RC=$?; }
fresh; settings '{"tracker": "partial"}'; rm -f "$FAKE_LOG"; prun state-add 7 ready
ok "an adapter without the operation: exit 3, naming the setting and the operation" '[ $RC = 3 ] && grep -qF "\"partial\"" <<<"$OUT" && grep -qF "'"'"'state-add'"'"'" <<<"$OUT"'
ok "… and the adapter was never called" '[ ! -f "$FAKE_LOG" ]'
prun require view state-add
ok "require names the first operation the adapter lacks" '[ $RC = 3 ] && grep -qF "'"'"'state-add'"'"'" <<<"$OUT"'
prun require ref view
ok "require passes for what it implements" '[ $RC = 0 ]'
cat > "$P/adapters/broken.sh" <<'A'
exit 5
A
fresh; settings '{"tracker": "broken"}'
for c in "require view" "view 7" "operations" "comment-delete 7 1"; do
  prun $c
  ok "an adapter that cannot list its operations: '$c' exits 78, never 3" '[ $RC = 78 ] && grep -qF "cannot list its operations" <<<"$OUT"'
done
fresh; settings '{"tracker": "fake"}'; rm -f "$FAKE_LOG"; prun state-add PROJ-12 ready
ok "another tracker: the call reaches its adapter, and gh is never run" '[ $RC = 0 ] && grep -qxF "fake state-add PROJ-12 ready" "$FAKE_LOG" && [ "$(gh_calls)" = 0 ]'
prun branch-ref feature/PROJ-12-add-the-thing
ok "another tracker: branch-ref finds a key with a hyphen in it whole" '[ $RC = 0 ] && [ "$OUT" = PROJ-12 ]'

echo "References (github):"
fresh
for c in "50|50" "#50|50" "007|007" "https://github.com/a/b/issues/5|a/b#5" "a/b#5|a/b#5"; do
  run_out ref "${c%%|*}"; ok "ref ${c%%|*} → ${c#*|}" '[ $RC = 0 ] && [ "$OUT" = "${c#*|}" ]'
done
for c in "" "abc" "5a" "#" "##5" "https://github.com/a/b/pull/5"; do
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
run_out ref --forms https://github.com/a/b/issues/5
ok "ref --forms of another repository's issue mentions it as a/b#5" '[ "$(jq -r .mention <<<"$OUT")" = "a/b#5" ] && [ "$(jq -r .branch <<<"$OUT")" = 5 ]'
ok "ref reaches no tracker" '[ "$(gh_calls)" = 0 ]'
run_out branch-ref feature/248-pr-closing-keyword; ok "branch-ref feature/248-pr-closing-keyword → 248" '[ $RC = 0 ] && [ "$OUT" = 248 ]'
run branch-ref feature/build-command; ok "branch-ref of a branch with no number: no candidate" '[ $RC = 1 ]'
run branch-ref feature/net10-upgrade; ok "branch-ref never takes a number from inside a word" '[ $RC = 1 ]'
run branch-ref feature/248; ok "branch-ref needs the <N>-<slug> shape" '[ $RC = 1 ]'
run branch-ref main; ok "branch-ref of main: no candidate" '[ $RC = 1 ]'
settings '{"github": {"labels": {"ready": ""}}}'
run ref 50; ok "a malformed github.labels is refused by ref too, so the chain finds it before a stage" '[ $RC = 78 ]'
run branch-ref feature/248-x; ok "branch-ref passes on a refusal rather than reading it as no candidate" '[ $RC = 78 ] && grep -qF "github.labels" <<<"$OUT"'
rm -f "$R/.gaffer/chain.json"

echo "The GitHub calls are the ones the commands made:"
fresh; n=$(issue "An issue"); reset_log
run state-add "$n" needs-answers; ok "state-add needs-answers adds the 'needs answers' label" '[ $RC = 0 ] && logged "issue|edit|$n|--add-label|needs answers|"'
run state-remove "$n" needs-answers; ok "state-remove needs-answers removes it" '[ $RC = 0 ] && logged "issue|edit|$n|--remove-label|needs answers|"'
run state-add "$n" ready; ok "state-add ready adds 'ready'" 'logged "issue|edit|$n|--add-label|ready|"'
run state-add "https://github.com/a/b/issues/$n" parked; ok "another repository's issue URL passes --repo" 'logged "issue|edit|$n|--repo|a/b|--add-label|parked|"'
run state-add "https://github.com/o/r/issues/$n" parked; ok "this repository's issue URL passes none" 'logged "issue|edit|$n|--add-label|parked|"'
settings '{"github": {"labels": {"ready": "go"}}, "labels": {"ready": "queued"}}'; reset_log
run state-add "$n" ready; ok "github.labels names the label a state maps to; the runner's labels key does not" 'logged "issue|edit|$n|--add-label|go|"'
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
ok "comment-post posts the file as the body, and returns its id and URL" 'logged "issue|comment|$n|--body-file|c|" && [ "$(jq -r .id <<<"$OUT")" = 1001 ] && [ "$(jq -r ".comments[0].body" "$STUB_DIR/state.json")" = "A comment with \`code\` and \$HOME." ]'
printf 'Edited.\n' > "$R/e"; reset_log
run_out comment-edit "$n" 1001 e
ok "comment-edit patches the comment over REST by its numeric id" 'logged "api|-X|PATCH|repos/{owner}/{repo}/issues/comments/1001|-F|body=@e|--jq|{id, url: .html_url}|" && [ "$(jq -r .id <<<"$OUT")" = 1001 ]'
reset_log; run comment-delete "$n" 1001
ok "comment-delete deletes it over REST" '[ $RC = 0 ] && logged "api|--method|DELETE|repos/{owner}/{repo}/issues/comments/1001|" && [ "$(jq ".comments | length" "$STUB_DIR/state.json")" = 0 ]'
printf 'New body: `x` $y \\ "q"\n' > "$R/b"; reset_log
run_out body-set "$n" b
ok "body-set patches the issue with the file's bytes as the body" 'logged "api|--method|PATCH|repos/{owner}/{repo}/issues/$n|--input|-|--jq|.html_url|" && [ "$(jq -r --arg n "$n" ".issues[\$n].body" "$STUB_DIR/state.json")" = "$(cat "$R/b")" ]'
printf 'Superseded by #9' > "$R/note"; reset_log
run close "$n" note
ok "close closes with the note as its comment" 'logged "issue|close|$n|--comment|Superseded by #9|" && [ "$(jq -r --arg n "$n" ".issues[\$n].state" "$STUB_DIR/state.json")" = CLOSED ]'
reset_log; printf 'An audit.\n' > "$R/ab"; run_out create --title "Codebase audit" --body-file ab --state audit
ok "create with a state labels the new issue, and returns its reference" 'logged "issue|create|--title|Codebase audit|--body-file|ab|--label|audit|" && [ "$(jq -r .ref <<<"$OUT")" = 2 ]'
reset_log; run_out search-title "Codebase audit"
ok "search-title searches every issue's title" 'logged "issue|list|--state|all|--search|Codebase audit in:title|--json|number,title,state,url|--limit|100|" && [ "$(jq -r ".[0].ref" <<<"$OUT")" = 2 ]'
reset_log; m=$(issue "Other"); reset_log; run link "$n" "$m"
ok "link mentions the other issue on this one" 'logged "issue|comment|$n|--body|Related: #$m|"'
reset_log; run link a/b#5 "$m"
ok "on another repository's issue, link names this repository in the mention" 'logged "issue|comment|5|--repo|a/b|--body|Related: o/r#$m|"'

echo "view and comment-find:"
fresh; n=$(issue "Read me" ready "needs answers" bug)
jq --arg n "$n" '.issues[$n].closing = ["https://github.com/o/r/pull/40"]' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
for b in "first <!-- speckit:review -->" "plain" "second <!-- speckit:review -->"; do printf '%s\n' "$b" > "$R/c"; gh issue comment "$n" --body-file "$R/c" >/dev/null; done
# The newest comment gets the lowest id, as ids across GitHub's two id spaces can.
jq '.comments |= map(if .id == 1003 then .id = 900 else . end)' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
run_out view "$n"
ok "view: title, body, state, labels and the states among them" '[ "$(jq -r .title <<<"$OUT")" = "Read me" ] && [ "$(jq -r .state <<<"$OUT")" = open ] && [ "$(jq -c .states <<<"$OUT")" = "[\"needs-answers\",\"ready\"]" ] && [ "$(jq -c .labels <<<"$OUT")" = "[\"ready\",\"needs answers\",\"bug\"]" ]'
ok "view: the closing pull requests as links" '[ "$(jq -c .links <<<"$OUT")" = "[{\"kind\":\"closing-pull-request\",\"url\":\"https://github.com/o/r/pull/40\"}]" ]'
ok "view: every comment, across pages, with numeric ids" '[ "$(jq ".comments | length" <<<"$OUT")" = 3 ] && [ "$(jq -c "[.comments[].id]" <<<"$OUT")" = "[1001,1002,900]" ]'
run_out comment-find "$n" review
ok "comment-find: the newest marker comment by time, not by id" '[ "$(jq -r .id <<<"$OUT")" = 900 ] && grep -q "^second" <<<"$(jq -r .body <<<"$OUT")"'
run_out comment-find "$n" confirmed-decisions
ok "comment-find with no such comment prints null" '[ $RC = 0 ] && [ "$OUT" = null ]'
run view 999
ok "view of no issue: exit 1" '[ $RC = 1 ]'
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
run_out pr-reference "https://github.com/o/r/issues/$open"
ok "this repository's issue URL: linked as #N" '[ "$(jq -r .line <<<"$OUT")" = "Closes #$open" ]'
run_out pr-reference 4
ok "a pull request at that number: none" '[ "$(jq -r .outcome <<<"$OUT")" = none ] && grep -q "pull request" <<<"$(jq -r .reason <<<"$OUT")" && [ "$(jq -r .line <<<"$OUT")" = null ]'
run_out pr-reference "$closed"
ok "a closed issue: none, with Refs #N to keep the trace" '[ "$(jq -r .outcome <<<"$OUT")" = none ] && [ "$(jq -r .line <<<"$OUT")" = "Refs #$closed" ]'
run_out pr-reference 99
ok "no issue or pull request at that number: none" '[ "$(jq -r .outcome <<<"$OUT")" = none ] && grep -q "no issue or pull request #99" <<<"$(jq -r .reason <<<"$OUT")"'
reset_log; run_out pr-reference https://github.com/cli/cli/issues/14353
ok "another repository's issue: none, without looking it up" '[ "$(jq -r .outcome <<<"$OUT")" = none ] && ! grep -q "issue|view" "$STUB_DIR/gh-log"'
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
ok "… with the descriptions the labels have always had" 'logged "label|create|needs answers|--description|A review is posted and awaiting the author'"'"'s answers|" && logged "label|create|parked|--description|An unattended run stopped on this issue; remove to retry|"'
ok "labels are listed by name, beyond the default page" 'logged "label|list|--limit|1000|--json|name|--jq|.[].name|"'
run_out setup
ok "a second setup adds nothing" '[ $RC = 0 ] && ! grep -q "^added:" <<<"$OUT"'
fresh; jq '.labels = []' "$STUB_DIR/state.json" > "$STUB_DIR/s" && mv "$STUB_DIR/s" "$STUB_DIR/state.json"
touch "$STUB_DIR/fail-label-create"; run setup
ok "a label that cannot be created: exit 1, naming it" '[ $RC = 1 ] && grep -qF "could not create label" <<<"$OUT"'
touch "$STUB_DIR/fail"; run setup
ok "a label listing that fails: exit 1" '[ $RC = 1 ]'

echo "Conformance:"
fresh; OUT=$(cd "$R" && bash "$CONFORMANCE" 2>&1); RC=$?
ok "the github adapter meets every operation against the fake gh" '[ $RC = 0 ] && ! grep -q "^not met" <<<"$OUT" && [ "$(grep -c "^met:" <<<"$OUT")" = 16 ]'
# An adapter that is github's in every way but one: its state-remove does nothing.
cp "$HERE/adapters/github.sh" "$P/adapters/github.sh"
cat > "$P/adapters/leaky.sh" <<'A'
[ "$1" = state-remove ] && exit 0
exec bash "$(dirname "$0")/github.sh" "$@"
A
cp "$CONFORMANCE" "$P/conformance.sh"
fresh; settings '{"tracker": "leaky"}'; OUT=$(cd "$R" && bash "$P/conformance.sh" 2>&1); RC=$?
ok "an adapter that misses one operation is named for it, and fails" '[ $RC = 1 ] && grep -q "^not met: state-remove" <<<"$OUT" && grep -qxF "met: state-add" <<<"$OUT"'

# An adapter that is github's but leaves out both optional operations.
cat > "$P/adapters/minimal.sh" <<'A'
if [ "$1" = operations ]; then bash "$(dirname "$0")/github.sh" operations | grep -vxE 'comment-delete|search-title'; exit 0; fi
exec bash "$(dirname "$0")/github.sh" "$@"
A
fresh; settings '{"tracker": "minimal"}'; OUT=$(cd "$R" && bash "$P/conformance.sh" 2>&1); RC=$?
ok "an adapter without the optional operations meets the contract, and the report says which it left out" '[ $RC = 0 ] && grep -qxF "not implemented (optional): comment-delete" <<<"$OUT" && grep -qxF "not implemented (optional): search-title" <<<"$OUT"'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
