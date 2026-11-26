#!/usr/bin/env bash
#
# setup.sh — the mechanical part of /gaffer:init.
#
# Wires a repository for the plugin, in the checkout as it stands: the files every command assumes.
# The judgement part of init (reading the repository and filling CONVENTIONS.md and REVIEW.md) is
# the command's; this script does only what a person would otherwise type from
# docs/getting-started.md, so it can be tested without a model.
#
#   bash setup.sh check [<repo>]                 can init run here? Changes nothing.
#   bash setup.sh files [--git-ignore] [<repo>]  ensure the settings entries, the git-ignore line,
#                                                the memory index and the CLAUDE.md imports.
#
# <repo> defaults to the current directory and must be the root of a git work tree. Any branch
# will do, clean or not, with or without a remote: nothing here commits, pushes, switches branch
# or reaches a host.
#
# --git-ignore keeps what init writes out of git, for a repository whose owner has not agreed to
# carry it. Each path init manages is added to .git/info/exclude, the ignore file that belongs to
# this clone and is never committed, and .gitignore is left alone. A path git already tracks cannot
# be hidden that way, so it is reported as `tracked:` and a change to it still shows.
#
# OUTPUT. One line per item, `<status>: <item>`, for the command's report. `check` prints `ready`
# or `not ready: <reason>`. `files` prints `added:` for something it puts in place and `present:`
# for something already there, and `skipped:` for the CONVENTIONS.md import when there is no
# CONVENTIONS.md. Without --git-ignore it also prints `ignored: <path>` for any file it manages
# that the repository git-ignores, since a commit will not carry it; with it, `tracked: <path>`
# as above.
#
# IDEMPOTENT. Anything already present is left exactly as it is, including a setting the
# repository has deliberately turned off: a second run of `files` changes no byte. A file is only
# rewritten when something in it is missing; .claude/settings.json is then re-serialised by jq, so
# its entries are kept but its indentation may change.
#
# EXIT. 0 on success (including `ready`); 1 on `not ready` or an unreadable settings file, with
# nothing changed by the step that failed; 2 on bad usage.
#
# Needs git and jq. Run with `bash`; nothing relies on an executable bit.

set -uo pipefail

MARKETPLACE='gaffer-claude'
MARKETPLACE_SOURCE='{"source":{"source":"github","repo":"FrankRay78/gaffer-claude"}}'
PLUGINS=('gaffer@gaffer-claude' 'pr-review-toolkit@claude-plugins-official')
ASK_RULE='Bash(chmod:*)'
SCRATCH='.claude/scratch/'
MEMORY_INDEX='.claude/memory/MEMORY.md'
MEMORY_HEADER='<!-- Memory index: one line per entry, `- [Title](file.md) — one-line hook`. -->'
# What --git-ignore keeps out of git: every path init or a later command writes, as patterns
# anchored at the repository root.
LOCAL_ONLY=(/CONVENTIONS.md /REVIEW.md /CLAUDE.md /.claude/settings.json /.claude/memory/ "/$SCRATCH")
usage() { echo "usage: bash setup.sh check [<repo>] | files [--git-ignore] [<repo>]" >&2; exit 2; }
fail() { echo "error: $*" >&2; exit 1; }

[ $# -ge 1 ] || usage
MODE=$1; shift
GIT_IGNORE=0
REPO=''
for arg in "$@"; do
  case "$arg" in
    --git-ignore) [ "$MODE" = files ] || usage; GIT_IGNORE=1 ;;
    -*)           usage ;;
    *)            [ -z "$REPO" ] || usage; REPO=$arg ;;
  esac
done
REPO=${REPO:-.}
cd "$REPO" 2>/dev/null || fail "no such directory: $REPO"
top=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not a git repository: $REPO"
[ "$(cd "$top" && pwd -P)" = "$(pwd -P)" ] || fail "not the root of the work tree: $REPO (the root is $top)"

# ---------------------------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------------------------
do_check() {
  command -v jq >/dev/null || { echo "not ready: jq is not on the path"; exit 1; }
  echo "ready"
}

# ---------------------------------------------------------------------------------------------
# files
# ---------------------------------------------------------------------------------------------

