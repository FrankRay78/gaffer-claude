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
# this clone and is never committed, and .gitignore is left alone. A tracked file cannot be hidden
# that way, so none is changed: where git tracks CLAUDE.md, the imports go in CLAUDE.local.md, and
# where it tracks .claude/settings.json, the entries go in .claude/settings.local.json — the files
# Claude Code reads beside them for one clone. Each is reported as `tracked: <path> ...`.
#
# Which ignore rule counts depends on the mode. Without --git-ignore, only a .gitignore rule
# counts, since the setup is meant to be committed and must ignore scratch in every clone. With it,
# only a rule in this clone's exclude file or in a committed, unchanged .gitignore counts, so that
# discarding a .gitignore change cannot un-hide anything.
#
# OUTPUT. One line per item, `<status>: <item>`, for the command's report. `check` prints `ready`
# or `not ready: <reason>`. `files` prints `added:` for something it puts in place and `present:`
# for something already there, and `skipped:` for the CONVENTIONS.md import when there is no
# CONVENTIONS.md, and for the gaffer marketplace and plugin entries when this script runs from a
# local checkout (see LOCAL_CHECKOUT) and the settings lack them. Without --git-ignore it also
# prints `ignored: <path>` for any file it manages that the repository git-ignores, since a commit
# will not carry it. With it, `tracked:` as above,
# and `shows: <path> <why>` for a path git status still shows: a .gitignore with a change this run
# did not make, or a path a .gitignore negation un-ignores, which outranks the exclude file.
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

# The marketplace this copy of the plugin ships in is named by its own manifest, and its repository
# is that name under MARKETPLACE_OWNER, so a distribution published under another marketplace name
# wires itself and not this one. Set by read_marketplace, which needs jq.
MARKETPLACE_OWNER='FrankRay78'
MARKETPLACE=''
MARKETPLACE_SOURCE=''
GAFFER_PLUGIN=''
PLUGINS=('pr-review-toolkit@claude-plugins-official')
ASK_RULE='Bash(chmod:*)'
SCRATCH='.claude/scratch/'
MEMORY_INDEX='.claude/memory/MEMORY.md'
MEMORY_HEADER='<!-- Memory index: one line per entry, `- [Title](file.md) — one-line hook`. -->'
# Where the settings entries and the imports go. --git-ignore moves either to its local file when
# git tracks it; see resolve_targets.
SETTINGS='.claude/settings.json'
IMPORTS='CLAUDE.md'

