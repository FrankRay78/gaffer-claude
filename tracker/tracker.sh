#!/usr/bin/env bash
#
# tracker.sh — every tracker operation on GitHub issues, through `gh`.
#
#   bash tracker.sh <operation> [arguments…]
#
# The script the plugin's interface file, TRACKER.md beside this file, has a command run for each
# operation it names. The operations are the list coverage.sh holds; docs/tracker.md states each
# one's arguments, output and outcome. Each operation the commands used before the interface
# existed makes the call they made, so a repository on GitHub sees the same labels, comments and
# edits; `link` is new, a mention comment.
#
# STATES are labels. The names come from `github.labels` in the settings file — the one
# GAFFER_SETTINGS names, else .gaffer/chain.json at the root of the repository this runs in — each
# state defaulting to the label the commands have always used, so a repository with no settings
# file, or none of that key, needs nothing. No other key of the file is read.
#
# REFERENCES. `<N>` or `#<N>` is issue N of this repository, the origin remote's. An issue URL or
# `<owner>/<repo>#<N>` naming this repository normalises to the bare `N`; naming another, to
# `<owner>/<repo>#<N>`, GitHub's own cross-repository form. Every operation accepts any of them.
# Every call names its repository — the reference's, else origin's — with --repo or its REST path,
# never leaving gh to choose one: in a fork clone, gh's own choice (gh repo set-default, an
# `upstream` remote) is another repository. The calls that take no reference (create,
# search-title, setup, pr-reference) go to origin too. Only where origin is not a GitHub URL is the
# choice left to gh.
#
# EXIT. 0 success; 1 the operation failed, or a reference is not one GitHub recognises; 2 bad
# usage — a missing argument, or an operation, state or marker that is not one of the interface's;
# 78 the settings file cannot be read or its github.labels is malformed. On 2 and 78 no gh call has
# been made. Tests: tracker.tests.sh beside this file.

set -uo pipefail

OPERATIONS=(setup ref branch-ref view create body-set state-add state-remove comment-find comment-post
  comment-edit comment-delete link close pr-reference marker search-title)
STATES=(needs-answers ready parked audit)
MARKERS=(review confirmed-decisions review-pr)
CONFIG_EXIT=78

die() { echo "tracker: $*" >&2; exit 1; }
# usage <operation and its arguments> — bad usage, refused before any gh call.
usage() { echo "tracker: usage: bash tracker.sh $1" >&2; exit 2; }
refused() { echo "tracker: refused — $1; nothing was changed." >&2; exit "$CONFIG_EXIT"; }
in_list() { local x=$1; shift; local y; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }
joined() { printf '%s, ' "$@" | sed 's/, $//'; }
check_state() { in_list "$1" "${STATES[@]}" || { echo "tracker: '$1' is not a state; the states are $(joined "${STATES[@]}")" >&2; exit 2; }; }
check_marker() { in_list "$1" "${MARKERS[@]}" || { echo "tracker: '$1' is not a marker; the markers are $(joined "${MARKERS[@]}")" >&2; exit 2; }; }
need_file() { [ -f "$1" ] || die "no such file: $1"; }

# The settings file, located once: the one GAFFER_SETTINGS names — the chain sets it for every
# stage to the file it read itself — else the repository's own, if it has one.
if [ -n "${GAFFER_SETTINGS:-}" ]; then
  SETTINGS=$GAFFER_SETTINGS
else
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$PWD
  SETTINGS="$root/.gaffer/chain.json"
  [ -f "$SETTINGS" ] || SETTINGS=
fi

need_gh() { command -v gh >/dev/null 2>&1 || die "gh is not on PATH"; }
# need_gh_version <major> <minor> <why> — refuse an older gh, which would fail the call with only
# `Unknown JSON field`. A version gh does not print is let through to fail on its own.
need_gh_version() {
  local v
  v=$(gh --version 2>/dev/null | sed -n '1s/^gh version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')
  [ -n "$v" ] || return 0
  set -- "$1" "$2" "$3" $v
  [ "$4" -gt "$1" ] || { [ "$4" = "$1" ] && [ "$5" -ge "$2" ]; } || die "needs gh $1.$2.0 or later ($3); this gh is $4.$5"
}

