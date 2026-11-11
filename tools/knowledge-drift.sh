#!/usr/bin/env bash
# Dream Team — tells a run how far the committed project knowledge lags behind
# the code, and which knowledge files to verify against the code before
# relying on them. See team-manifest.json → knowledge.drift.
#
#   bash <team-root>/tools/knowledge-drift.sh [--list]     (from the project root)
#
# The knowledge dir is the resolver's project dir (knowledge.resolver). A
# refresh records the commit it verified the knowledge against in
# <knowledge dir>/<knowledge.baselineFile>, one key per line: commit=<40 hex>,
# date=YYYY-MM-DD, branch=<release branch>. Every generated file and topic
# declares, within its first five lines (after the scaffold banner, when it
# has one), the paths it describes:
#
#   Covers: <pattern>, <pattern>   git glob pathspecs from the repository root
#   Covers: conventions            never marked by path
#   Covers: topics                 the index of a split file, never marked
#
# The first state that holds decides the output, one line unless said:
#
#   none        not a repository, or nothing tracked under the knowledge dir
#   scaffold    checks/verify-knowledge-scaffold.sh exits 1 or 3
#   missing     no baseline file, or no commit= line of 40 hex digits
#   unresolved  the baseline commit is not in this copy
#   clean       no path changed since the baseline commit
#   over        more than knowledge.budgets.driftMarkedPercent of the located
#               topics are marked: one line, "a refresh is due"
#   listed      a block: the changed-file count, the marked files, each with
#               the pattern that matched most, and the changed paths no
#               pattern matched, grouped by their first two path segments
#               (src/notifications/), a file one level down by its directory
#               (src/), a root file by its name
#
# Changed paths: git diff --name-only --no-renames <commit> HEAD, without the
# paths under the knowledge dir, so a commit that only touched the knowledge
# reads "Nothing changed since." A rename counts at both its paths. The list is
# read once, NUL-separated, and every pattern is matched against it here, with
# git's glob pathspec semantics: the literal part before the first wildcard is
# compared as is; "*" and "?" never match "/"; "**" matches across "/" when it
# stands between slashes, at the start of the wildcard part or at its end;
# "[...]" is a class; a pattern with no wildcard names a path or a directory.
#
# Located topics: every *.md under the knowledge dir outside rulesDir and
# proposalsDir whose Covers: line lists patterns, plus every file with no
# Covers: line whose default in knowledge.covers is "paths" (a topic takes the
# default of its index file: backend-architecture/x.md reads
# BACKEND-ARCHITECTURE.md). A file is marked when a pattern of its own matches
# a changed path; a file listed for a missing Covers: line is always marked.
# Lists are in byte order and cut at knowledge.budgets.driftListMaxLines with
# "… and <n> more"; the "Verify against" part is left out when nothing is
# marked, the "Not covered" line when every changed path is covered.
#
# --list prints tab-separated records instead, never cut:
#   state     none|scaffold|missing|unresolved|clean|over|listed
#   baseline  <sha>          from unresolved on
#   branch    <branch>       when the baseline file names one
#   marked    <file> <n>     over and listed; n is the count of the pattern that
#                            matched most, 0 for a missing Covers: line
#   uncovered <group> <n>    over and listed
#
# Reads only; never writes outside a temporary directory, never contacts a
# remote. Exit 0 always, 2 on a bad argument. A manifest that cannot be read
# is named on stderr and the tool exits 0 with nothing on stdout.
set -uo pipefail
export LC_ALL=C

usage() { echo "usage: knowledge-drift.sh [--list]" >&2; exit 2; }
LIST=0
case "$#" in
  0) ;;
  1) [ "$1" = "--list" ] && LIST=1 || usage ;;
  *) usage ;;
esac

complain() { echo "knowledge-drift: $1" >&2; exit 0; }

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || complain "cannot find the team root"

SHA="" DATE="" BRANCH=""
report() { # <state> <line>
  if [ "$LIST" = 1 ]; then
    printf 'state\t%s\n' "$1"
    [ -z "$SHA" ] || printf 'baseline\t%s\n' "$SHA"
    [ -z "$BRANCH" ] || printf 'branch\t%s\n' "$BRANCH"
  else
    printf '%s\n' "$2"
  fi
}

# --- none ----------------------------------------------------------------------
NONE='Knowledge baseline: none — the knowledge is not committed in this branch.'
[ "$(git rev-parse --is-inside-work-tree 2>/dev/null | tr -d '\r')" = true ] \
  || { report none "$NONE"; exit 0; }