# LOCAL_CHECKOUT — the plugin root when this script runs from a checkout passed as --plugin-dir,
# and empty when it runs from a copy Claude Code installed, which lives under the config
# directory's plugins/. A checkout may differ from the marketplace's gaffer, such as a clone with
# its own tracker skill, so the entries that enable the marketplace's gaffer are not written for
# it: a session opened without the --plugin-dir would load the marketplace copy instead.
plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P) || { echo "error: cannot find the plugin root" >&2; exit 1; }
installed_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins"
[ ! -d "$installed_dir" ] || installed_dir=$(cd "$installed_dir" && pwd -P)
case "$plugin_root/" in
  "$installed_dir"/*) LOCAL_CHECKOUT='' ;;
  *)                  LOCAL_CHECKOUT=$plugin_root ;;
esac

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

# read_marketplace — MARKETPLACE, MARKETPLACE_SOURCE and GAFFER_PLUGIN, from the manifest beside
# this script's plugin.
read_marketplace() {
  local manifest="$plugin_root/.claude-plugin/marketplace.json"
  MARKETPLACE=$(jq -er '.name | select(type == "string" and test("^[A-Za-z0-9._-]+$"))' "$manifest" 2>/dev/null) \
    || fail "cannot read the marketplace name from $manifest (the settings were not changed)"
  MARKETPLACE_SOURCE=$(jq -nc --arg repo "$MARKETPLACE_OWNER/$MARKETPLACE" '{source: {source: "github", repo: $repo}}')
  GAFFER_PLUGIN="gaffer@$MARKETPLACE"
}

# read_settings <file> — the file's JSON, or {} when there is none; fails on anything but an object.
read_settings() {
  local json='{}'
  if [ -f "$1" ]; then
    json=$(cat "$1")
    jq -e 'type == "object"' >/dev/null 2>&1 <<<"$json" || fail "$1 is not a JSON object; fix it and re-run (the settings were not changed)"
  fi
  printf '%s\n' "$json"
}

# Prints what the settings are missing, one item per line, and writes the merged $SETTINGS to $1.
# Where $SETTINGS is the local file, an entry the tracked settings.json already has counts as
# present, so a plugin the repository turned off there is not turned back on here. From a local
# checkout the gaffer marketplace and plugin are listed when missing but not written.
settings_merge() {
  local out=$1 json other='{}' local_checkout=false
  [ -z "$LOCAL_CHECKOUT" ] || local_checkout=true
  json=$(read_settings "$SETTINGS") || exit 1
  if [ "$SETTINGS" != .claude/settings.json ]; then other=$(read_settings .claude/settings.json) || exit 1; fi
  jq --arg m "$MARKETPLACE" --argjson ms "$MARKETPLACE_SOURCE" --arg g "$GAFFER_PLUGIN" --arg ask "$ASK_RULE" \
     --argjson o "$other" --argjson local "$local_checkout" --args '
    def ensure(path; v): if (getpath(path) == null and ($o | getpath(path)) == null) then setpath(path; v) else . end;
    (if $local then . else ensure(["extraKnownMarketplaces", $m]; $ms) | ensure(["enabledPlugins", $g]; true) end)
    | reduce $ARGS.positional[] as $p (.; ensure(["enabledPlugins", $p]; true))
    | if ((.permissions.ask // []) + ($o.permissions.ask // []) | index($ask)) then . else .permissions.ask = ((.permissions.ask // []) + [$ask]) end
  ' "${PLUGINS[@]}" <<<"$json" > "$out" || fail "could not merge $SETTINGS"
  jq -r --arg m "$MARKETPLACE" --arg g "$GAFFER_PLUGIN" --arg ask "$ASK_RULE" --argjson o "$other" --args '
    (if .extraKnownMarketplaces[$m] == null and $o.extraKnownMarketplaces[$m] == null then "marketplace \($m)" else empty end),
    (. as $s | [$g] + $ARGS.positional | .[] as $p | if $s.enabledPlugins[$p] == null and $o.enabledPlugins[$p] == null then "plugin \($p)" else empty end),
    (if ((.permissions.ask // []) + ($o.permissions.ask // []) | index($ask)) then empty else "permission ask \($ask)" end)
  ' "${PLUGINS[@]}" <<<"$json"
}

report_settings() {
  local tmp missing written item
  local -a skippable=("marketplace $MARKETPLACE" "plugin $GAFFER_PLUGIN")
  tmp=$(mktemp) || fail "mktemp failed"
  missing=$(settings_merge "$tmp") || { rm -f "$tmp"; exit 1; }
  written=$missing
  if [ -n "$LOCAL_CHECKOUT" ]; then
    for item in "${skippable[@]}"; do written=$(grep -vxF "$item" <<<"$written"); done
  fi
  if [ -n "$written" ]; then
    mkdir -p .claude
    mv "$tmp" "$SETTINGS"
  else
    rm -f "$tmp"
  fi
  for item in "${skippable[@]}" "${PLUGINS[@]/#/plugin }" "permission ask $ASK_RULE"; do
    if ! grep -qxF "$item" <<<"$missing"; then
      echo "present: $SETTINGS $item"
    elif grep -qxF "$item" <<<"$written"; then
      echo "added: $SETTINGS $item"
    else
      echo "skipped: $SETTINGS $item (gaffer runs from the local checkout $LOCAL_CHECKOUT, not a marketplace install)"
    fi
  done
}

# append_line <file> <line> — the line on a line of its own, whatever the file ends with.
append_line() {
  if [ -s "$1" ] && [ -n "$(tail -c1 "$1")" ]; then printf '\n' >> "$1"; fi
  printf '%s\n' "$2" >> "$1"
}

# ignore_source <path> — the file holding the rule that makes git ignore the path, or nothing
# when no rule does or the deciding rule is a negation. --no-index, so a tracked file answers by
# the rules too; a directory is asked about through a file inside it.
ignore_source() {
  local path=$1 line pattern
  case "$path" in */) path="${path}probe" ;; esac
  line=$(git check-ignore -v --no-index "$path" 2>/dev/null) || return 0
  pattern=${line#*:*:}
  case "$pattern" in '!'*) return 0 ;; esac
  printf '%s\n' "${line%%:*}"
}

# A .gitignore in this work tree, as opposed to the exclude file or a global excludes file, which
# git names by an absolute path.
is_gitignore() { case "$1" in /*|'~'*) return 1 ;; .gitignore|*/.gitignore) return 0 ;; *) return 1 ;; esac; }

