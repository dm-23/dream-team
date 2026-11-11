#!/usr/bin/env bash
# Dream Team — moves the rules a person authored out of the generated
# knowledge files into rule files, one per rule, under <knowledge-dir>/rules/
# (the format is templates/rule.md).
#
#   bash <team-root>/tools/extract-rules.sh [--dry-run] <knowledge-dir>
#
# It reads every *.md of the directory outside rules/ and proposals/, topic
# directories included, in byte order of their paths. An authored line is one
# that contains "— source: learnings " or ends "— source: user" (a trailing
# CR ignored), or, in REVIEW-CHECKLIST.md, any "- " line under
# "## Accepted exceptions" other than "- none". Its text is the line without
# the list marker ("- ", "<n>. "), the trailing CR and the source suffix.
#
#   "— source: user" under "## Critical zones"  kind critical-zone, Zone: the
#                     text, title the text before " — ".
#   "— source: user" elsewhere                  kind rule, Rule: the text,
#                     title its first 60 characters.
#   "— source: learnings <date> <title>"        kind rule, title <title>.
#                     Every line with the same suffix (date and title) makes
#                     one file. A line from a file other than
#                     REVIEW-CHECKLIST.md is Rule:; when several are, the first
#                     one found is Rule: and the others are removed with it.
#                     The REVIEW-CHECKLIST.md line is Check:. With only a
#                     checklist line, Rule: and Check: both carry it.
#   an accepted exception                       kind exception, Exception: the
#                     text, title "exception <path>" (the text before " · ").
#
# "Belongs with:" (rules only) is the required file (knowledge.required) that
# held the Rule: line; a file in a topic directory counts as its index file,
# the required file whose lower-cased base name is the directory's name.
# "Source:" is the suffix as written ("user" for an exception); "Added:" is
# today. The file name is the title under the slug transform of
# templates/learnings-entry.md ("rule" when that is empty), with -2, -3 ...
# when the name exists or this run took it.
#
# The authored lines are removed from their files; every other byte stays (a
# CRLF line keeps its CR, a missing last newline stays missing), list numbers
# are not renumbered. A "## Accepted exceptions" section whose every line is
# blank or extracted goes whole, heading included, up to the next heading or
# the end of the file; one that keeps any other line keeps its heading. The
# rule files are written before the sources are rewritten, so an interrupted
# run leaves a rule twice, never lost.
#
# Prints one line:
#   rules: extracted <N> (<R> rules, <Z> critical zones, <E> exceptions) into <dir>/rules
#   rules: nothing to extract
# --dry-run prefixes "would: " and writes nothing.
#
# Exit 0 = done or nothing to do. 2 = bad arguments, an unreadable directory
# or manifest, or a failed write.
set -uo pipefail
export LC_ALL=C