KD="$(bash "$TEAM_ROOT/tools/knowledge-dir.sh" project 2>/dev/null | tr -d '\r')"
[ -n "$KD" ] || complain "the knowledge dir cannot be resolved (tools/knowledge-dir.sh project)"
KD="${KD%/}"
[ -n "$(git ls-files -- "$KD" 2>/dev/null | head -n 1)" ] || { report none "$NONE"; exit 0; }

# --- scaffold ------------------------------------------------------------------
bash "$TEAM_ROOT/checks/verify-knowledge-scaffold.sh" . "$KD" >/dev/null 2>&1
case $? in
  1|3) report scaffold "Knowledge baseline: scaffold knowledge — nothing in it is verified against code."; exit 0 ;;
esac

# --- the manifest ----------------------------------------------------------------
# knowledge's string values and its budgets and covers entries, read by
# indentation the way tools/knowledge-dir.sh reads the manifest, never with a
# JSON parser.
M="$TEAM_ROOT/team-manifest.json"
[ -f "$M" ] || complain "no team-manifest.json in $TEAM_ROOT"
tmp="$(mktemp -d)" || complain "cannot create a temporary directory"
trap 'rm -rf "$tmp"' EXIT
awk '
  { sub(/\r$/, "") }
  index($0, "  \"knowledge\": {") == 1 { k = 1; next }
  !k { next }
  /^  }/ { exit }
  /^    }/ { blk = ""; next }
  /^    "[^"]+":[ \t]*\{/ {
    s = $0; sub(/^    "/, "", s); sub(/".*$/, "", s)
    if ($0 !~ /\}[ \t]*,?[ \t]*$/) blk = s
    next
  }
  blk == "" && /^    "[^"]+":[ \t]*"/ {
    key = $0; sub(/^    "/, "", key); sub(/".*$/, "", key)
    v = $0; sub(/^[^:]*:[ \t]*"/, "", v); sub(/".*$/, "", v)
    print key "\t" v; next
  }
  blk == "budgets" && /^      "[^"]+":[ \t]*[0-9]/ {
    key = $0; sub(/^      "/, "", key); sub(/".*$/, "", key)
    v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[^0-9].*$/, "", v)
    print "budgets." key "\t" v; next
  }
  blk == "covers" && /^      "[^"]+":[ \t]*"/ {
    key = $0; sub(/^      "/, "", key); sub(/".*$/, "", key)
    v = $0; sub(/^[^:]*:[ \t]*"/, "", v); sub(/".*$/, "", v)
    print "covers." key "\t" v; next
  }
' "$M" > "$tmp/manifest.tsv"
get() { # runs in a subshell: says what is missing and fails, the caller exits 0
  local v
  v="$(awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$tmp/manifest.tsv")"
  if [ -z "$v" ]; then
    echo "knowledge-drift: knowledge.$1 is missing from the manifest; update the team" >&2
    return 1
  fi
  printf '%s' "$v"
}
BASELINE_NAME="$(get baselineFile)" || exit 0
RULES="$(get rulesDir)" || exit 0
PROPOSALS="$(get proposalsDir)" || exit 0
PCT="$(get budgets.driftMarkedPercent)" || exit 0
MAXL="$(get budgets.driftListMaxLines)" || exit 0
awk -F'\t' 'index($1, "covers.") == 1 { print substr($1, 8) "\t" $2 }' "$tmp/manifest.tsv" > "$tmp/covers.tsv"
[ -s "$tmp/covers.tsv" ] || complain "knowledge.covers is missing from the manifest; update the team"

# --- missing ---------------------------------------------------------------------
B="$KD/$BASELINE_NAME"
if [ -f "$B" ]; then
  first=1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$first" = 1 ]; then line="${line#$'\xEF\xBB\xBF'}"; first=0; fi
    case "$line" in
      commit=*) [ -n "$SHA" ] || SHA="${line#commit=}" ;;
      date=*) [ -n "$DATE" ] || DATE="${line#date=}" ;;
      branch=*) [ -n "$BRANCH" ] || BRANCH="${line#branch=}" ;;
    esac
  done < "$B"
fi
case "$SHA" in
  *[!0-9a-fA-F]*) SHA="" ;;
esac
[ "${#SHA}" -eq 40 ] || SHA=""
if [ -z "$SHA" ]; then
  BRANCH=""
  report missing "Knowledge baseline: missing — the lag is unknown until a refresh writes it."
  exit 0
fi
SHA="$(printf '%s' "$SHA" | tr 'A-F' 'a-f')"
SHORT="${SHA:0:7}"
case "$DATE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) DATE="unknown" ;;
esac