# The label each state maps to, as "state|label" lines.
labels() {
  local defaults='{"needs-answers": "needs answers", "ready": "ready", "parked": "parked", "audit": "audit"}' conf='{}'
  if [ -n "$SETTINGS" ]; then
    [ -f "$SETTINGS" ] || refused "the settings file $SETTINGS (GAFFER_SETTINGS) does not exist"
    jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1 || refused "the settings file $SETTINGS is not a JSON object"
    conf=$(jq -e 'if .github == null then {} elif (.github | type) == "object" and (.github.labels == null or (.github.labels | type) == "object") then (.github.labels // {}) else error("x") end' "$SETTINGS" 2>/dev/null) \
      || refused "in $SETTINGS, \"github\" is not an object, or github.labels is not an object"
  fi
  jq -e -r --argjson d "$defaults" '
    (keys - ($d | keys)) as $unknown
    | if ($unknown | length) > 0 then error("unknown: " + ($unknown | join(", ")))
      elif any(.[]; type != "string" or length == 0) then error("empty")
      else ($d + .) end
    | to_entries[] | "\(.key)|\(.value)"' <<<"$conf" 2>/dev/null \
    || refused "in ${SETTINGS:-the settings}, github.labels must map only the states $(joined "${STATES[@]}"), each to a non-empty label name"
}
label_of() { labels | awk -F'|' -v s="$1" '$1 == s { print $2 }'; }

description_of() {
  case $1 in
    needs-answers) echo "A review is posted and awaiting the author's answers" ;;
    ready) echo "The issue is confirmed and may be built" ;;
    parked) echo "An unattended run stopped on this issue; remove to retry" ;;
    audit) echo "A codebase audit's findings, raised by /gaffer:audit-codebase" ;;
  esac
}

lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }

# This repository's owner/repo, read from the origin remote's URL — locally, as `ref` must not reach
# GitHub. Empty when origin is not a GitHub URL.
origin_repo() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 0
  [[ $url =~ github\.com[:/]([^/]+)/([^/]+)$ ]] && echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
}
# home_args — sets HOME_ARGS to --repo <origin>, for a call that takes no reference.
home_args() { local here; here=$(origin_repo); if [ -n "$here" ]; then HOME_ARGS=(--repo "$here"); else HOME_ARGS=(); fi; }

