#!/usr/bin/env bash
#
# github.sh — the tracker contract (docs/tracker.md) on GitHub issues, through `gh`.
#
# Called by tracker.sh, which has already checked the operation and any state or marker name.
# Each operation makes the call the commands made before the interface existed, so a repository
# on GitHub sees the same labels, comments and edits.
#
# STATES are labels. The names come from `github.labels` in the settings file TRACKER_SETTINGS
# names, each state defaulting to the label the commands have always used.
#
# REFERENCES. `<N>` or `#<N>` is issue N of the repository gh resolves from the working directory;
# an issue URL is `<owner>/<repo>#<N>`, GitHub's own cross-repository form, and every operation
# accepts either.

set -uo pipefail

OPERATIONS=(setup ref view create body-set state-add state-remove comment-find comment-post comment-edit
  comment-delete link close pr-reference marker search-title)

die() { echo "tracker: github: $*" >&2; exit 1; }
need_gh() { command -v gh >/dev/null 2>&1 || die "gh is not on PATH"; }

# The label each state maps to, as "state|label|description" lines.
labels() {
  local defaults='{"needs-answers": "needs answers", "ready": "ready", "parked": "parked", "audit": "audit"}' conf='{}'
  if [ -n "${TRACKER_SETTINGS:-}" ]; then
    conf=$(jq -e 'if .github == null then {} elif (.github | type) == "object" and (.github.labels == null or (.github.labels | type) == "object") then (.github.labels // {}) else error("x") end' "$TRACKER_SETTINGS" 2>/dev/null) \
      || { echo "tracker: github: in $TRACKER_SETTINGS, \"github\" is not an object, or github.labels is not an object; nothing was changed." >&2; exit 78; }
  fi
  jq -e -r --argjson d "$defaults" '
    (keys - ($d | keys)) as $unknown
    | if ($unknown | length) > 0 then error("unknown: " + ($unknown | join(", ")))
      elif any(.[]; type != "string" or length == 0) then error("empty")
      else ($d + .) end
    | to_entries[] | "\(.key)|\(.value)"' <<<"$conf" 2>/dev/null \
    || { echo "tracker: github: in ${TRACKER_SETTINGS:-the settings}, github.labels must map only the states needs-answers, ready, parked and audit, each to a non-empty label name; nothing was changed." >&2; exit 78; }
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

# parse_ref <reference> — sets NUM, REPO_ARGS (--repo, or nothing for this repository) and
# API_REPO, or fails.
parse_ref() {
  local r=$1
  if [[ $r =~ ^#?([0-9]+)$ ]]; then
    NUM=${BASH_REMATCH[1]}; REPO=; REPO_ARGS=(); API_REPO='{owner}/{repo}'
  elif [[ $r =~ ^https://github\.com/([^/[:space:]]+)/([^/[:space:]]+)/issues/([0-9]+)/?$ ]] \
    || [[ $r =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)$ ]]; then
    NUM=${BASH_REMATCH[3]}; REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"; REPO_ARGS=(--repo "$REPO"); API_REPO=$REPO
  else
    return 1
  fi
}
target() { parse_ref "$1" || { echo "tracker: github: '$1' is not a GitHub issue reference (N, #N, an issue URL or owner/repo#N)" >&2; exit 1; }; }
normal() { if [ -n "$REPO" ]; then echo "$REPO#$NUM"; else echo "$NUM"; fi; }

# The issue's comments, every page, as one JSON array. --paginate prints one array per page.
comments() {
  local raw
  raw=$(gh api --paginate "repos/$API_REPO/issues/$NUM/comments") || die "could not list the comments on $(normal)"
  jq -s 'add // [] | map({id, author: .user.login, created_at, body, url: .html_url})' <<<"$raw"
}

op_ref() {
  local forms=0
  [ "${1:-}" = --forms ] && { forms=1; shift; }
  [ $# -eq 1 ] || die "usage: ref [--forms] <reference>"
  parse_ref "$1" || { echo "tracker: github: '$1' is not a GitHub issue reference (N, #N, an issue URL or owner/repo#N)" >&2; exit 1; }
  if [ "$forms" = 1 ]; then
    jq -n -c --arg r "$(normal)" --arg n "$NUM" --arg repo "$REPO" \
      '{ref: $r, branch: $n, mention: (if $repo == "" then "#\($n)" else $r end)}'
  else
    normal
  fi
}

op_view() {
  [ $# -eq 1 ] || die "usage: view <reference>"
  target "$1"; need_gh
  local issue cs map
  issue=$(gh issue view "$NUM" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json number,title,body,state,labels,url,closedByPullRequestsReferences) \
    || die "could not read issue $(normal)"
  cs=$(comments) || exit 1
  map=$(labels | jq -R 'split("|") | {(.[1] | ascii_downcase): .[0]}' | jq -s 'add') || exit 78
  jq -c --arg r "$(normal)" --argjson cs "$cs" --argjson map "$map" '{
      ref: $r, title, body, state: (.state | ascii_downcase), url,
      labels: [.labels[].name],
      states: [.labels[].name | ascii_downcase | $map[.] // empty] | unique,
      links: [(.closedByPullRequestsReferences // [])[] | {kind: "closing-pull-request", url}],
      comments: $cs
    }' <<<"$issue"
}

op_create() {
  local title= body= label url
  local -a label_args=()
  while [ $# -gt 0 ]; do
    case $1 in
      --title) title=${2:-}; shift 2 ;;
      --body-file) body=${2:-}; shift 2 ;;
      --state) label=$(label_of "$2") || exit 78; label_args+=(--label "$label"); shift 2 ;;
      *) die "usage: create --title <title> --body-file <file> [--state <state>]…" ;;
    esac
  done
  [ -n "$title" ] && [ -f "$body" ] || die "usage: create --title <title> --body-file <file> [--state <state>]…"
  need_gh
  url=$(gh issue create --title "$title" --body-file "$body" ${label_args[@]+"${label_args[@]}"}) || die "could not create the issue"
  url=$(tail -n 1 <<<"$url")
  [[ $url =~ /issues/([0-9]+)$ ]] || die "gh created an issue but printed no issue URL: $url"
  jq -n -c --arg r "${BASH_REMATCH[1]}" --arg u "$url" '{ref: $r, url: $u}'
}

op_body_set() {
  [ $# -eq 2 ] && [ -f "$2" ] || die "usage: body-set <reference> <file>"
  target "$1"; need_gh
  local url
  url=$(jq -n --rawfile b "$2" '{body: $b}' | gh api --method PATCH "repos/$API_REPO/issues/$NUM" --input - --jq .html_url) \
    || die "could not replace the body of $(normal)"
  jq -n -c --arg r "$(normal)" --arg u "$url" '{ref: $r, url: $u}'
}

op_state() {
  local flag=$1 label
  shift
  [ $# -eq 2 ] || die "usage: state-add|state-remove <reference> <state>"
  target "$1"; need_gh
  label=$(label_of "$2") || exit 78
  gh issue edit "$NUM" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} "$flag" "$label" >/dev/null || die "could not ${flag#--} '$label' on $(normal)"
}

op_marker() {
  case $1 in
    review) echo '<!-- speckit:review -->' ;;
    confirmed-decisions) echo '<!-- confirmed-decisions -->' ;;
    review-pr) echo '<!-- review-pr -->' ;;
  esac
}

# The newest comment carrying the marker, by created_at: comment ids are not issued in time order
# across GitHub's two id spaces, so they never pick the newest.
op_comment_find() {
  [ $# -eq 2 ] || die "usage: comment-find <reference> <marker name>"
  target "$1"; need_gh
  local marker cs
  marker=$(op_marker "$2")
  [ -n "$marker" ] || { echo "tracker: '$2' is not a marker" >&2; exit 2; }
  cs=$(comments) || exit 1
  jq -c --arg m "$marker" 'map(select(.body | contains($m))) | max_by(.created_at)' <<<"$cs"
}

op_comment_post() {
  [ $# -eq 2 ] && [ -f "$2" ] || die "usage: comment-post <reference> <file>"
  target "$1"; need_gh
  local url
  url=$(gh issue comment "$NUM" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --body-file "$2") || die "could not post the comment on $(normal)"
  url=$(tail -n 1 <<<"$url")
  [[ $url =~ issuecomment-([0-9]+)$ ]] || die "gh posted a comment but printed no comment URL: $url"
  jq -n -c --argjson id "${BASH_REMATCH[1]}" --arg u "$url" '{id: $id, url: $u}'
}

op_comment_edit() {
  [ $# -eq 3 ] && [ -f "$3" ] || die "usage: comment-edit <reference> <comment id> <file>"
  target "$1"; need_gh
  [[ $2 =~ ^[0-9]+$ ]] || die "'$2' is not a comment id"
  gh api -X PATCH "repos/$API_REPO/issues/comments/$2" -F "body=@$3" --jq '{id, url: .html_url}' \
    || die "could not edit comment $2 on $(normal)"
}

op_comment_delete() {
  [ $# -eq 2 ] || die "usage: comment-delete <reference> <comment id>"
  target "$1"; need_gh
  [[ $2 =~ ^[0-9]+$ ]] || die "'$2' is not a comment id"
  gh api --method DELETE "repos/$API_REPO/issues/comments/$2" >/dev/null || die "could not delete comment $2 on $(normal)"
}

# A mention is how GitHub links one issue to another: it puts a cross-reference on both.
op_link() {
  [ $# -eq 2 ] || die "usage: link <reference> <other reference>"
  target "$2"
  local mention
  if [ -n "$REPO" ]; then mention="$REPO#$NUM"; else mention="#$NUM"; fi
  target "$1"; need_gh
  gh issue comment "$NUM" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --body "Related: $mention" >/dev/null || die "could not link $(normal) to $mention"
}

op_close() {
  [ $# -eq 2 ] && [ -f "$2" ] || die "usage: close <reference> <note file>"
  target "$1"; need_gh
  gh issue close "$NUM" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --comment "$(cat "$2")" >/dev/null || die "could not close $(normal)"
}

# Whether the reference names an open issue of this repository, so a pull request body may close it.
# GitHub numbers issues and pull requests from one sequence, `gh issue view` resolves a pull request
# as readily as an issue, and a transferred issue redirects to another number, so only the whole
# URL being this repository's issue URL for that number proves it. A lookup that could not answer
# (auth, network, rate limit) is `unverified`, never `none`: the fix for it is not on the issue.
op_pr_reference() {
  [ $# -eq 1 ] || die "usage: pr-reference <reference>"
  target "$1"
  local this out err rc n line
  unverified() { jq -n -c --arg r "$1" '{outcome: "unverified", reason: $r}'; exit 0; }
  none() { jq -n -c --arg r "$1" --arg l "${2:-}" '{outcome: "none", reason: $r, line: (if $l == "" then null else $l end)}'; exit 0; }
  command -v gh >/dev/null 2>&1 || unverified "gh is not on PATH"
  err=$(mktemp) || die "mktemp failed"
  this=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>"$err") || { out=$(tr '\n' ' ' <"$err"); rm -f "$err"; unverified "${out% }"; }
  n=$(sed 's/^0*//' <<<"$NUM")
  if [ -z "$n" ]; then rm -f "$err"; none "#$NUM is not an issue number"; fi
  if [ -n "$REPO" ] && [ "$REPO" != "$this" ]; then rm -f "$err"; none "$REPO#$NUM is in another repository, not $this"; fi
  out=$(gh issue view "$n" --json number,state,title,url -R "$this" 2>"$err"); rc=$?
  if [ "$rc" != 0 ]; then
    out=$(tr '\n' ' ' <"$err"); rm -f "$err"; out=${out% }
    grep -qF 'Could not resolve to an issue or pull request' <<<"$out" && none "no issue or pull request #$n in $this"
    unverified "$out"
  fi
  rm -f "$err"
  local url state title
  url=$(jq -r '.url' <<<"$out"); state=$(jq -r '.state' <<<"$out"); title=$(jq -r '.title' <<<"$out")
  case $url in
    "https://github.com/$this/pull/$n") none "#$n is a pull request" ;;
    "https://github.com/$this/issues/$n") ;;
    *) none "#$n resolves to $url, not an issue of $this" ;;
  esac
  [ "$state" = OPEN ] || none "#$n is closed" "Refs #$n"
  line="Closes #$n"
  jq -n -c --arg l "$line" --arg r "$n" --arg t "$title" '{outcome: "linked", line: $l, ref: $r, title: $t}'
}

op_search_title() {
  [ $# -eq 1 ] || die "usage: search-title <text>"
  need_gh
  local out
  out=$(gh issue list --state all --search "$1 in:title" --json number,title,state,url --limit 100) || die "could not search issue titles"
  jq -c 'map({ref: (.number | tostring), title, state: (.state | ascii_downcase), url})' <<<"$out"
}

op_setup() {
  [ $# -eq 0 ] || die "usage: setup"
  need_gh
  local existing entry state name
  existing=$(gh label list --limit 1000 --json name --jq '.[].name' 2>/dev/null) || die "could not list labels (gh label list failed)"
  entry=$(labels) || exit 78
  while IFS='|' read -r state name; do
    # GitHub label names are case-insensitive: an existing `Ready` is the `ready` label.
    if grep -qixF -- "$name" <<<"$existing"; then
      echo "present: label $name"
    else
      gh label create "$name" --description "$(description_of "$state")" >/dev/null 2>&1 || die "could not create label '$name'"
      echo "added: label $name"
    fi
  done <<<"$entry"
}

[ $# -ge 1 ] || die "usage: github.sh <operation> [arguments…]"
op=$1; shift
case $op in
  operations) printf '%s\n' "${OPERATIONS[@]}" ;;
  setup) op_setup "$@" ;;
  ref) op_ref "$@" ;;
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
  marker) [ $# -eq 1 ] || die "usage: marker <name>"; op_marker "$1" ;;
  search-title) op_search_title "$@" ;;
  *) die "no such operation: $op" ;;
esac
