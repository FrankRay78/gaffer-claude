#!/usr/bin/env bash
#
# link-check.sh — every markdown link to a file in this repository resolves to a file that is there.
#
# The plugin is mostly markdown: commands, docs, CONVENTIONS.md and REVIEW.md point at each other
# by file and by heading. A rename or a deleted heading leaves those pointers broken in places
# nobody opens at the time, so this check is what makes the cost visible on the pull request that
# causes it, instead of to a reader months later.
#
# TWO CHECKS, both over the tracked `*.md` files:
#
#   1. A markdown link — `[text](target)`. Three kinds of target are resolved, every one of them
#      against the files in this branch and none of them fetched:
#        a. a relative path, resolved from the linking file's own directory, which is how GitHub
#           renders it; or a root-relative one, resolved from the repository root, which GitHub
#           does NOT do — it reads a leading `/` against the site root, so such a link renders
#           broken there. Resolving it here is a deliberate leniency, not a match for GitHub;
#        b. a full `https://github.com/FrankRay78/gaffer-claude/{blob,tree,raw}/main/<path>` link,
#           mapped onto `<path>` in the checkout — the file the link points at, read locally;
#        c. an `#anchor`, on either of those or on its own, checked against the headings of the
#           markdown file it lands in.
#   2. A heading named in prose directly after a link to a markdown file — the
#      `[file](path) → *Heading*` form the docs use for "this section of that file". The italic
#      text is slugged as GitHub slugs a heading and checked against the headings of the linked
#      file, so a renamed section fails here just as a renamed `#anchor` does. Only the first
#      `→ *Heading*` after a link is read, and only when the link carries no title. An unlinked
#      `File.md` → *Heading* is left out: with no link there is no path to resolve it against.
#
# HOW A HEADING IS MATCHED. GitHub derives a heading's anchor by lowercasing the text, dropping
# everything that is not a letter, digit, hyphen or underscore, turning each remaining space into a
# hyphen, and suffixing `-1`, `-2`, … to the second and later occurrences of a repeated heading.
# A link in a heading contributes its text and not its target, which is reproduced here too.
#
# That is reproduced over ATX headings (`## Text`) outside code fences, front matter and multi-line
# HTML comments, none of which GitHub renders as headings. Four kinds of heading are
# read differently from GitHub, and every one of them costs a FAIL on a link that works there
# rather than a quiet pass, so the report is loud in each case:
#   - a non-ASCII letter is dropped where GitHub keeps it;
#   - a setext heading (`Text` over `====`) is not seen as a heading at all;
#   - nor is an ATX heading indented by one to three spaces, which GFM allows;
#   - nor is an explicit `<a id="...">` anchor, which GitHub honours.
# None of the four occurs in this repository today. Setext is left unread deliberately: a naive
# `previous line + ----` rule mints a heading from a front-matter delimiter, and a check that
# invents headings passes links that are broken — strictly worse than one that reports a working
# link, loudly.
#
# WHAT IS DELIBERATELY NOT A LINK. A markdown link inside a fenced block or inline backticks is
# being shown to the reader, not offered to be followed: the commands spell out link syntax and
# `.claude/memory/MEMORY.md` carries `- [Title](file.md) — hook` as its own format. So both are
# stripped before the scan, at the cost of not checking a link someone wrote inside backticks —
# which was not a working link to begin with. Stripping backticks also means a `→ *Heading*`
# whose italic text holds a backtick span is slugged without it, and fails loudly. Also skipped:
#   - a `mailto:` target, and any `scheme://` URL that is not the full-link shape above. The rest
#     of github.com is a web page rather than a path in this branch — `/releases`, an issue page,
#     an action badge — as is a path on another ref or in another repository, and resolving any of
#     those against the checkout would fail on a perfectly good link. A scheme carrying no `://`,
#     such as `tel:`, is not recognised and is read as a path; the result is a loud FAIL rather
#     than a quiet pass.
#   - a relative path that climbs above the repository root, which is outside this repository's
#     reach.
#   - an anchor on a target that is not a markdown file: a `#L10-L20` line range on a source file
#     and a fragment on a folder name no heading. An `#L<n>` anchor names no heading on a markdown
#     file either, and is skipped there too — it is what GitHub's "copy permalink" writes.
#
# WHAT IS JUDGED is the WORKING TREE, not `HEAD`: the point of a local run is to be used midway
# through a rename, before anything is committed. The file LIST still comes from `git ls-files`,
# so an untracked scratch file is never scanned — but target existence is a plain filesystem test,
# so a link resolving to one passes here and fails in CI. In CI the two are the same thing, because
# the checkout holds only what was committed.
#
# DESIGN RULE: fail CLOSED — this is a merge gate, and a gate that passes without having run gives
# exactly the false comfort it exists to remove. Finding no tracked `*.md` at all is therefore a
# failure, not a clean pass. An unterminated code fence is a failure too, for the same reason —
# every link below it would be invisible, which is not the same as there being none.
#
# Not a Claude Code hook. Two ways to run it:
#   In CI       .github/workflows/link-check.yml, on every pull request to main.
#   Locally     bash .github/scripts/link-check.sh
#               Run it after renaming or deleting anything that is linked to.
#
# CLAUDE_PROJECT_DIR points it at another tree, which is how link-check.tests.sh drives it.
# Verify any edit with that matrix.