usage() { echo "usage: extract-rules.sh [--dry-run] <knowledge-dir>" >&2; exit 2; }
dry=0
if [ "${1:-}" = --dry-run ]; then dry=1; shift; fi
[ $# -eq 1 ] && [ -n "$1" ] || usage
DIR="$1"
[ "$DIR" = / ] || DIR="${DIR%/}"
if [ ! -d "$DIR" ] || [ ! -r "$DIR" ]; then
  echo "extract-rules: cannot read directory: $DIR" >&2
  exit 2
fi

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 2
M="$TEAM_ROOT/team-manifest.json"
[ -f "$M" ] || { echo "extract-rules: no team-manifest.json in $TEAM_ROOT" >&2; exit 2; }

# knowledge.required: the strings of the array, which may span lines.
REQUIRED="$(tr -d '\r' < "$M" | awk '
  index($0, "  \"knowledge\": {") == 1 { k = 1; next }
  k && /^  }/ { exit }
  k && index($0, "    \"required\":") == 1 { r = 1; sub(/^[^[]*\[/, "") }
  r { s = $0; done = sub(/\].*$/, "", s)
      n = split(s, a, ",")
      for (i = 1; i <= n; i++) { v = a[i]; gsub(/^[ \t]*"|"[ \t]*$/, "", v); if (v != "") print v }
      if (done) exit }')"
[ -n "$REQUIRED" ] || { echo "extract-rules: no knowledge.required in $M" >&2; exit 2; }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
TODAY="$(date +%Y-%m-%d)"
US=$'\037'

mapfile -t FILES < <(find "$DIR" \( -path "$DIR/rules" -o -path "$DIR/proposals" \) -prune -o -type f -name '*.md' -print 2>/dev/null | sort)

: > "$TMP/records"; : > "$TMP/deletions"
if [ "${#FILES[@]}" -gt 0 ]; then
  REQ="$REQUIRED" awk -v dir="$DIR" -v recs="$TMP/records" -v dels="$TMP/deletions" '
    BEGIN {
      mid = "— source: learnings "; tail = "— source: user"; US = "\037"
      n = split(ENVIRON["REQ"], R, "\n")
      for (i = 1; i <= n; i++) if (R[i] != "") { b = tolower(R[i]); sub(/\.md$/, "", b); idx[b] = R[i] }
    }
    # The file a path belongs with: itself at the top, its index file in a topic directory.
    function homeof(p,   top) {
      if (index(p, "/") == 0) return p
      top = tolower(substr(p, 1, index(p, "/") - 1))
      return (top in idx) ? idx[top] : p
    }
    function textof(s) {
      sub(/[ \t]+$/, "", s); sub(/^[ \t]*([-*+]|[0-9]+\.)[ \t]+/, "", s); sub(/^[ \t]+/, "", s)
      return s
    }
    function del(ln) { print rel US ln > dels }
    function newrec(kind, title) { nrec++; K[nrec] = kind; T[nrec] = title; return nrec }
    # The end of an "## Accepted exceptions" section: it goes whole when every
    # line under it is blank or extracted.
    function endsec(   m, i, b) {
      if (ae && aen > 0 && aeclean) {
        print aefile US aestart > dels
        m = split(aeb, b, " ")
        for (i = 1; i <= m; i++) print aefile US b[i] > dels
      }
      ae = 0
    }
    FNR == 1 {
      endsec()
      rel = substr(FILENAME, length(dir) + 2)
      home = homeof(rel); ischeck = (home == "REVIEW-CHECKLIST.md"); isrc = (rel == "REVIEW-CHECKLIST.md")
      sec = ""
    }
    {
      line = $0; sub(/\r$/, "", line)
      if (line ~ /^##? /) {
        endsec()
        sec = line; sub(/[ \t]+$/, "", sec)
        if (isrc && sec == "## Accepted exceptions") { ae = 1; aestart = FNR; aeclean = 1; aen = 0; aeb = ""; aefile = rel }
        next
      }
      if (ae) {
        t = line; sub(/[ \t]+$/, "", t)
        if (t ~ /^- / && t != "- none") {
          text = textof(line)
          p = index(text, " · "); path = p ? substr(text, 1, p - 1) : text
          r = newrec("exception", "exception " path); X[r] = text; S[r] = "user"
          del(FNR); aen++
          next
        }
        if (t == "") aeb = aeb " " FNR
        else aeclean = 0
      }
      i = index(line, mid)
      if (i > 0) {
        key = substr(line, i + length(mid)); sub(/[ \t]+$/, "", key)
        text = textof(substr(line, 1, i - 1))
        if (!(key in G)) {
          title = key
          if (key ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] /) { title = substr(key, 12); sub(/^[ \t]+/, "", title) }
          if (title == "") title = key
          G[key] = newrec("rule", title); S[G[key]] = "learnings " key
        }
        r = G[key]
        if (ischeck) { if (!(r in C)) { C[r] = text; CH[r] = home } }
        else if (!(r in RU)) { RU[r] = text; B[r] = home }
        del(FNR)
        next
      }
      if (length(line) >= length(tail) && substr(line, length(line) - length(tail) + 1) == tail) {
        text = textof(substr(line, 1, length(line) - length(tail)))
        if (sec == "## Critical zones") {
          p = index(text, " — "); title = p ? substr(text, 1, p - 1) : text
          r = newrec("critical-zone", title); Z[r] = text
        } else {
          r = newrec("user-rule", ""); RU[r] = text; B[r] = home
        }
        S[r] = "user"
        del(FNR)
      }
    }
    END {
      endsec()
      for (r = 1; r <= nrec; r++) {
        if (K[r] == "rule" && !(r in RU)) { RU[r] = C[r]; B[r] = CH[r] }
        print K[r] US T[r] US RU[r] US C[r] US Z[r] US X[r] US B[r] US S[r] > recs
      }
    }
  ' "${FILES[@]}" || { echo "extract-rules: could not read the files of $DIR" >&2; exit 2; }
fi

