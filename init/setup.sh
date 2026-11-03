#!/usr/bin/env bash
#
# setup.sh — the mechanical part of /gaffer:init.
#
# Wires a repository for the plugin: the checks that say it can take a pull request, the files
# every command assumes, and the labels the issue stage and the chain use. The judgement part of
# init (reading the repository and filling CONVENTIONS.md and REVIEW.md) is the command's; this
# script does only what a person would otherwise type from docs/getting-started.md, so it can be
# tested without a model.
#
#   bash setup.sh check  [<repo>]   is the repository ready for init? Changes nothing.
#   bash setup.sh files  [<repo>]   ensure the settings entries, the git-ignore line, the memory
#                                   index and the CLAUDE.md imports.
#   bash setup.sh labels [<repo>]   ensure the issue-stage and chain labels exist on GitHub.
#
# <repo> defaults to the current directory and must be the root of a git work tree.
#
# OUTPUT. One line per item, `<status>: <item>`, so the command can list the outcome in the pull
# request body. `files` and `labels` print `added:` for something they put in place and `present:`
# for something already there; `check` prints `ready: <default branch>` or `not ready: <reason>`.
#
# IDEMPOTENT. Anything already present is left exactly as it is, including a setting the
# repository has deliberately turned off: a second run of `files` changes no byte. A file is only
# rewritten when something in it is missing.
#
# EXIT. 0 on success (including `ready`); 1 on `not ready`, an unreadable settings file, or a gh
# failure, with nothing changed by the step that failed; 2 on bad usage.
#
# Needs git, jq and, for `check` and `labels`, gh signed in. Run with `bash`; nothing relies on an
# executable bit.

set -uo pipefail

MARKETPLACE='gaffer-claude'
MARKETPLACE_SOURCE='{"source":{"source":"github","repo":"FrankRay78/gaffer-claude"}}'
PLUGINS=('gaffer@gaffer-claude' 'pr-review-toolkit@claude-plugins-official')
ASK_RULE='Bash(chmod:*)'
SCRATCH='.claude/scratch/'
MEMORY_INDEX='.claude/memory/MEMORY.md'
MEMORY_HEADER='<!-- Memory index: one line per entry, `- [Title](file.md) — one-line hook`. -->'
# name|description, in the order getting-started.md lists them.
LABELS=(
  'needs answers|A review is posted and awaiting the author'"'"'s answers'
  'ready|The issue is confirmed and may be built'
  'parked|An unattended run stopped on this issue; remove to retry'
)

usage() { echo "usage: bash setup.sh {check|files|labels} [<repo>]" >&2; exit 2; }
fail() { echo "error: $*" >&2; exit 1; }

[ $# -ge 1 ] && [ $# -le 2 ] || usage
MODE=$1
REPO=${2:-.}
cd "$REPO" 2>/dev/null || fail "no such directory: $REPO"
top=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not a git repository: $REPO"
[ "$(cd "$top" && pwd -P)" = "$(pwd -P)" ] || fail "not the root of the work tree: $REPO (the root is $top)"

# ---------------------------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------------------------
do_check() {
  local branch default
  gh auth status >/dev/null 2>&1 || { echo "not ready: gh is not signed in (run \`gh auth login\`)"; exit 1; }
  default=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null) \
    && [ -n "$default" ] \
    || { echo "not ready: no GitHub repository found for this remote (gh repo view failed)"; exit 1; }
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$branch" = "$default" ] || { echo "not ready: on branch '$branch', not the default branch '$default'"; exit 1; }
  [ -z "$(git status --porcelain)" ] || { echo "not ready: the working tree has uncommitted changes"; exit 1; }
  echo "ready: $default"
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

ensure_ignored() {
  if git check-ignore -q --no-index "${SCRATCH}probe" 2>/dev/null; then
    echo "present: $SCRATCH git-ignored"
    return
  fi
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then printf '\n' >> .gitignore; fi
  printf '%s\n' "$SCRATCH" >> .gitignore
  echo "added: $SCRATCH git-ignored (.gitignore)"
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
  ensure_ignored
  ensure_memory_index
  # CONVENTIONS.md is imported only once it exists: the command writes it before calling this, and
  # leaves it out when the repository gave it nothing to say.
  if [ -f CONVENTIONS.md ]; then ensure_import CONVENTIONS.md; else echo "skipped: CLAUDE.md import of CONVENTIONS.md (no CONVENTIONS.md)"; fi
  ensure_import "$MEMORY_INDEX"
}

# ---------------------------------------------------------------------------------------------
# labels
# ---------------------------------------------------------------------------------------------
do_labels() {
  local existing entry name desc
  existing=$(gh label list --limit 1000 --json name --jq '.[].name' 2>/dev/null) || fail "could not list labels (gh label list failed)"
  for entry in "${LABELS[@]}"; do
    name=${entry%%|*}; desc=${entry#*|}
    if grep -qxF "$name" <<<"$existing"; then
      echo "present: label $name"
    else
      gh label create "$name" --description "$desc" >/dev/null 2>&1 || fail "could not create label '$name'"
      echo "added: label $name"
    fi
  done
}

case "$MODE" in
  check)  do_check ;;
  files)  do_files ;;
  labels) do_labels ;;
  *)      usage ;;
esac