# parse_ref <reference> — sets NUM, REPO, REPO_ARGS and API_REPO, or fails. REPO is the display
# repository: owner/repo, or empty for this repository, so a URL or owner/repo#N naming this
# repository is mentioned as #N. REPO_ARGS and API_REPO are where the calls go: REPO, else origin.
# Only where origin is not on GitHub is the choice left to gh.
parse_ref() {
  local r=$1 here
  if [[ $r =~ ^#?([0-9]+)$ ]]; then
    NUM=${BASH_REMATCH[1]}; REPO=
  elif [[ $r =~ ^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/issues/([0-9]+)/?$ ]] \
    || [[ $r =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)$ ]]; then
    NUM=${BASH_REMATCH[3]}; REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    [ "$(lower "$REPO")" != "$(lower "$(origin_repo)")" ] || REPO=
  else
    return 1
  fi
  here=${REPO:-$(origin_repo)}
  if [ -n "$here" ]; then REPO_ARGS=(--repo "$here"); API_REPO=$here; else REPO_ARGS=(); API_REPO='{owner}/{repo}'; fi
}
target() { parse_ref "$1" || die "'$1' is not a GitHub issue reference (N, #N, an issue URL or owner/repo#N)"; }
normal() { if [ -n "$REPO" ]; then echo "$REPO#$NUM"; else echo "$NUM"; fi; }
mention() { if [ -n "$REPO" ]; then echo "$REPO#$NUM"; else echo "#$NUM"; fi; }

# The issue's comments, every page, as one JSON array. --paginate prints one array per page.
# Every REST path here is written without a leading `/`: Git Bash on Windows rewrites `/repos/...`
# as a filesystem path.
comments() {
  local raw
  raw=$(gh api --paginate "repos/$API_REPO/issues/$NUM/comments") || die "could not list the comments on $(normal)"
  jq -s 'add // [] | map({id, author: .user.login, created_at, body, url: .html_url})' <<<"$raw"
}

op_ref() {
  local forms=0
  [ "${1:-}" = --forms ] && { forms=1; shift; }
  [ $# -eq 1 ] || usage "ref [--forms] <reference>"
  target "$1"
  if [ "$forms" = 1 ]; then
    # A branch name carries only the number, which read back is this repository's issue N.
    [ -z "$REPO" ] || die "$REPO#$NUM is an issue of another repository, which no branch name here can carry"
    jq -n -c --arg r "$(normal)" --arg n "$NUM" --arg m "$(mention)" '{ref: $r, branch: $n, mention: $m}'
  else
    normal
  fi
}

# The reference a branch named <prefix>/<N>-<slug> carries: the number leading the name after the
# prefix, with a slug after it, so a number inside a word (net10) is never taken for one.
op_branch_ref() {
  [ $# -eq 1 ] || usage "branch-ref <branch>"
  local pattern='^[^/]+/([0-9]+)-.'
  [[ $1 =~ $pattern ]] || die "the branch $1 carries no issue reference (it is not <prefix>/<N>-<slug>)"
  echo "${BASH_REMATCH[1]}"
}

op_view() {
  [ $# -eq 1 ] || usage "view <reference>"
  target "$1"; need_gh; need_gh_version 2 73 "view reads closedByPullRequestsReferences"
  local issue cs map
  issue=$(gh issue view "$NUM" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json number,title,body,state,labels,url,closedByPullRequestsReferences) \
    || die "could not read issue $(normal)"
  # gh issue view resolves a pull request number too, and its state can be MERGED.
  jq -e '.url | test("/issues/[0-9]+$")' <<<"$issue" >/dev/null || die "$(normal) is a pull request, not an issue"
  cs=$(comments) || exit 1
  map=$(labels | jq -R 'split("|") | {(.[1] | ascii_downcase): .[0]}' | jq -s 'add') || exit "$CONFIG_EXIT"
  jq -c --arg r "$(normal)" --argjson cs "$cs" --argjson map "$map" '{
      ref: $r, title, body, state: (.state | ascii_downcase), url,
      labels: [.labels[].name],
      states: [.labels[].name | ascii_downcase | $map[.] // empty] | unique,
      links: [(.closedByPullRequestsReferences // [])[] | {kind: "closing-pull-request", url}],
      comments: $cs
    }' <<<"$issue"
}

op_create() {
  local title= body= label url form="create --title <title> --body-file <file> [--state <state>]…"
  local -a label_args=()
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage "$form"
    case $1 in
      --title) title=$2; shift 2 ;;
      --body-file) body=$2; shift 2 ;;
      --state) check_state "$2"; label=$(label_of "$2") || exit "$CONFIG_EXIT"; label_args+=(--label "$label"); shift 2 ;;
      *) usage "$form" ;;
    esac
  done
  [ -n "$title" ] && [ -n "$body" ] || usage "$form"
  need_file "$body"
  need_gh; home_args
  url=$(gh issue create ${HOME_ARGS[@]+"${HOME_ARGS[@]}"} --title "$title" --body-file "$body" ${label_args[@]+"${label_args[@]}"}) || die "could not create the issue"
  url=$(tail -n 1 <<<"$url")
  [[ $url =~ /issues/([0-9]+)$ ]] || die "gh created an issue but printed no issue URL: $url"
  jq -n -c --arg r "${BASH_REMATCH[1]}" --arg u "$url" '{ref: $r, url: $u}'
}

op_body_set() {
  [ $# -eq 2 ] || usage "body-set <reference> <file>"
  need_file "$2"; target "$1"; need_gh
  local url
  url=$(jq -n --rawfile b "$2" '{body: $b}' | gh api --method PATCH "repos/$API_REPO/issues/$NUM" --input - --jq .html_url) \
    || die "could not replace the body of $(normal)"
  jq -n -c --arg r "$(normal)" --arg u "$url" '{ref: $r, url: $u}'
}

op_state() {
  local flag=$1 label name=state-add
  [ "$flag" = --add-label ] || name=state-remove
  shift
  [ $# -eq 2 ] || usage "$name <reference> <state>"
  check_state "$2"; target "$1"; need_gh
  label=$(label_of "$2") || exit "$CONFIG_EXIT"
  gh issue edit "$NUM" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "$flag" "$label" >/dev/null || die "could not ${flag#--} '$label' on $(normal)"
}

op_marker() {
  [ $# -eq 1 ] || usage "marker <name>"
  check_marker "$1"
  case $1 in
    review) echo '<!-- speckit:review -->' ;;
    confirmed-decisions) echo '<!-- confirmed-decisions -->' ;;
    review-pr) echo '<!-- review-pr -->' ;;
  esac
}

# The newest comment carrying the marker, by created_at.
op_comment_find() {
  [ $# -eq 2 ] || usage "comment-find <reference> <marker name>"
  check_marker "$2"; target "$1"; need_gh
  local marker cs
  marker=$(op_marker "$2")
  cs=$(comments) || exit 1
  jq -c --arg m "$marker" 'map(select(.body | contains($m))) | max_by(.created_at)' <<<"$cs"
}

op_comment_post() {
  [ $# -eq 2 ] || usage "comment-post <reference> <file>"
  need_file "$2"; target "$1"; need_gh
  local url
  url=$(gh issue comment "$NUM" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --body-file "$2") || die "could not post the comment on $(normal)"
  url=$(tail -n 1 <<<"$url")
  [[ $url =~ issuecomment-([0-9]+)$ ]] || die "gh posted a comment but printed no comment URL: $url"
  jq -n -c --argjson id "${BASH_REMATCH[1]}" --arg u "$url" '{id: $id, url: $u}'
}

op_comment_edit() {
  [ $# -eq 3 ] || usage "comment-edit <reference> <comment id> <file>"
  need_file "$3"; target "$1"; need_gh
  [[ $2 =~ ^[0-9]+$ ]] || die "'$2' is not a comment id"
  gh api -X PATCH "repos/$API_REPO/issues/comments/$2" -F "body=@$3" --jq '{id, url: .html_url}' \
    || die "could not edit comment $2 on $(normal)"
}

op_comment_delete() {
  [ $# -eq 2 ] || usage "comment-delete <reference> <comment id>"
  target "$1"; need_gh
  [[ $2 =~ ^[0-9]+$ ]] || die "'$2' is not a comment id"
  gh api --method DELETE "repos/$API_REPO/issues/comments/$2" >/dev/null || die "could not delete comment $2 on $(normal)"
}

# A mention is how GitHub links one issue to another: it puts a cross-reference on both.
op_link() {
  [ $# -eq 2 ] || usage "link <reference> <other reference>"
  target "$2"
  local other here full
  other=$(mention); full=$other; here=$(origin_repo)
  [ -n "$REPO" ] || [ -z "$here" ] || full="$here#$NUM"
  target "$1"; need_gh
  # On another repository's issue, #N would name that repository's issue N.
  [ -z "$REPO" ] || other=$full
  gh issue comment "$NUM" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --body "Related: $other" >/dev/null || die "could not link $(normal) to $other"
}

op_close() {
  [ $# -eq 2 ] || usage "close <reference> <note file>"
  need_file "$2"; target "$1"; need_gh
  gh issue close "$NUM" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --comment "$(cat "$2")" >/dev/null || die "could not close $(normal)"
}

# Whether the reference names an open issue of this repository, so a pull request body may close it.
# GitHub numbers issues and pull requests from one sequence, `gh issue view` resolves a pull request
# as readily as an issue, and a transferred issue redirects to another number, so only the whole
# URL being this repository's issue URL for that number proves it. A lookup that could not answer
# (auth, network, rate limit) is `unverified`, never `none`: the fix for it is not on the issue.
op_pr_reference() {
  [ $# -eq 1 ] || usage "pr-reference <reference>"
  target "$1"
  local this out err rc n
  unverified() { jq -n -c --arg r "$1" '{outcome: "unverified", reason: $r}'; exit 0; }
  none() { jq -n -c --arg r "$1" --arg l "${2:-}" '{outcome: "none", reason: $r, line: (if $l == "" then null else $l end)}'; exit 0; }
  command -v gh >/dev/null 2>&1 || unverified "gh is not on PATH"
  err=$(mktemp) || die "mktemp failed"
  # This repository is origin's, as for every other call; gh is asked only where origin is not on GitHub.
  this=$(origin_repo)
  [ -n "$this" ] || this=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>"$err") || { out=$(tr '\n' ' ' <"$err"); rm -f "$err"; unverified "${out% }"; }
  n=$(sed 's/^0*//' <<<"$NUM")
  if [ -z "$n" ]; then rm -f "$err"; none "#$NUM is not an issue number"; fi
  if [ -n "$REPO" ] && [ "$(lower "$REPO")" != "$(lower "$this")" ]; then rm -f "$err"; none "$REPO#$NUM is in another repository, not $this"; fi
  out=$(gh issue view "$n" --json number,state,title,url -R "$this" 2>"$err"); rc=$?
  if [ "$rc" != 0 ]; then
    out=$(tr '\n' ' ' <"$err"); rm -f "$err"; out=${out% }
    grep -qF 'Could not resolve to an issue or pull request' <<<"$out" && none "no issue or pull request #$n in $this"
    unverified "$out"
  fi
  rm -f "$err"
  local url state title
  url=$(jq -er '.url | strings' <<<"$out" 2>/dev/null) || unverified "gh gave no issue URL for #$n: $out"
  state=$(jq -r '.state' <<<"$out"); title=$(jq -r '.title' <<<"$out")
  case $(lower "$url") in
    "$(lower "https://github.com/$this/pull/$n")") none "#$n is a pull request" ;;
    "$(lower "https://github.com/$this/issues/$n")") ;;
    *) none "#$n resolves to $url, not an issue of $this" ;;
  esac
  [ "$state" = OPEN ] || none "#$n is closed" "Refs #$n"
  jq -n -c --arg l "Closes #$n" --arg r "$n" --arg t "$title" '{outcome: "linked", line: $l, ref: $r, title: $t}'
}

op_search_title() {
  [ $# -eq 1 ] || usage "search-title <text>"
  need_gh; home_args
  local out
  out=$(gh issue list ${HOME_ARGS[@]+"${HOME_ARGS[@]}"} --state all --search "$1 in:title" --json number,title,state,url --limit 100) || die "could not search issue titles"
  jq -c 'map({ref: (.number | tostring), title, state: (.state | ascii_downcase), url})' <<<"$out"
}

op_setup() {
  [ $# -eq 0 ] || usage "setup"
  need_gh; home_args
  local existing mapping state name
  existing=$(gh label list ${HOME_ARGS[@]+"${HOME_ARGS[@]}"} --limit 1000 --json name --jq '.[].name' 2>/dev/null) || die "could not list labels (gh label list failed)"
  mapping=$(labels) || exit "$CONFIG_EXIT"
  while IFS='|' read -r state name; do
    # GitHub label names are case-insensitive: an existing `Ready` is the `ready` label.
    if grep -qixF -- "$name" <<<"$existing"; then
      echo "present: label $name"
    else
      gh label create "$name" ${HOME_ARGS[@]+"${HOME_ARGS[@]}"} --description "$(description_of "$state")" >/dev/null 2>&1 || die "could not create label '$name'"
      echo "added: label $name"
    fi
  done <<<"$mapping"
}

[ $# -ge 1 ] || usage "<operation> [arguments…]"
op=$1; shift
in_list "$op" "${OPERATIONS[@]}" \
  || { echo "tracker: '$op' is not a tracker operation; the operations are $(joined "${OPERATIONS[@]}")" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is not on PATH"
# A settings file that cannot be read, or a malformed github.labels, is refused by every operation,
# ref included, so a command's first read of the issue meets it before anything is changed.
labels >/dev/null || exit "$CONFIG_EXIT"
case $op in
  setup) op_setup "$@" ;;
  ref) op_ref "$@" ;;
  branch-ref) op_branch_ref "$@" ;;
  view) op_view "$@" ;;
  create) op_create "$@" ;;
  body-set) op_body_set "$@" ;;
  state-add) op_state --add-label "$@" ;;
  state-remove) op_state --remove-label "$@" ;;
  comment-find) op_comment_find "$@" ;;
  comment-post) op_comment_post "$@" ;;
  comment-edit) op_comment_edit "$@" ;;
  comment-delete) op_comment_delete "$@" ;;
  link) op_link "$@" ;;
  close) op_close "$@" ;;
  pr-reference) op_pr_reference "$@" ;;
  marker) op_marker "$@" ;;
  search-title) op_search_title "$@" ;;
esac