slug() { # the slug of a title (templates/learnings-entry.md)
  printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//' | cut -c1-60 | sed 's/-$//'
}
first60() { # the first 60 characters, counted in UTF-8 where the locale exists
  local LC_ALL=C.UTF-8
  printf '%s' "${1:0:60}"
}

declare -A taken
mkdir -p "$TMP/rules" || exit 2
: > "$TMP/written"
R=0 Z=0 E=0
while IFS="$US" read -r kind title rule check zone exc bel src; do
  case "$kind" in
    user-rule) kind=rule; title="$(first60 "$rule")"; title="${title%"${title##*[![:space:]]}"}" ;;
  esac
  case "$kind" in rule) R=$((R + 1)) ;; critical-zone) Z=$((Z + 1)) ;; exception) E=$((E + 1)) ;; esac
  base="$(slug "$title")"; [ -n "$base" ] || base=rule
  i=1
  while :; do
    if [ "$i" = 1 ]; then name="$base.md"; else name="$base-$i.md"; fi
    if [ -e "$DIR/rules/$name" ] || [ -n "${taken[$name]:-}" ]; then i=$((i + 1)); continue; fi
    taken[$name]=1; break
  done
  {
    printf '# %s\n' "$title"
    printf -- '- Kind: %s\n' "$kind"
    [ -z "$rule" ] || printf -- '- Rule: %s\n' "$rule"
    [ -z "$check" ] || printf -- '- Check: %s\n' "$check"
    [ -z "$zone" ] || printf -- '- Zone: %s\n' "$zone"
    [ -z "$exc" ] || printf -- '- Exception: %s\n' "$exc"
    [ -z "$bel" ] || printf -- '- Belongs with: %s\n' "$bel"
    printf -- '- Source: %s\n' "$src"
    printf -- '- Added: %s\n' "$TODAY"
  } > "$TMP/rules/$name" || exit 2
  printf '%s\n' "$name" >> "$TMP/written"
done < "$TMP/records"

N=$((R + Z + E))
pfx=""; [ "$dry" = 0 ] || pfx="would: "
if [ "$N" = 0 ]; then
  echo "${pfx}rules: nothing to extract"
  exit 0
fi
line="rules: extracted $N ($R rules, $Z critical zones, $E exceptions) into $DIR/rules"
if [ "$dry" = 1 ]; then
  echo "$pfx$line"
  exit 0
fi

werr() { echo "extract-rules: could not $1 (read-only or open elsewhere?); fix that and run again" >&2; exit 2; }

# The sources, rewritten into the temporary directory first.
sort -t "$US" -k1,1 -k2,2n -u "$TMP/deletions" > "$TMP/dels.sorted"
cut -d "$US" -f1 "$TMP/dels.sorted" | uniq > "$TMP/dfiles"
n=0
: > "$TMP/rewrites"
while IFS= read -r rel; do
  n=$((n + 1)); f="$DIR/$rel"
  lines="$(awk -F "$US" -v r="$rel" '$1 == r { printf "%s ", $2 }' "$TMP/dels.sorted")"
  nonl=0; [ ! -s "$f" ] || [ "$(tail -c 1 "$f" | wc -l | tr -d ' ')" != 0 ] || nonl=1
  # BINMODE=3: gawk on Windows otherwise drops the CR of a CRLF line.
  awk -v BINMODE=3 -v lines="$lines" -v nonl="$nonl" '
    BEGIN { m = split(lines, a, " "); for (i = 1; i <= m; i++) d[a[i]] = 1 }
    { if (have) printf "%s\n", pl; have = 0 }
    !(FNR in d) { pl = $0; have = 1 }
    END { if (have) printf "%s%s", pl, (nonl ? "" : "\n") }
  ' "$f" > "$TMP/src.$n" || werr "read $f"
  printf '%s\t%s\n' "$TMP/src.$n" "$f" >> "$TMP/rewrites"
done < "$TMP/dfiles"

# The rule files first, then the sources.
mkdir -p "$DIR/rules" || werr "create $DIR/rules/"
while IFS= read -r name; do
  mv -- "$TMP/rules/$name" "$DIR/rules/$name" || werr "write $DIR/rules/$name"
done < "$TMP/written"
while IFS="$(printf '\t')" read -r src f; do
  mv -- "$src" "$f" || werr "rewrite $f"
done < "$TMP/rewrites"

echo "$line"
exit 0