set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

say() { printf 'link-check: %s\n' "$*"; }
die() { printf 'link-check: FAIL — %s\n' "$*" >&2; exit 1; }

# --- fail-closed preconditions ----------------------------------------------------
for tool in git grep sed awk sort tr dirname mktemp; do
  command -v "$tool" >/dev/null 2>&1 \
    || die "'$tool' is not available, so the check cannot run. It is a merge gate, so it fails rather than reporting an unverified pass."
done

git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || die "'$REPO_ROOT' is not a git repository, so the tracked files cannot be listed."

TMP="$(mktemp -d)" || die "could not create a temporary directory."
trap 'rm -rf "$TMP"' EXIT

# This repository's canonical web URL, lowercased, with its trailing slash. Hardcoded rather than
# read from `git remote`: the links in these documents name the canonical repository whoever is
# holding the clone, so a fork's own origin is the wrong thing to resolve them against.
MAIN_URL_PREFIX="https://github.com/frankray78/gaffer-claude/"

# --- resolve BASE_DIR TARGET ------------------------------------------------------
# Prints the repository-root-relative path a link target names, or returns 1 when it climbs above
# the root. Done in the shell rather than with `realpath`, which resolves against the real
# filesystem and would follow a symlink out of the tree and succeed on a path that GitHub, which
# resolves textually, would render as broken.
resolve_path() {
  local base="$1" target="$2" joined seg out=""
  local -a segs=() parts=()

  case "$target" in
    /*) joined="${target#/}" ;;                      # root-relative, resolved from the repo root
    *)  if [ "$base" = "." ]; then joined="$target"; else joined="$base/$target"; fi ;;
  esac

  # A non-whitespace IFS does not collapse runs of the delimiter, so `a//b` splits to three
  # segments with an empty one in the middle — dropped below alongside `.`, as GitHub drops it.
  IFS='/' read -r -a segs <<< "$joined"
  for seg in "${segs[@]}"; do
    case "$seg" in
      ''|.) ;;
      ..)
        [ "${#parts[@]}" -gt 0 ] || return 1
        parts=("${parts[@]:0:${#parts[@]}-1}")
        ;;
      *) parts+=("$seg") ;;
    esac
  done

  [ "${#parts[@]}" -gt 0 ] || return 1
  for seg in "${parts[@]}"; do out="${out:+$out/}$seg"; done
  printf '%s' "$out"
}

# --- main_ref_path URL ------------------------------------------------------------
# Prints the repository-root-relative path a full link to a file on this repository's `main`
# branch names, or returns 1 when the URL is not one. The whole shape is matched against a
# lowercased copy, so the scheme, host, owner, repository and the `blob`/`tree`/`raw` and `main`
# segments are all read whatever their case; the path is then cut from the original URL by length,
# so it keeps the case it was written in, because the checkout does. Lowercasing goes through `tr`
# rather than `${var,,}` so the check runs under the bash 3.2 that is still /bin/bash on macOS.
main_ref_path() {
  local url="$1" lower path tail
  lower="$(printf '%s' "$url" | LC_ALL=C tr 'A-Z' 'a-z')"

  # Only a path on `main` can be answered for by the files in this branch. `blob` and `raw` name a
  # file, `tree` a folder; anything else under this repository's URL is a web page, and any other
  # ref is a different set of files.
  case "$lower" in
    "$MAIN_URL_PREFIX"blob/main/*|"$MAIN_URL_PREFIX"tree/main/*|"$MAIN_URL_PREFIX"raw/main/*) ;;
    *) return 1 ;;
  esac

  # Cut at the first `/main/` of the lowercased copy, then take that many characters off the end
  # of the original: matching on `$url` would miss a `/MAIN/` the case test above has accepted.
  tail="${lower#*/main/}"
  path="${url:$(( ${#url} - ${#tail} ))}"
  path="${path%%\?*}"                                # `?plain=1` and friends are not part of it
  [ -n "$path" ] || return 1
  resolve_path "." "$path"
}