# --- unresolved --------------------------------------------------------------------
git cat-file -e "$SHA^{commit}" 2>/dev/null || {
  report unresolved "Knowledge baseline: $SHORT ($DATE) is not in this copy — the lag is unknown."
  exit 0
}

# --- clean -----------------------------------------------------------------------
# NUL-separated, so no path is quoted or split; a newline inside a path becomes
# \001, and each path is one line.
git diff --name-only -z --no-renames --no-relative "$SHA" HEAD 2>/dev/null \
  | tr '\n\000' '\001\n' > "$tmp/all"
awk -v kd="$KD/" '$0 != "" && index($0, kd) != 1' "$tmp/all" > "$tmp/changed"
if [ ! -s "$tmp/changed" ]; then
  report clean "Knowledge baseline: $SHORT ($DATE). Nothing changed since."
  exit 0
fi

# --- the located topics ------------------------------------------------------------
find "$KD" \( -path "$KD/$RULES" -o -path "$KD/$PROPOSALS" \) -prune -o -type f -name '*.md' -print 2>/dev/null \
  | sort > "$tmp/files"
FILES=()
while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done < "$tmp/files"
: > "$tmp/found.tsv"
if [ "${#FILES[@]}" -gt 0 ]; then
  awk -v bom="$(printf '\357\273\277')" -v banner="> SCAFFOLD — " '
    { sub(/\r$/, "") }
    FNR == 1 {
      if (index($0, bom) == 1) $0 = substr($0, 4)
      start = (index($0, banner) == 1) ? 2 : 1
    }
    FNR >= start && FNR < start + 5 && !(FILENAME in seen) && index($0, "Covers:") == 1 {
      seen[FILENAME] = 1
      print FILENAME "\t" substr($0, 8)
    }
  ' "${FILES[@]}" > "$tmp/found.tsv"
fi

# --- marking ---------------------------------------------------------------------
# Records: M <file> <n> <pattern> (pattern empty for a missing Covers: line),
# U <group> <n>, and one S <changed> <located> <marked>.
awk -F'\t' -v kd="$KD/" -v fdef="$tmp/covers.tsv" -v ffound="$tmp/found.tsv" \
    -v ffiles="$tmp/files" -v fchanged="$tmp/changed" '
  function esc(s,    i, c, out) {
    out = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      out = out ((index("\\^$.|?*+()[]{}", c) > 0) ? "\\" c : c)
    }
    return out
  }
  # A git glob pathspec as an anchored extended regular expression.
  function glob2re(p,    L, i, c, pre, rest, re, j, k, n, prevok, nxt, neg, body, e) {
    L = length(p)
    for (i = 1; i <= L; i++) {
      c = substr(p, i, 1)
      if (c == "*" || c == "?" || c == "[" || c == "\\") break
    }
    if (i > L) {                      # no wildcard: the path or a directory
      sub(/\/+$/, "", p)
      return "^" esc(p) "(/.*)?$"
    }
    pre = substr(p, 1, i - 1); rest = substr(p, i); n = length(rest)
    re = "^" esc(pre)
    j = 1
    while (j <= n) {
      c = substr(rest, j, 1)
      if (c == "*") {
        k = j
        while (k < n && substr(rest, k + 1, 1) == "*") k++
        if (k > j) {
          prevok = (j == 1 || substr(rest, j - 1, 1) == "/")
          nxt = (k < n) ? substr(rest, k + 1, 1) : ""
          if (prevok && nxt == "/") { re = re "(.*/)?"; j = k + 2; continue }
          if (prevok && nxt == "") { re = re ".*"; j = k + 1; continue }
        }
        re = re "[^/]*"; j = k + 1; continue
      }
      if (c == "?") { re = re "[^/]"; j++; continue }
      if (c == "\\" && j < n) { re = re esc(substr(rest, j + 1, 1)); j += 2; continue }
      if (c == "[") {
        k = j + 1; neg = 0; body = ""
        if (k <= n && (substr(rest, k, 1) == "!" || substr(rest, k, 1) == "^")) { neg = 1; k++ }
        if (k <= n && substr(rest, k, 1) == "]") { body = "]"; k++ }
        while (k <= n && substr(rest, k, 1) != "]") {
          if (substr(rest, k, 2) == "[:" && (e = index(substr(rest, k + 2), ":]")) > 0) {
            body = body substr(rest, k, e + 3); k += e + 3; continue
          }
          if (substr(rest, k, 1) != "\\") body = body substr(rest, k, 1)
          k++
        }
        if (k <= n) {
          if (neg) {
            if (substr(body, length(body)) == "-") body = substr(body, 1, length(body) - 1) "/-"
            else body = body "/"
            re = re "[^" body "]"
          } else re = re "[" body "]"
          j = k + 1; continue
        }
      }
      re = re esc(c); j++
    }
    return re "$"
  }
  function count(p,    re, c, n) {
    if (p in cnt) return cnt[p]
    re = glob2re(p); n = 0
    for (c = 1; c <= nc; c++) if (ch[c] ~ re) { n++; covered[c] = 1 }
    cnt[p] = n
    return n
  }
  FILENAME == fdef { def[$1] = $2; next }
  FILENAME == ffound { found[$1] = substr($0, length($1) + 2); next }
  FILENAME == ffiles { nf++; file[nf] = $0; next }
  FILENAME == fchanged { nc++; ch[nc] = $0; next }
  END {
    located = 0; marked = 0
    for (i = 1; i <= nf; i++) {
      f = file[i]; rel = substr(f, length(kd) + 1)
      if (f in found) {
        v = found[f]; gsub(/^[ \t]+|[ \t]+$/, "", v)
        if (v == "conventions" || v == "topics") continue
        np = split(v, parts, ","); k = 0
        for (j = 1; j <= np; j++) {
          q = parts[j]; gsub(/^[ \t]+|[ \t]+$/, "", q)
          if (q != "") pat[++k] = q
        }
        if (k > 0) {
          located++; best = ""; bestn = 0
          for (j = 1; j <= k; j++) { n = count(pat[j]); if (n > bestn) { bestn = n; best = pat[j] } }
          if (bestn > 0) { marked++; print "M\t" rel "\t" bestn "\t" best }
          continue
        }
      }
      idx = rel
      if (index(rel, "/") > 0) idx = toupper(substr(rel, 1, index(rel, "/") - 1)) ".md"
      if ((idx in def) && def[idx] == "paths") { located++; marked++; print "M\t" rel "\t0\t" }
    }
    for (c = 1; c <= nc; c++) {
      if (c in covered) continue
      n = split(ch[c], seg, "/")
      g = (n >= 3) ? seg[1] "/" seg[2] "/" : (n == 2) ? seg[1] "/" : ch[c]
      ug[g]++
    }
    for (g in ug) print "U\t" g "\t" ug[g]
    print "S\t" nc "\t" located "\t" marked
  }