# Plain mode: ignored by a .gitignore, which a commit carries to every clone.
ignored_for_all() {
  local src
  src=$(ignore_source "$1")
  [ -n "$src" ] && is_gitignore "$src"
}

# --git-ignore: ignored by this clone's exclude file, or by a .gitignore that is committed and
# unchanged, so that discarding an uncommitted .gitignore line cannot un-hide the path.
ignored_here() {
  local src
  src=$(ignore_source "$1")
  [ -n "$src" ] || return 1
  [ "$src" = "$EXCLUDE" ] && return 0
  is_gitignore "$src" && [ -n "$(git ls-files -- "$src")" ] && [ -z "$(git status --porcelain -- "$src")" ]
}

ensure_ignored() {
  if ignored_for_all "$SCRATCH"; then
    echo "present: $SCRATCH git-ignored"
    return
  fi
  append_line .gitignore "$SCRATCH"
  echo "added: $SCRATCH git-ignored (.gitignore)"
}

# --git-ignore: a tracked CLAUDE.md or .claude/settings.json is left alone, and what init would add
# to it goes in the local file Claude Code reads beside it.
resolve_targets() {
  if [ -n "$(git ls-files -- CLAUDE.md)" ]; then
    IMPORTS='CLAUDE.local.md'
    echo "tracked: CLAUDE.md left as it is; its imports go in $IMPORTS"
  fi
  if [ -n "$(git ls-files -- .claude/settings.json)" ]; then
    SETTINGS='.claude/settings.local.json'
    echo "tracked: .claude/settings.json left as it is; its entries go in $SETTINGS"
  fi
}

# --git-ignore. Excludes every path init writes, as a pattern anchored at the repository root. It
# needs none of them to exist, so it runs first, and a later failure leaves nothing showing. git
# rev-parse finds the exclude file, which a linked work tree shares with its main one.
ensure_excluded() {
  local path
  for path in CONVENTIONS.md REVIEW.md "$IMPORTS" "$SETTINGS" .claude/memory/ "$SCRATCH"; do
    if [ -n "$(git ls-files -- "$path")" ]; then
      echo "tracked: $path"
    elif ignored_here "$path"; then
      echo "present: $path git-ignored"
    else
      mkdir -p "$(dirname "$EXCLUDE")"
      append_line "$EXCLUDE" "/$path"
      if ignore_source "$path" | grep -q .; then
        echo "added: $path git-ignored (.git/info/exclude)"
      else
        echo "shows: $path a .gitignore negation un-ignores it, and outranks .git/info/exclude"
      fi
    fi
  done
}

# --git-ignore leaves .gitignore alone, so a change to it was made by someone else, such as an
# earlier run without the option, and it still shows.
report_gitignore_change() {
  if [ -n "$(git status --porcelain -- .gitignore)" ]; then
    echo "shows: .gitignore a change this run did not make"
  fi
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

# An import counts as present when a line of CLAUDE.md, or of $IMPORTS, is exactly `@<path>` or
# `@./<path>`.
has_import() { grep -sqE "^@(\./)?$(sed 's/[.]/\\./g' <<<"$1")[[:space:]]*$" CLAUDE.md "$IMPORTS"; }

ensure_import() {
  local path=$1
  if has_import "$path"; then
    echo "present: $IMPORTS imports $path"
    return
  fi
  if [ -s "$IMPORTS" ]; then
    [ -n "$(tail -c1 "$IMPORTS")" ] && printf '\n' >> "$IMPORTS"
    printf '\n@%s\n' "$path" >> "$IMPORTS"
  else
    printf '@%s\n' "$path" >> "$IMPORTS"
  fi
  echo "added: $IMPORTS imports $path"
}

do_files() {
  command -v jq >/dev/null || fail "jq is not on the path"
  read_marketplace
  if [ "$GIT_IGNORE" = 1 ]; then
    EXCLUDE=$(git rev-parse --git-path info/exclude) || fail "could not find this clone's exclude file"
    resolve_targets
    ensure_excluded
  fi
  report_settings
  [ "$GIT_IGNORE" = 1 ] || ensure_ignored
  ensure_memory_index
  # CONVENTIONS.md is imported only once it exists: the command writes it before calling this, and
  # leaves it out when the repository gave it nothing to say.
  if [ -f CONVENTIONS.md ]; then ensure_import CONVENTIONS.md; else echo "skipped: $IMPORTS import of CONVENTIONS.md (no CONVENTIONS.md)"; fi
  ensure_import "$MEMORY_INDEX"
  if [ "$GIT_IGNORE" = 1 ]; then
    report_gitignore_change
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