# --- resolve_target DIR TARGET_PATH -----------------------------------------------
# Prints the repository-root-relative path a link's target (its anchor already cut) names, or
# returns 1 when it is not a path in this repository: a `mailto:`, a URL that is not a path on
# `main`, or a relative path that climbs out. An empty target is the linking file itself, which
# the caller handles.
resolve_target() {
  case "$2" in
    mailto:*) return 1 ;;
    # Every scheme goes through the mapping, which returns 1 for anything that is not a path on
    # this repository's `main` — so a scheme written in any case is read, and nothing else about
    # the URL has to be matched twice.
    *://*)    main_ref_path "$2" ;;
    *)        resolve_path "$1" "$2" ;;
  esac
}

# --- slugify ----------------------------------------------------------------------
# Reads heading text a line at a time and prints the GitHub anchor of each, without the counter a
# repeated heading takes.
slugify() {
  LC_ALL=C tr 'A-Z' 'a-z' \
    | LC_ALL=C tr -dc 'a-z0-9 _\n-' \
    | LC_ALL=C tr ' ' '-'
}

# --- heading_slugs FILE -----------------------------------------------------------
# Prints the GitHub anchor of every ATX heading in a markdown file, in document order. See
# HOW A HEADING IS MATCHED above. Returns non-zero when the file cannot be read to the end.
heading_slugs() {
  awk '
    match($0, /^[[:space:]]*(```+|~~~+)/) {
      marker = substr($0, RSTART, RLENGTH)
      gsub(/[[:space:]]/, "", marker)
      if (fence == "") { fence = marker; next }
      # CommonMark closes a fence only on a marker line with nothing after it: inside a ```markdown
      # block, a ```bash line is content, not the end of the block.
      if (substr(marker, 1, 1) == substr(fence, 1, 1) && length(marker) >= length(fence) && $0 ~ /^[[:space:]]*(```+|~~~+)[[:space:]]*$/) fence = ""
      next
    }
    fence != "" { next }
    # Front matter (a `---` block opening on line 1) is rendered as a table, never as headings.
    NR == 1 && /^---[[:space:]]*$/ { front = 1; next }
    front { if (/^---[[:space:]]*$/) front = 0; next }
    # Nor is anything inside an HTML comment that spans lines.
    comment { if (/-->/) comment = 0; next }
    /^[[:space:]]*<!--/ && !/-->/ { comment = 1; next }
    /^#+[ \t]/ {
      match($0, /^#+/)
      if (RLENGTH > 6) next                          # seven hashes is not a heading
      sub(/^#+[ \t]+/, "")
      gsub(/\]\([^)]*\)/, "")                        # a link slugs as its text, never its target
      sub(/[ \t]+#+[ \t]*$/, "")                     # an optional closing sequence
      sub(/[ \t]+$/, "")
      print
    }
    END { if (fence != "") exit 3 }
  ' "$REPO_ROOT/$1" \
    | slugify \
    | awk '{ seen = count[$0]++; if (seen == 0) print; else print $0 "-" seen }'
}

# --- has_heading LINKING_FILE RESOLVED SLUG LABEL ---------------------------------
# Records a finding when the markdown file RESOLVED has no heading whose anchor is SLUG. LABEL is
# how the reference is reported. A target that is not a markdown file, or not a file, names no
# heading and is passed over.
has_heading() {
  local file="$1" resolved="$2" slug="$3" label="$4"
  case "$resolved" in *.md) ;; *) return 0 ;; esac
  [ -f "$REPO_ROOT/$resolved" ] || return 0

  heading_slugs "$resolved" > "$TMP/slugs" \
    || die "could not read the headings of '$resolved', which '$file' links into, so no verdict is possible. An unterminated code fence in it is the commonest cause."
  checked=$((checked + 1))
  grep -qxF -- "$slug" "$TMP/slugs" \
    || printf '%s\t%s\t%s\n' "$file" "$label" "$resolved" >> "$TMP/noheading"
}

# --- the tracked markdown files ---------------------------------------------------
git -C "$REPO_ROOT" ls-files -z -- '*.md' > "$TMP/tracked" \
  || die "could not list the tracked files of '$REPO_ROOT'."

checked=0
scanned=0
: > "$TMP/missing"
: > "$TMP/noheading"

while IFS= read -r -d '' file; do
  path="$REPO_ROOT/$file"
  # A tracked file that is gone from the working tree is the half-finished deletion this check
  # exists to be run during. There is nothing to scan in it; what points AT it is the finding,
  # and that is raised by whichever file carries the pointer.
  [ -f "$path" ] || continue

  # Fenced blocks first, dropped by their own delimiter so that a `~~~` block quoting a ``` line
  # stays one block; then backtick spans. A span opens on a run of backticks and closes on the next
  # run of exactly the same length, as CommonMark reads it, so `a` and `b` on one line is two spans
  # and a ``double-backtick span holding a ` backtick`` is one. An opener with no closer is kept as
  # text. A span is read within one line only.
  awk '
    function strip_spans(s,    out, n, opener, pre, rest, r, after, found) {
      out = ""
      while (match(s, /`+/)) {
        n = RLENGTH
        pre = substr(s, 1, RSTART - 1)
        opener = substr(s, RSTART, n)
        rest = substr(s, RSTART + n)
        found = 0
        r = rest
        while (match(r, /`+/)) {
          if (RLENGTH == n) { found = 1; after = substr(r, RSTART + RLENGTH); break }
          r = substr(r, RSTART + RLENGTH)
        }
        if (found) { out = out pre; s = after }
        else       { out = out pre opener; s = rest }
      }
      return out s
    }
    match($0, /^[[:space:]]*(```+|~~~+)/) {
      marker = substr($0, RSTART, RLENGTH)
      gsub(/[[:space:]]/, "", marker)
      if (fence == "") { fence = marker; next }
      # CommonMark closes a fence only on a marker line with nothing after it: inside a ```markdown
      # block, a ```bash line is content, not the end of the block.
      if (substr(marker, 1, 1) == substr(fence, 1, 1) && length(marker) >= length(fence) && $0 ~ /^[[:space:]]*(```+|~~~+)[[:space:]]*$/) fence = ""
      next
    }
    fence == "" { print strip_spans($0) }
    END { if (fence != "") exit 3 }
  ' "$path" > "$TMP/prose"
  case $? in
    0) ;;
    3) die "'$file' has an unterminated code fence, so any link below it cannot be read. Close the fence — an unreadable file is not a link-free one." ;;
    *) die "could not scan '$file' for code fences, so no verdict is possible." ;;
  esac

  scanned=$((scanned + 1))
  dir="$(dirname "$file")"

  # --- check 1: markdown links --------------------------------------------------
  # The target is everything after `](` up to the first space or close paren, which takes the path
  # out of `[text](path "Title")` as well as out of `[text](path)`.
  targets="$(grep -oE '\]\([^)[:space:]]+' "$TMP/prose" | sed -E 's/^\]\(//')"
  case $? in
    0|1) ;;
    *) die "could not scan '$file' for markdown links, so no verdict is possible." ;;
  esac

  while IFS= read -r target; do
    [ -n "$target" ] || continue

    target_path="${target%%#*}"
    anchor="${target#*#}"
    [ "$anchor" = "$target" ] && anchor=""           # no `#` in the target at all

    if [ -z "$target_path" ]; then
      resolved="$file"                               # an anchor-only target names a heading here
    else
      resolved="$(resolve_target "$dir" "$target_path")" || continue
      checked=$((checked + 1))
      if [ ! -e "$REPO_ROOT/$resolved" ]; then
        printf '%s\t%s\n' "$file" "$target_path" >> "$TMP/missing"
        continue                                     # the file is the finding, not its heading
      fi
    fi

    [ -n "$anchor" ] || continue
    # A line reference names no heading even on a markdown file, and GitHub's own "copy permalink"
    # writes one as `…/docs/guide.md?plain=1#L10`.
    case "$anchor" in L[0-9]*) continue ;; esac
    has_heading "$file" "$resolved" "$anchor" "#$anchor"
  done <<< "$targets"

  # --- check 2: a heading named in prose after a link ---------------------------
  # Each match is `](target) → *Heading*`; the target and the heading text are split on the first
  # `)`, which the target pattern cannot contain. A link with a title does not match, by design.
  named="$(grep -oE '\]\([^)[:space:]]+\)[[:space:]]*→[[:space:]]*\*[^*]+\*' "$TMP/prose")"
  case $? in
    0) ;;
    1) named="" ;;
    *) die "could not scan '$file' for headings named after a link, so no verdict is possible." ;;
  esac

  while IFS= read -r match; do
    [ -n "$match" ] || continue
    target="${match#](}"
    target="${target%%)*}"
    heading="${match#*→}"
    heading="${heading#"${heading%%\**}"}"           # drop the space before the opening `*`
    heading="${heading#\*}"
    heading="${heading%\*}"

    target_path="${target%%#*}"
    if [ -z "$target_path" ]; then
      resolved="$file"
    else
      # A missing file is check 1's finding; a heading in it is not reported as well.
      resolved="$(resolve_target "$dir" "$target_path")" || continue
      [ -e "$REPO_ROOT/$resolved" ] || continue
    fi

    slug="$(printf '%s\n' "$heading" | slugify)"
    has_heading "$file" "$resolved" "$slug" "→ *$heading*"
  done <<< "$named"
done < "$TMP/tracked"

[ "$scanned" -gt 0 ] \
  || die "found no tracked '*.md' files in '$REPO_ROOT'. This repository has many, so an empty result means the discovery or the naming has drifted — which is the one outcome that would otherwise report green having checked nothing."

# --- the verdict ------------------------------------------------------------------
# Both verdicts carry the counts, which makes a run self-diagnosing after the fact — "2 references
# checked" alongside a clean verdict reads very differently from "431".
if [ -s "$TMP/missing" ] || [ -s "$TMP/noheading" ]; then
  {
    if [ -s "$TMP/missing" ]; then
      printf 'link-check: FAIL — these links name a file that is not in the repository:\n'
      sort -u "$TMP/missing" | sed $'s/\t/ → /; s/^/  - /'
      printf '\n'
      printf 'Point each one at where the content now lives, or remove it where the surrounding\n'
      printf 'text no longer needs it.\n'
    fi
    if [ -s "$TMP/noheading" ]; then
      [ -s "$TMP/missing" ] && printf '\n'
      printf 'link-check: FAIL — these name a heading the file they point at does not have:\n'
      sort -u "$TMP/noheading" | sed $'s/\t/ : /; s/\t/ in /; s/^/  - /'
      printf '\n'
      printf 'Retitle the reference to the heading as it now reads, or point it at one that is there.\n'
      printf 'GitHub lowercases a heading, drops anything that is not a letter, digit, hyphen or\n'
      printf 'underscore, and turns each remaining space into a hyphen.\n'
    fi
    printf 'Checked %s reference(s) across %s markdown file(s).\n' "$checked" "$scanned"
  } >&2
  exit 1
fi

say "OK — $checked reference(s) checked across $scanned markdown file(s), none dangling."