# Prints what the settings file is missing, one item per line, and writes the merged file to $1.
settings_merge() {
  local out=$1 src='.claude/settings.json' json
  if [ -f "$src" ]; then
    json=$(cat "$src")
    jq -e 'type == "object"' >/dev/null 2>&1 <<<"$json" || fail "$src is not a JSON object; fix it and re-run (nothing was changed)"
  else
    json='{}'
  fi
  jq --arg m "$MARKETPLACE" --argjson ms "$MARKETPLACE_SOURCE" --arg ask "$ASK_RULE" \
     --args '
    def ensure(path; v): if (getpath(path) == null) then setpath(path; v) else . end;
    ensure(["extraKnownMarketplaces", $m]; $ms)
    | reduce $ARGS.positional[] as $p (.; ensure(["enabledPlugins", $p]; true))
    | if ((.permissions.ask // []) | index($ask)) then . else .permissions.ask = ((.permissions.ask // []) + [$ask]) end
  ' "${PLUGINS[@]}" <<<"$json" > "$out" || fail "could not merge $src"
  jq -r --arg m "$MARKETPLACE" --arg ask "$ASK_RULE" --args '
    (if .extraKnownMarketplaces[$m] == null then "marketplace \($m)" else empty end),
    ($ARGS.positional[] as $p | if .enabledPlugins[$p] == null then "plugin \($p)" else empty end),
    (if ((.permissions.ask // []) | index($ask)) then empty else "permission ask \($ask)" end)
  ' "${PLUGINS[@]}" <<<"$json"
}

report_settings() {
  local tmp missing
  tmp=$(mktemp) || fail "mktemp failed"
  missing=$(settings_merge "$tmp") || { rm -f "$tmp"; exit 1; }
  if [ -n "$missing" ]; then
    mkdir -p .claude
    mv "$tmp" .claude/settings.json
  else
    rm -f "$tmp"
  fi
  local item
  for item in "marketplace $MARKETPLACE" "${PLUGINS[@]/#/plugin }" "permission ask $ASK_RULE"; do
    if grep -qxF "$item" <<<"$missing"; then echo "added: .claude/settings.json $item"; else echo "present: .claude/settings.json $item"; fi
  done
}

# append_line <file> <line> — the line on a line of its own, whatever the file ends with.
append_line() {
  if [ -s "$1" ] && [ -n "$(tail -c1 "$1")" ]; then printf '\n' >> "$1"; fi
  printf '%s\n' "$2" >> "$1"
}

# Whether git ignores the path, by any rule. --no-index, so a tracked file answers by the rules
# too; a directory is asked about through a file inside it.
is_ignored() {
  local path=$1
  case "$path" in */) path="${path}probe" ;; esac
  git check-ignore -q --no-index "$path" 2>/dev/null
}

ensure_ignored() {
  if is_ignored "$SCRATCH"; then
    echo "present: $SCRATCH git-ignored"
    return
  fi
  append_line .gitignore "$SCRATCH"
  echo "added: $SCRATCH git-ignored (.gitignore)"
}

# --git-ignore. git rev-parse finds the exclude file, which a linked work tree shares with its
# main one.
ensure_excluded() {
  local exclude pattern path
  exclude=$(git rev-parse --git-path info/exclude) || fail "could not find this clone's exclude file"
  for pattern in "${LOCAL_ONLY[@]}"; do
    path=${pattern#/}
    if [ -n "$(git ls-files -- "$path")" ]; then
      echo "tracked: $path"
    elif is_ignored "$path"; then
      echo "present: $path git-ignored"
    else
      mkdir -p "$(dirname "$exclude")"
      append_line "$exclude" "$pattern"
      echo "added: $path git-ignored (.git/info/exclude)"
    fi
  done
}

ensure_memory_index() {
  if [ -f "$MEMORY_INDEX" ]; then
    echo "present: $MEMORY_INDEX"
    return
  fi
  mkdir -p "$(dirname "$MEMORY_INDEX")"
  printf '%s\n' "$MEMORY_HEADER" > "$MEMORY_INDEX"
  echo "added: $MEMORY_INDEX"
}

# An import counts as present when a line of CLAUDE.md is exactly `@<path>` or `@./<path>`.
has_import() { grep -qE "^@(\./)?$(sed 's/[.]/\\./g' <<<"$1")[[:space:]]*$" CLAUDE.md 2>/dev/null; }

ensure_import() {
  local path=$1
  if has_import "$path"; then
    echo "present: CLAUDE.md imports $path"
    return
  fi
  if [ -s CLAUDE.md ]; then
    [ -n "$(tail -c1 CLAUDE.md)" ] && printf '\n' >> CLAUDE.md
    printf '\n@%s\n' "$path" >> CLAUDE.md
  else
    printf '@%s\n' "$path" >> CLAUDE.md
  fi
  echo "added: CLAUDE.md imports $path"
}

do_files() {
  command -v jq >/dev/null || fail "jq is not on the path"
  report_settings
  [ "$GIT_IGNORE" = 1 ] || ensure_ignored
  ensure_memory_index
  # CONVENTIONS.md is imported only once it exists: the command writes it before calling this, and
  # leaves it out when the repository gave it nothing to say.
  if [ -f CONVENTIONS.md ]; then ensure_import CONVENTIONS.md; else echo "skipped: CLAUDE.md import of CONVENTIONS.md (no CONVENTIONS.md)"; fi
  ensure_import "$MEMORY_INDEX"
  if [ "$GIT_IGNORE" = 1 ]; then
    ensure_excluded
  else
    report_ignored .claude/settings.json "$MEMORY_INDEX" CLAUDE.md .gitignore CONVENTIONS.md REVIEW.md
  fi
}

# A file git ignores is in no commit, even though it is written here. A file git already tracks
# is not ignored, whatever the patterns say, so no --no-index here.
report_ignored() {
  local f
  for f in "$@"; do
    if [ -e "$f" ] && git check-ignore -q "$f" 2>/dev/null; then echo "ignored: $f"; fi
  done
}

case "$MODE" in
  check)  do_check ;;
  files)  do_files ;;
  *)      usage ;;
esac