' "$tmp/covers.tsv" "$tmp/found.tsv" "$tmp/files" "$tmp/changed" > "$tmp/records"

awk -F'\t' '$1 == "M" { print $2 "\t" $3 "\t" $4 }' "$tmp/records" | sort > "$tmp/marked"
awk -F'\t' '$1 == "U" { print $2 "\t" $3 }' "$tmp/records" | sort > "$tmp/uncovered"
read -r N LOCATED MARKED <<EOF
$(awk -F'\t' '$1 == "S" { print $2, $3, $4 }' "$tmp/records")
EOF
[ -n "${MARKED:-}" ] || complain "the change set could not be matched against the Covers lines"
SHARE=0
[ "${LOCATED:-0}" -gt 0 ] && SHARE=$(( MARKED * 100 / LOCATED ))
STATE=listed
[ "$SHARE" -gt "$PCT" ] && STATE=over

if [ "$LIST" = 1 ]; then
  report "$STATE" ""
  awk -F'\t' '{ print "marked\t" $1 "\t" $2 }' "$tmp/marked"
  awk -F'\t' '{ print "uncovered\t" $1 "\t" $2 }' "$tmp/uncovered"
  exit 0
fi

if [ "$STATE" = over ]; then
  C="$(git rev-list --count "$SHA..HEAD" 2>/dev/null | tr -d '\r')"
  printf '%s\n' "Knowledge baseline: $SHORT ($DATE). ${C:-?} commits behind, $SHARE% of the located topics changed: a refresh is due; verify every topic against the code."
  exit 0
fi

printf '%s\n' "Knowledge baseline: $SHORT ($DATE). Changed since: $N files."
if [ -s "$tmp/marked" ]; then
  echo "Verify against the code before relying on:"
  awk -F'\t' -v max="$MAXL" '
    NR <= max { print "- " $1 "  (" (($3 == "") ? "no Covers line" : $3 ": " $2 " files") ")" }
    END { if (NR > max) print "- … and " (NR - max) " more" }
  ' "$tmp/marked"
fi
awk -F'\t' -v max="$MAXL" '
  NR <= max { s = s ((NR > 1) ? ", " : "") (($1 ~ /\/$/) ? $1 " (" $2 " files)" : $1) }
  END {
    if (NR > max) s = s ", … and " (NR - max) " more"
    if (NR > 0) print "Not covered by knowledge: " s
  }
' "$tmp/uncovered"
exit 0
