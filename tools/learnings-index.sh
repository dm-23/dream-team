#!/usr/bin/env bash
# Dream Team — prints the learnings index, derived from the entry files. No
# index file is kept: two working copies writing one shared table at once
# lose rows, while each entry is a file of its own. See team-manifest.json →
# knowledge.learningsIndex.
#
#   bash <team-root>/tools/learnings-index.sh <dir> [<dir> ...]
#
# Each <dir> holds entry files, *.md directly inside, in the format
# templates/learnings-entry.md defines; a missing directory is skipped. Prints
#
#   | Date | Title | Tags | File |
#   |------|-------|------|------|
#   | 2026-11-02 | <title> | <tag>, <tag> | <dir as given>/<file name> |
#   entries: <N>
#
# Date and title come from the file's first non-empty line,
# "## [YYYY-MM-DD] <title>", tags from its "- **Tags:**" line. The title is cut
# to knowledge.budgets.learningsIndexRowTitleChars characters, the tags to the
# first learningsIndexRowMaxTags. A file whose first line has another form
# gets the date of its name's YYYY-MM-DD- prefix, else "unknown", and the
# title "(unreadable heading)". Rows are sorted by date, then file name, in
# byte order. A file name present in more than one directory gives one row,
# from the directory named last. CR is stripped. Writes nothing.
#
# Exit 0 = printed. 2 = no argument, or the manifest or a limit could not be
# read.
set -uo pipefail
export LC_ALL=C

[ "$#" -gt 0 ] || { echo "usage: learnings-index.sh <dir> [<dir> ...]" >&2; exit 2; }

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 2
M="$TEAM_ROOT/team-manifest.json"
[ -f "$M" ] && [ -r "$M" ] || { echo "learnings-index: no readable team-manifest.json in $TEAM_ROOT" >&2; exit 2; }

# A number placed in knowledge.budgets.
budget() {
  tr -d '\r' < "$M" | awk -v k="$1" '
    index($0, "  \"knowledge\": {") == 1 { f = 1; next }
    f && /^  }/ { exit }
    f && index($0, "    \"budgets\": {") == 1 { g = 1; next }
    g && /^    }/ { exit }
    g && index($0, "      \"" k "\":") == 1 { sub(/^[^:]*:[ \t]*/, ""); sub(/[ \t]*,?[ \t]*$/, ""); print; exit }'
}
need() {
  local v
  v="$(budget "$1")"
  case "$v" in
    ''|*[!0-9]*) echo "learnings-index: knowledge.budgets.$1 is missing or not a number in the manifest" >&2; exit 2 ;;
  esac
  printf '%s' "$v"
}
TITLE_CHARS="$(need learningsIndexRowTitleChars)" || exit 2
MAX_TAGS="$(need learningsIndexRowMaxTags)" || exit 2

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
TAB="$(printf '\t')"

# One line per file found: "<file name><TAB><path as printed>", in argument
# order, so the last line for a name is the directory named last.
: > "$TMP/found"
for d in "$@"; do
  shown="$d"
  while [ "${#shown}" -gt 1 ] && [ "${shown%/}" != "$shown" ]; do shown="${shown%/}"; done
  [ -d "$d" ] || continue
  for f in "$d"/*.md; do
    [ -f "$f" ] || continue
    name="${f##*/}"
    case "$shown" in */) p="$shown$name" ;; *) p="$shown/$name" ;; esac
    printf '%s\t%s\n' "$name" "$p" >> "$TMP/found"
  done
done

# Last occurrence of each name wins.
awk -F'\t' '{ path[$1] = $2 } END { for (n in path) print n "\t" path[n] }' "$TMP/found" > "$TMP/files"

# Rows, keyed by date and file name for the sort.
awk -F'\t' -v tchars="$TITLE_CHARS" -v maxtags="$MAX_TAGS" '
  BEGIN { for (i = 128; i < 192; i++) cont[sprintf("%c", i)] = 1 }
  # The first n characters of s, counting a UTF-8 sequence as one.
  function cut(s, n,    i, c, out, k) {
    k = 0; out = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (!(c in cont)) { if (k == n) break; k++ }
      out = out c
    }
    return out
  }
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function cell(s) { gsub(/\t/, " ", s); gsub(/\|/, "/", s); return s }
  {
    name = $1; path = $2
    first = ""; tags = ""; seenfirst = 0; seentags = 0
    while ((getline line < path) > 0) {
      sub(/\r$/, "", line)
      if (!seenfirst && line !~ /^[ \t]*$/) { first = line; seenfirst = 1 }
      if (!seentags && line ~ /^- \*\*Tags:\*\*/) { tags = line; seentags = 1 }
      if (seenfirst && seentags) break
    }
    close(path)

    date = ""; title = ""
    if (first ~ /^## \[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\] /) {
      date = substr(first, 5, 10)
      title = trim(substr(first, 17))
    }
    if (title == "") {
      if (name ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-/) date = substr(name, 1, 10)
      else date = "unknown"
      title = "(unreadable heading)"
    } else {
      title = trim(cut(cell(title), tchars))
    }

    out = ""
    if (tags != "") {
      sub(/^- \*\*Tags:\*\*/, "", tags)
      n = split(tags, t, ",")
      k = 0
      for (i = 1; i <= n && k < maxtags; i++) {
        s = trim(cell(t[i]))
        if (s == "") continue
        out = (k ? out ", " : "") s
        k++
      }
    }
    printf "%s\t%s\t| %s | %s | %s | %s |\n", date, name, date, title, out, cell(path)
  }' "$TMP/files" > "$TMP/rows"

echo "| Date | Title | Tags | File |"
echo "|------|-------|------|------|"
sort -t "$TAB" -k1,1 -k2,2 "$TMP/rows" | cut -f3-
echo "entries: $(wc -l < "$TMP/rows" | tr -d ' ')"
exit 0
