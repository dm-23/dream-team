#!/usr/bin/env bash
# Dream Team — moves a project's knowledge out of this edition's own directory
# (knowledge.legacyDir). The operative files (LEARNINGS.md, learnings/,
# CAPABILITIES.md) go to knowledge.operativeDir and knowledge.capabilitiesDir;
# the project files go to knowledge.dir, the committed directory every
# edition reads. See team-manifest.json → knowledge.
#
#   bash <team-root>/tools/migrate-knowledge.sh [--dry-run] [--first-commit [--from <dir>] | --drop-legacy]
#                                                           (from the project root)
#
# Every mode moves the operative files first. Then the inbox moves from
# operativeDir into the developer's profile, <profile root>/<key>/, which all
# working copies of the repository share (the profile root and the key as
# tools/knowledge-dir.sh computes them):
#   - profileDir empty, or no remote (no key): the inbox stays per copy.
#   - <profile>/learnings is created and a probe file written and removed
#     there; on any failure the directories this step created are removed
#     and the inbox stays per copy (exit 0).
#   - LEARNINGS.md, learnings/ and review-exceptions.md are backed up to
#     operativeDir/inbox-backup-<YYYY-MM-DD-HHmm>/.
#   - The inline entries of an older LEARNINGS.md (each "## [date] title"
#     body, cut as checks/verify-knowledge-integrity.sh cuts it) become entry
#     files in learnings/, byte for byte, named <date>-<slug>.md by the rules
#     of templates/learnings-entry.md ("entry" for an empty slug; -2, -3
#     when taken); LEARNINGS.md then
#     moves to operativeDir/dropped-index-<YYYY-MM-DD-HHmm>.md. An unclosed
#     fence or an inline heading without a date keeps the inbox per copy.
#   - Every learnings/*.md moves into the profile: a name already there with
#     the same bytes drops the source; with other bytes it moves under the
#     first free -2, -3 ... suffix.
#   - review-exceptions.md moves, or, when the profile has one, the lines it
#     lacks (whole line, CR ignored) are appended and the source removed.
#   - CAPABILITIES.md, the import stamp, the backups and the
#     legacy-knowledge-* directories stay in operativeDir.
# Then, for the project files:
#   default         the committed copy is tracked in this branch: authored
#                   lines of the private copy that the committed copy lacks
#                   become inbox entries (entry files only, written into the
#                   inbox as the step above left it), once per edition (a stamp in
#                   capabilitiesDir records it), and the private copy stays
#                   for branches without knowledge. Nothing tracked: the
#                   report says what the first commit still needs.
#   --first-commit  the project files move into knowledge.dir, which must not
#                   exist yet. This edition's directory moves with one rename;
#                   another edition's (--from picks it when both hold project
#                   files) is staged entry by entry in knowledge.dir.migrating,
#                   which is renamed at the end, so an interrupted run resumes
#                   and knowledge.dir only ever appears complete. Then
#                   tools/extract-rules.sh moves the authored lines of the
#                   moved files into knowledge.dir/<knowledge.rulesDir>/ and its line is
#                   printed.
#   --drop-legacy   the committed copy is tracked: authored lines the inbox
#                   does not hold yet become entries, then the private copy is
#                   backed up under operativeDir, checked, and removed.
#   --dry-run       prints what a run would do, prefixed "would:"; writes
#                   nothing, and creates no profile directory.
#
# In the default mode and --drop-legacy, an authored line of the private copy
# is already held, and becomes no entry, when the committed copy holds the
# whole line (CR ignored) or when its text (the line without the list marker,
# the source suffix and the CR) is the value of a "- Rule:", "- Check:",
# "- Zone:" or "- Exception:" line of a file directly inside knowledge.dir/<knowledge.rulesDir>/.
#
# Every refusal is decided before the first write, so a refused run leaves the
# tree as it found it. Moves are byte-exact (mv); a moved file is rewritten
# only by the extractor after a first commit, which removes its authored lines
# and keeps every other byte.
#
# Exit 0 = done, nothing to do, or a dry run. 1 = refused: a run is open, the
# run state is still in the legacy tracking directory, a name exists on both
# sides, or the mode's precondition does not hold. 2 = error: bad arguments,
# the manifest, a symbolic link, or a failed write.
set -uo pipefail

usage() { echo "usage: migrate-knowledge.sh [--dry-run] [--first-commit [--from <dir>] | --drop-legacy]" >&2; exit 2; }
dry=0 mode=default from="" fromset=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --first-commit) [ "$mode" != drop ] || usage; mode=first ;;
    --drop-legacy) [ "$mode" != first ] || usage; mode=drop ;;
    --from) [ $# -ge 2 ] && [ -n "$2" ] || usage; from="$2"; fromset=1; shift ;;
    *) usage ;;
  esac
  shift
done
[ "$fromset" = 0 ] || [ "$mode" = first ] || usage
from="${from#./}"; from="${from%/}"

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 2
M="$TEAM_ROOT/team-manifest.json"
[ -f "$M" ] || { echo "migrate-knowledge: no team-manifest.json in $TEAM_ROOT" >&2; exit 2; }

# The string value of a key placed directly inside a top-level block.
value_in() {
  tr -d '\r' < "$M" | awk -v b="$1" -v k="$2" '
    index($0, "  \"" b "\": {") == 1 { f = 1; next }
    f && /^  }/ { exit }
    f && index($0, "    \"" k "\":") == 1 { sub(/^[^:]*:[ \t]*"/, ""); sub(/".*$/, ""); print; exit }'
}
# The strings of a one-line array placed directly inside a top-level block.
array_in() {
  tr -d '\r' < "$M" | awk -v b="$1" -v k="$2" '
    index($0, "  \"" b "\": {") == 1 { f = 1; next }
    f && /^  }/ { exit }
    f && index($0, "    \"" k "\":") == 1 {
      sub(/^[^[]*\[/, ""); sub(/\].*$/, "")
      n = split($0, a, ",")
      for (i = 1; i <= n; i++) { s = a[i]; gsub(/^[ \t]*"|"[ \t]*$/, "", s); if (s != "") print s }
      exit }'
}
# A project-root-relative path: not empty, not absolute, no "..".
rel_ok() {
  case "$2" in
    ''|/*|*..*) echo "migrate-knowledge: $1 must be a project-root-relative path (got '$2')" >&2; exit 2 ;;
  esac
}

DIR="$(value_in knowledge dir)";                 DIR="${DIR%/}";       rel_ok knowledge.dir "$DIR"
LEGACY="$(value_in knowledge legacyDir)";        LEGACY="${LEGACY%/}"; rel_ok knowledge.legacyDir "$LEGACY"
OPS="$(value_in knowledge operativeDir)";        OPS="${OPS%/}";       rel_ok knowledge.operativeDir "$OPS"
CAPS="$(value_in knowledge capabilitiesDir)";    CAPS="${CAPS%/}";     rel_ok knowledge.capabilitiesDir "$CAPS"
RULESD="$(value_in knowledge rulesDir)";         RULESD="${RULESD%/}"; rel_ok knowledge.rulesDir "$RULESD"
TRK="$(value_in tracking dir)";                  TRK="${TRK%/}";       rel_ok tracking.dir "$TRK"
TRKOLD="$(value_in tracking legacyDir)";         TRKOLD="${TRKOLD%/}"; rel_ok tracking.legacyDir "$TRKOLD"
OTHERS="$(array_in knowledge otherEditionDirs)"

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
# Per edition: each edition's private copy is imported once, by its own migration.
STAMP="$CAPS/.legacy-rules-imported"
# An interrupted move from another edition's directory, and the source it records.
STAGE="$DIR.migrating"
SRCREC="$STAGE/.migrate-source"
TODAY="$(date +%Y-%m-%d)"
NOW="$(date +%Y-%m-%d-%H%M)"
TAB="$(printf '\t')"
CR=$'\r'
COMMIT_LINE="project: moved to $DIR: run /generate-knowledge, then commit it alone, one commit and one pull request, no other file"

# --- 1. refusals ---------------------------------------------------------
links=""
for p in "$LEGACY" "$LEGACY/learnings" "$DIR" "$STAGE" "$OPS" "$OPS/learnings" "$CAPS" ${from:+"$from"}; do
  [ ! -L "$p" ] || links="$links $p"
done
if [ "$mode" = first ]; then
  while IFS= read -r o; do [ -z "$o" ] || [ ! -L "${o%/}" ] || links="$links ${o%/}"; done <<EOF
$OTHERS
EOF
fi
if [ -n "$links" ]; then
  echo "migrate-knowledge: a symbolic link:$links; refusing to touch anything. Replace it with a real directory and run again." >&2
  exit 2
fi
for p in "$LEGACY" "$DIR" "$STAGE" "$OPS" "$CAPS"; do
  [ ! -e "$p" ] || [ -d "$p" ] || { echo "migrate-knowledge: $p exists but is not a directory" >&2; exit 2; }
done

if [ -f "$TRK/.team-mode" ] && [ "$(sed -n 's/^state=//p' "$TRK/.team-mode" | head -1 | tr -d '\r')" != "closed" ]; then
  cid="$(sed -n 's/^context_id=//p' "$TRK/.team-mode" | head -1 | tr -d '\r')"
  echo "migrate-knowledge: refused — a run is open: ${cid:-unknown} (marker $TRK/.team-mode)." >&2
  echo "In the session that runs it: /team stop. Then /team-setup, then /team resume." >&2
  exit 1
fi
if [ -e "$TRKOLD" ]; then
  echo "migrate-knowledge: refused — run state is still in the legacy directory ($TRKOLD/) — run /team-setup first" >&2
  exit 1
fi

# Project files in a directory: a *.md directly inside other than LEARNINGS.md
# and CAPABILITIES.md (the resolver's rule, tools/knowledge-dir.sh).
has_project() {
  local f
  [ -d "$1" ] || return 1
  for f in "$1"/*.md; do
    [ -f "$f" ] || continue
    case "${f##*/}" in LEARNINGS.md|CAPABILITIES.md) continue ;; esac
    return 0
  done
  return 1
}
# Entries of a directory other than the operative ones, one path per line.
project_entries() {
  find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | LC_ALL=C sort | while IFS= read -r e; do
    case "${e##*/}" in LEARNINGS.md|learnings|CAPABILITIES.md) continue ;; esac
    printf '%s\n' "$e"
  done
}
# This edition's directory or one of the other editions' directories.
known_dir() {
  [ "$1" = "$LEGACY" ] && return 0
  printf '%s\n' "$OTHERS" | sed 's|/$||' | grep -qxF -- "$1"
}

# --- 2. the operative part, planned ----------------------------------------
: > "$TMP/moves"; : > "$TMP/conflicts"
plan() { # <src> <dst> <name>
  if [ -e "$2" ] || [ -L "$2" ]; then echo "  $3" >> "$TMP/conflicts"; else printf '%s\t%s\n' "$1" "$2" >> "$TMP/moves"; fi
}
[ ! -e "$LEGACY/LEARNINGS.md" ] || plan "$LEGACY/LEARNINGS.md" "$OPS/LEARNINGS.md" "LEARNINGS.md (in $OPS/)"
if [ -d "$LEGACY/learnings" ]; then
  if [ -e "$OPS/learnings" ] && [ ! -d "$OPS/learnings" ]; then
    echo "  learnings (in $OPS/, not a directory)" >> "$TMP/conflicts"
  else
    find "$LEGACY/learnings" -mindepth 1 -maxdepth 1 | LC_ALL=C sort > "$TMP/lentries"
    while IFS= read -r e; do plan "$e" "$OPS/learnings/${e##*/}" "learnings/${e##*/} (in $OPS/)"; done < "$TMP/lentries"
  fi
elif [ -e "$LEGACY/learnings" ]; then
  echo "migrate-knowledge: $LEGACY/learnings exists but is not a directory" >&2; exit 2
fi
[ ! -e "$LEGACY/CAPABILITIES.md" ] || plan "$LEGACY/CAPABILITIES.md" "$CAPS/CAPABILITIES.md" "CAPABILITIES.md (in $CAPS/)"
if [ -s "$TMP/conflicts" ]; then
  echo "migrate-knowledge: refused — these names exist in both $LEGACY/ and the operative directory. Keep one of each (delete or merge the other by hand), then run again; nothing was moved:" >&2
  cat "$TMP/conflicts" >&2
  exit 1
fi
nmoves="$(wc -l < "$TMP/moves" | tr -d ' ')"
if [ "$nmoves" -gt 0 ]; then ops_line="operative: moved $nmoves entries to $OPS"; else ops_line="operative: nothing to move"; fi

# --- 2b. the profile, planned --------------------------------------------------
# The profile directory: <profile root>/<key>, by the resolver's rule
# (tools/knowledge-dir.sh): $DREAM_TEAM_PROFILE, else profileDir with a
# leading ~ replaced by $HOME; shown through cygpath -m where it exists.
PROFILE_CFG="$(value_in knowledge profileDir)"
PDIR="" PSHOW="" KEY="" prof_reason="" pidle=0
if [ -z "$PROFILE_CFG" ]; then
  prof_reason="profile disabled"
elif ! KEY="$(bash "$TEAM_ROOT/tools/knowledge-dir.sh" key 2>/dev/null)" || [ -z "$KEY" ]; then
  KEY=""; prof_reason="no remote"
else
  PROOT="${DREAM_TEAM_PROFILE:-}"
  [ -n "$PROOT" ] || case "$PROFILE_CFG" in "~"|"~/"*) PROOT="${HOME:-}${PROFILE_CFG#\~}" ;; *) PROOT="$PROFILE_CFG" ;; esac
  if [ -n "$PROOT" ]; then PDIR="${PROOT%/}/$KEY"; else prof_reason="profile not writable"; fi
fi
PSHOW="$PDIR"
if [ -n "$PDIR" ] && command -v cygpath >/dev/null 2>&1; then PSHOW="$(cygpath -m "$PDIR")"; fi

slug() { # the slug of an entry title (templates/learnings-entry.md)
  printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//' | cut -c1-60 | sed 's/-$//'
}
lookup() { # <file> <name>: the path recorded for <name> in a name<TAB>path file
  LC_ALL=C awk -F'\t' -v n="$2" '$1 == n { print $2; exit }' "$1"
}

# profile_plan pending|now: what the step does to the inbox in operativeDir,
# as it is now or as the operative part above leaves it (pending). Fills
# $TMP/lifts (split entry, name), $TMP/pmoves (name, name in the profile or
# empty when the profile holds the same bytes); sets PIDX, PL, PN, PM, PS,
# PEXC and pidle, or prof_reason when the inbox has to stay per copy.
profile_plan() {
  local f src dst h d edate etitle eslug base i cand other nm stem nonl
  : > "$TMP/inbox"
  if [ -d "$OPS/learnings" ]; then
    for f in "$OPS/learnings"/*.md; do
      [ ! -f "$f" ] || printf '%s\t%s\n' "${f##*/}" "$f" >> "$TMP/inbox"
    done
  fi
  PIDX=""; [ ! -f "$OPS/LEARNINGS.md" ] || PIDX="$OPS/LEARNINGS.md"
  if [ "$1" = pending ]; then
    while IFS="$TAB" read -r src dst; do
      case "$dst" in
        "$OPS/LEARNINGS.md") PIDX="$src" ;;
        "$OPS/learnings/"*.md) [ ! -f "$src" ] || printf '%s\t%s\n' "${dst##*/}" "$src" >> "$TMP/inbox" ;;
      esac
    done < "$TMP/moves"
  fi
  PEXC=0; [ ! -f "$OPS/review-exceptions.md" ] || PEXC=1

  # Step 4, the lift: split_entries of checks/verify-knowledge-integrity.sh,
  # writing every line as read, so CRs and a missing last newline survive
  # (BINMODE=3: gawk on Windows otherwise drops the CR of a CRLF line).
  : > "$TMP/lifts"; PL=0
  cp "$TMP/inbox" "$TMP/taken"
  rm -rf "$TMP/split"; mkdir -p "$TMP/split"
  if [ -n "$PIDX" ]; then
    nonl=0; [ ! -s "$PIDX" ] || [ "$(tail -c 1 "$PIDX" | wc -l | tr -d ' ')" != 0 ] || nonl=1
    LC_ALL=C awk -v BINMODE=3 -v out="$TMP/split" -v nonl="$nonl" '
      { if (have) printf "%s\n", pl > pf; have = 0 }
      /^```/                 { fence = !fence }
      !fence && /^## \[/     { if (f != "") close(f); n++; f = sprintf("%s/entry-%04d", out, n) }
      n > 0                  { pl = $0; pf = f; have = 1 }
      END                    { if (have) printf "%s%s", pl, (nonl ? "" : "\n") > pf; if (fence) exit 2 }
    ' "$PIDX"
    case $? in
      0) ;;
      2) prof_reason="LEARNINGS.md ends inside a fenced block; balance its fences and run again"; return ;;
      *) echo "migrate-knowledge: could not read $PIDX" >&2; exit 2 ;;
    esac
    for f in "$TMP/split"/entry-*; do
      [ -f "$f" ] || continue
      h=""; IFS= read -r h < "$f"; h="${h%"$CR"}"
      d="${h#"## ["}"; edate="${d%%"]"*}"; etitle="${d#*"]"}"; etitle="${etitle# }"
      case "$edate" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
        *) prof_reason="an inline entry of LEARNINGS.md has no date in its heading ($h); fix the heading and run again"; return ;;
      esac
      # A title with no ASCII letter or digit: "entry", as extract-rules.sh says "rule".
      eslug="$(slug "$etitle")"; [ -n "$eslug" ] || eslug=entry
      base="$edate-$eslug"; i=1
      while :; do
        if [ "$i" = 1 ]; then cand="$base.md"; else cand="$base-$i.md"; fi
        other="$(lookup "$TMP/taken" "$cand")"
        if [ -z "$other" ]; then
          printf '%s\t%s\n' "$cand" "$f" >> "$TMP/taken"; printf '%s\t%s\n' "$f" "$cand" >> "$TMP/lifts"
          PL=$((PL + 1)); break
        elif cmp -s "$f" "$other"; then
          break   # the entry file already holds it
        fi
        i=$((i + 1))
      done
    done
  fi

  # Step 5, into the profile: the same name with the same bytes is already
  # there; other bytes move under the first free suffix.
  : > "$TMP/pmoves"; : > "$TMP/claimed"; PN=0 PM=0 PS=0
  LC_ALL=C sort "$TMP/taken" > "$TMP/taken.sorted"
  while IFS="$TAB" read -r nm src; do
    stem="${nm%.md}"; i=1
    while :; do
      if [ "$i" = 1 ]; then cand="$nm"; else cand="$stem-$i.md"; fi
      if [ -e "$PDIR/learnings/$cand" ]; then other="$PDIR/learnings/$cand"; else other="$(lookup "$TMP/claimed" "$cand")"; fi
      if [ -z "$other" ]; then
        printf '%s\t%s\n' "$cand" "$src" >> "$TMP/claimed"; printf '%s\t%s\n' "$nm" "$cand" >> "$TMP/pmoves"
        if [ "$i" = 1 ]; then PN=$((PN + 1)); else PS=$((PS + 1)); fi
        break
      elif cmp -s "$src" "$other"; then
        printf '%s\t\n' "$nm" >> "$TMP/pmoves"; PM=$((PM + 1)); break
      fi
      i=$((i + 1))
    done
  done < "$TMP/taken.sorted"

  if [ -e "$PDIR/review-exceptions.md" ] && [ ! -f "$PDIR/review-exceptions.md" ]; then
    prof_reason="profile not writable"; return
  fi
  pidle=0
  [ -n "$PIDX" ] || [ -s "$TMP/taken" ] || [ "$PEXC" = 1 ] || pidle=1
}
prof_line_now() {
  if [ -n "$prof_reason" ]; then
    prof_line="operative: per-copy $OPS ($prof_reason)"
  elif [ "$pidle" = 1 ]; then
    prof_line="operative: $PSHOW (key $KEY): in place"
  else
    prof_line="operative: $PSHOW (key $KEY): moved $PN entries, $PM already there, $PS renamed, $PL lifted from LEARNINGS.md"
  fi
}
[ -n "$prof_reason" ] || profile_plan pending
prof_line_now

# --- 3. the project part, planned --------------------------------------------
tracked=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -z "$(git ls-files -- "$DIR" 2>/dev/null | head -1)" ] || tracked=1
fi
legacy_project=0; has_project "$LEGACY" && legacy_project=1
action=none note_line="" SRC=""

# plan_import: the authored lines of the private copy, what the inbox already
# holds, and what this run writes. Fills $TMP/new (n, rel, line, mark per
# entry to write); sets K, the number of entries this run writes. No index
# row is written: the index is printed from the entry files
# (knowledge.learningsIndex).
plan_import() {
  local f rel d n line rule mark hit
  # Authored lines: they end in "— source: user" or carry
  # "— source: learnings ", compared without a trailing CR.
  find "$LEGACY" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort > "$TMP/lfiles"
  : > "$TMP/cand"
  while IFS= read -r f; do
    rel="${f#"$LEGACY"/}"
    case "$rel" in LEARNINGS.md|CAPABILITIES.md|learnings/*) continue ;; esac
    LC_ALL=C awk -v rel="$rel" '
      BEGIN { u = "— source: user"; l = "— source: learnings " }
      { sub(/\r$/, "")
        if ((length($0) >= length(u) && substr($0, length($0) - length(u) + 1) == u) || index($0, l)) print rel "\t" $0 }' "$f" >> "$TMP/cand"
  done < "$TMP/lfiles"
  # Every line of every file of the committed copy, without a trailing CR.
  : > "$TMP/committed"
  [ ! -d "$DIR" ] || find "$DIR" -type f -exec awk '{ sub(/\r$/, ""); print }' {} + > "$TMP/committed" 2>/dev/null
  # The values of the committed rule files (tools/extract-rules.sh wrote
  # them from such lines): a line whose text is one of them is held too.
  : > "$TMP/rulevals"
  if [ -d "$DIR/$RULESD" ]; then
    for f in "$DIR/$RULESD"/*.md; do
      [ -f "$f" ] || continue
      LC_ALL=C awk '{ sub(/\r$/, "") } sub(/^- (Rule|Check|Zone|Exception):[ \t]*/, "") { sub(/[ \t]+$/, ""); print }' "$f" >> "$TMP/rulevals"
    done
  fi
  LC_ALL=C awk '
    BEGIN { u = "— source: user"; l = "— source: learnings " }
    function textof(s,   i) {
      if (length(s) >= length(u) && substr(s, length(s) - length(u) + 1) == u) s = substr(s, 1, length(s) - length(u))
      else { i = index(s, l); if (i) s = substr(s, 1, i - 1) }
      sub(/[ \t]+$/, "", s); sub(/^[ \t]*([-*+]|[0-9]+\.)[ \t]+/, "", s); sub(/^[ \t]+/, "", s)
      return s
    }
    FILENAME == ARGV[1] { c[$0] = 1; next }
    FILENAME == ARGV[2] { v[$0] = 1; next }
    { t = index($0, "\t"); line = substr($0, t + 1)
      if (!(line in c) && !(textof(line) in v) && !(line in seen)) { seen[line] = 1; print } }' "$TMP/committed" "$TMP/rulevals" "$TMP/cand" > "$TMP/kept"

  # The inbox as it will be after the operative move and the profile step
  # (the profile's entries included): its marks (resolved ones count as
  # present) with the entry file holding each, and an older index file when
  # one is still there, read only for the numbering below.
  : > "$TMP/marks"
  for d in "$OPS/learnings" "$LEGACY/learnings" ${PDIR:+"$PDIR/learnings"}; do
    [ -d "$d" ] || continue
    for f in "$d"/*.md; do
      [ -f "$f" ] || continue
      LC_ALL=C awk -v b="${f##*/}" '
        { sub(/\r$/, ""); sub(/^[ \t]*- /, ""); sub(/^\[PROMOTE RESOLVED [0-9-]*\] /, "[PROMOTE] ") }
        /^\[PROMOTE\] / { print $0 "\t" b }' "$f" >> "$TMP/marks"
    done
  done
  IDXSRC=""
  if [ -f "$OPS/LEARNINGS.md" ]; then IDXSRC="$OPS/LEARNINGS.md"; elif [ -f "$LEGACY/LEARNINGS.md" ]; then IDXSRC="$LEGACY/LEARNINGS.md"; fi
  : > "$TMP/index"; [ -z "$IDXSRC" ] || tr -d '\r' < "$IDXSRC" > "$TMP/index"
  # Numbering continues after the highest Migrated rule already present.
  n="$({
    for d in "$OPS/learnings" "$LEGACY/learnings" ${PDIR:+"$PDIR/learnings"}; do
      [ -d "$d" ] && find "$d" -mindepth 1 -maxdepth 1 -name '*-migrated-rule-*' | sed -n 's/.*-migrated-rule-\([0-9][0-9]*\)[^/]*$/\1/p'
    done
    sed -n 's/^|[^|]*| *Migrated rule \([0-9][0-9]*\) *|.*/\1/p' "$TMP/index"
    echo 0
  } | sort -n | tail -1)"

  : > "$TMP/new"
  while IFS= read -r kept; do
    rel="${kept%%"$TAB"*}"; line="${kept#*"$TAB"}"
    rule="$(printf '%s\n' "$line" | LC_ALL=C awk '
      BEGIN { u = "— source: user"; l = "— source: learnings " }
      { s = $0
        if (length(s) >= length(u) && substr(s, length(s) - length(u) + 1) == u) s = substr(s, 1, length(s) - length(u))
        else { i = index(s, l); if (i) s = substr(s, 1, i - 1) }
        sub(/[ \t]+$/, "", s); sub(/^[ \t]*([-*+]|[0-9]+\.)[ \t]+/, "", s); sub(/^[ \t]+/, "", s)
        print s }')"
    mark="[PROMOTE] $rel — $rule"
    hit="$(MK="$mark" LC_ALL=C awk -F'\t' 'BEGIN { m = ENVIRON["MK"] } $1 == m { print $2; exit }' "$TMP/marks")"
    # Already in the inbox: an earlier run, or an interrupted one, wrote it.
    [ -z "$hit" ] || continue
    n=$((n + 1))
    printf '%s\t%s\t%s\t%s\n' "$n" "$rel" "$line" "$mark" >> "$TMP/new"
    printf '%s\t%s-migrated-rule-%s.md\n' "$mark" "$TODAY" "$n" >> "$TMP/marks"
  done < "$TMP/kept"
  K="$(wc -l < "$TMP/new" | tr -d ' ')"
}

case "$mode" in
first)
  if [ -e "$DIR" ]; then
    if [ "$tracked" = 1 ]; then
      echo "migrate-knowledge: refused — $DIR/ is already committed; run without --first-commit." >&2
    else
      echo "migrate-knowledge: refused — $DIR/ already exists, so the move is done: run /generate-knowledge, then commit $DIR/ alone." >&2
    fi
    exit 1
  fi
  : > "$TMP/cands"
  # An empty staging directory without a record holds nothing to resume: the
  # move starts afresh.
  if [ -d "$STAGE" ] && { [ -f "$SRCREC" ] || [ -n "$(ls -A "$STAGE" 2>/dev/null)" ]; }; then
    # Resume: a directory still holding any project entry, topic directories
    # included, is unfinished; the source the interrupted run recorded wins,
    # and without a record only --from names it, never a guess.
    recorded=""; [ ! -f "$SRCREC" ] || recorded="$(head -n 1 "$SRCREC" | tr -d '\r')"
    if [ -n "$recorded" ] && ! known_dir "$recorded"; then
      echo "migrate-knowledge: $SRCREC names '$recorded', which is no knowledge directory; check $STAGE/ by hand" >&2; exit 2
    fi
    [ -z "$(project_entries "$LEGACY")" ] || echo "$LEGACY" >> "$TMP/cands"
    while IFS= read -r o; do
      o="${o%/}"; [ -n "$o" ] && [ "$o" != "$LEGACY" ] || continue
      [ -z "$(project_entries "$o")" ] || echo "$o" >> "$TMP/cands"
    done <<EOF
$OTHERS
EOF
    if [ "$fromset" = 1 ]; then
      if [ -n "$recorded" ] && [ "$recorded" != "$from" ]; then
        echo "migrate-knowledge: refused — the interrupted first commit was moving from $recorded, not $from; run --first-commit --from $recorded." >&2; exit 1
      fi
      known_dir "$from" || { echo "migrate-knowledge: refused — --from $from is no knowledge directory." >&2; exit 1; }
      SRC="$from"
    elif [ -n "$recorded" ]; then
      SRC="$recorded"
    else
      echo "migrate-knowledge: refused — an interrupted first commit left $STAGE/ without a record of the directory it was moving from; name that directory with --first-commit --from <dir>. Directories still holding project files:" >&2
      if [ -s "$TMP/cands" ]; then sed 's/^/  /' "$TMP/cands" >&2; else echo "  none" >&2; fi
      exit 1
    fi
    : > "$TMP/pentries"; : > "$TMP/conflicts"
    if [ -n "$SRC" ]; then
      project_entries "$SRC" > "$TMP/pentries"
      while IFS= read -r e; do
        [ ! -e "$STAGE/${e##*/}" ] || echo "  ${e##*/}" >> "$TMP/conflicts"
      done < "$TMP/pentries"
    fi
    if [ -s "$TMP/conflicts" ]; then
      echo "migrate-knowledge: refused — these names exist in both $SRC/ and $STAGE/. Keep one of each by hand, then run --first-commit again; nothing was moved:" >&2
      cat "$TMP/conflicts" >&2; exit 1
    fi
    action=stage
  else
    [ "$legacy_project" = 0 ] || echo "$LEGACY" >> "$TMP/cands"
    while IFS= read -r o; do
      o="${o%/}"; [ -n "$o" ] && [ "$o" != "$LEGACY" ] || continue
      ! has_project "$o" || echo "$o" >> "$TMP/cands"
    done <<EOF
$OTHERS
EOF
    ncands="$(wc -l < "$TMP/cands" | tr -d ' ')"
    if [ "$ncands" = 0 ]; then
      echo "migrate-knowledge: refused — no directory holds project files to make the first knowledge commit from; run /generate-knowledge instead." >&2
      exit 1
    fi
    if [ "$fromset" = 1 ]; then
      grep -qxF -- "$from" "$TMP/cands" || {
        echo "migrate-knowledge: refused — --from $from is not a directory holding project files. Candidates:" >&2
        sed 's/^/  /' "$TMP/cands" >&2; exit 1; }
      SRC="$from"
    elif [ "$ncands" -gt 1 ]; then
      echo "migrate-knowledge: refused — more than one directory holds project files; choose one with --from <dir>:" >&2
      sed 's/^/  /' "$TMP/cands" >&2
      exit 1
    else
      SRC="$(head -n 1 "$TMP/cands")"
    fi
    if [ "$SRC" = "$LEGACY" ]; then action=rename; else project_entries "$SRC" > "$TMP/pentries"; action=stage; fi
  fi
  proj_line="$COMMIT_LINE"
  # Another edition's directory keeps its operative files for its own migration.
  if [ "$action" = stage ] && [ -n "$SRC" ] && [ "$SRC" != "$LEGACY" ]; then
    for nm in LEARNINGS.md learnings CAPABILITIES.md; do
      [ ! -e "$SRC/$nm" ] || { note_line="note: $SRC/ keeps its operative files for that edition's own migration"; break; }
    done
  fi
  ;;
drop)
  if [ "$tracked" = 0 ]; then
    echo "migrate-knowledge: refused — nothing under $DIR/ is tracked in this branch, so the private copy in $LEGACY/ is the only knowledge here; nothing was removed." >&2
    exit 1
  fi
  if [ -d "$LEGACY" ] && [ -n "$(project_entries "$LEGACY")" ]; then
    plan_import
    BK="$OPS/legacy-knowledge-$(date +%Y-%m-%d-%H%M)"
    [ ! -e "$BK" ] || BK="$BK-$$"
    proj_line="project: private copy removed (backup $BK; $K authored lines kept as inbox entries)"
    action=drop
  else
    proj_line="project: in place ($DIR)"
  fi
  ;;
default)
  if [ "$tracked" = 1 ]; then
    if [ "$legacy_project" = 1 ] && [ ! -f "$STAMP" ]; then
      plan_import
      proj_line="project: in place ($DIR); private copy kept for branches without knowledge ($K authored lines kept as inbox entries)"
      action=import
    else
      proj_line="project: in place ($DIR)"
    fi
    # The committed copy is what counts now; a staging directory beside it is
    # an interrupted move from before it was committed.
    [ ! -d "$STAGE" ] || proj_line="$proj_line; an interrupted move left $STAGE/: $DIR/ is committed, so remove it once nothing in it is missing from $DIR/"
  elif [ -e "$DIR" ]; then
    proj_line="$COMMIT_LINE"
  elif [ -d "$STAGE" ]; then
    proj_line="project: waiting for $DIR in the repository; an interrupted --first-commit left $STAGE/: run --first-commit again to finish the move"
  elif [ "$legacy_project" = 1 ]; then
    proj_line="project: waiting for $DIR in the repository; the first knowledge commit is made with --first-commit"
  else
    proj_line="project: nothing to move"
  fi
  ;;
esac

# The rule extractor on knowledge.dir once the move is done (a first commit).
EXTRACT="$TEAM_ROOT/tools/extract-rules.sh"
extract_rules() {
  local out
  if ! out="$(bash "$EXTRACT" "$DIR" 2> "$TMP/xerr")"; then
    cat "$TMP/xerr" >&2
    echo "migrate-knowledge: the project files are in $DIR/, but their authored lines were not moved into $DIR/$RULESD/; fix that, then run bash <team-root>/tools/extract-rules.sh $DIR" >&2
    exit 2
  fi
  echo "$out"
}

# --- dry run ------------------------------------------------------------------
if [ "$dry" = 1 ]; then
  echo "would: $ops_line"
  echo "would: $prof_line"
  echo "would: $proj_line"
  if [ "$mode" = first ]; then
    # What the extractor would do with the moved files: a copy of them, read
    # where the move would put them.
    PV="$TMP/preview"; mkdir -p "$PV" || exit 2
    [ "$action" != stage ] || [ ! -d "$STAGE" ] || cp -R "$STAGE/." "$PV/" 2>/dev/null
    if [ "$action" = rename ]; then project_entries "$LEGACY"; else cat "$TMP/pentries" 2>/dev/null; fi > "$TMP/pv.entries"
    while IFS= read -r e; do cp -R -- "$e" "$PV/" 2>/dev/null; done < "$TMP/pv.entries"
    if xout="$(bash "$EXTRACT" --dry-run "$PV" 2>/dev/null)"; then
      case "$xout" in *" into $PV/$RULESD") xout="${xout%" into $PV/$RULESD"} into $DIR/$RULESD" ;; esac
      echo "$xout"
    else
      echo "would: rules: could not tell what the extractor would move"
    fi
  fi
  [ -z "$note_line" ] || echo "would: $note_line"
  exit 0
fi

# --- 4. act ---------------------------------------------------------------------
while IFS="$TAB" read -r src dst; do
  mkdir -p "$(dirname "$dst")" && mv -- "$src" "$dst" \
    || { echo "migrate-knowledge: could not move $src to $dst (read-only or open elsewhere?); fix that and run again" >&2; exit 2; }
done < "$TMP/moves"
[ ! -d "$LEGACY/learnings" ] || rmdir "$LEGACY/learnings" 2>/dev/null
[ "$action" = rename ] || [ ! -d "$LEGACY" ] || rmdir "$LEGACY" 2>/dev/null
# A source record left inside the committed directory by a run stopped right
# after its final rename belongs to this script, never to the knowledge.
[ ! -f "$DIR/${SRCREC##*/}" ] || rm -f -- "$DIR/${SRCREC##*/}"
echo "$ops_line"

# --- 4b. the profile ------------------------------------------------------------
# INBOX: where the inbox is once this step is done, and where the import
# below writes.
INBOX="$OPS"
werr() { echo "migrate-knowledge: could not $1 (read-only or open elsewhere?); fix that and run again" >&2; exit 2; }
profile_act() {
  local p np probe nm dst f IB DI
  # The probe; on failure the directories this step created go again, deepest first.
  : > "$TMP/created"; p="$PDIR/learnings"
  while [ ! -e "$p" ] && [ ! -L "$p" ]; do
    printf '%s\n' "$p" >> "$TMP/created"
    np="$(dirname "$p")"; [ "$np" != "$p" ] || break; p="$np"
  done
  probe="$PDIR/learnings/.write-probe-$$"
  if ! { mkdir -p "$PDIR/learnings" && : > "$probe" && rm -f -- "$probe" && [ ! -e "$probe" ]; } 2>/dev/null; then
    rm -f -- "$probe" 2>/dev/null
    while IFS= read -r p; do rmdir -- "$p" 2>/dev/null; done < "$TMP/created"
    prof_reason="profile not writable"; prof_line_now; return
  fi
  profile_plan now
  prof_line_now
  [ -z "$prof_reason" ] || return
  INBOX="$PDIR"
  [ "$pidle" = 0 ] || return

  # Step 3, the backup.
  IB="$OPS/inbox-backup-$NOW"; [ ! -e "$IB" ] || IB="$IB-$$"
  mkdir -p "$IB" || werr "create $IB/"
  for nm in LEARNINGS.md learnings review-exceptions.md; do
    [ -e "$OPS/$nm" ] || continue
    { cp -Rp "$OPS/$nm" "$IB/$nm" && diff -r "$OPS/$nm" "$IB/$nm" >/dev/null 2>&1; } || werr "back up $OPS/$nm to $IB/; nothing was moved"
  done
  # Step 4, the lift, then the index file goes.
  while IFS="$TAB" read -r f nm; do
    { mkdir -p "$OPS/learnings" && cp -- "$f" "$OPS/learnings/$nm"; } || werr "write $OPS/learnings/$nm"
  done < "$TMP/lifts"
  if [ -n "$PIDX" ]; then
    DI="$OPS/dropped-index-$NOW.md"; [ ! -e "$DI" ] || DI="$OPS/dropped-index-$NOW-$$.md"
    mv -- "$OPS/LEARNINGS.md" "$DI" || werr "move $OPS/LEARNINGS.md to $DI"
  fi
  # Step 5, the entry files.
  while IFS="$TAB" read -r nm dst; do
    if [ -n "$dst" ]; then
      mv -- "$OPS/learnings/$nm" "$PDIR/learnings/$dst" || werr "move $OPS/learnings/$nm to $PSHOW/learnings/$dst"
    else
      rm -f -- "$OPS/learnings/$nm" || werr "remove $OPS/learnings/$nm (the profile holds the same bytes)"
    fi
  done < "$TMP/pmoves"
  [ ! -d "$OPS/learnings" ] || rmdir "$OPS/learnings" 2>/dev/null
  # Step 6, review-exceptions.md.
  if [ "$PEXC" = 1 ]; then
    f="$PDIR/review-exceptions.md"
    if [ ! -e "$f" ]; then
      mv -- "$OPS/review-exceptions.md" "$f" || werr "move $OPS/review-exceptions.md to $PSHOW/"
    else
      LC_ALL=C awk -v BINMODE=3 '
        FILENAME == ARGV[1] { k = $0; sub(/\r$/, "", k); h[k] = 1; next }
        { k = $0; sub(/\r$/, "", k); if (!(k in h)) { h[k] = 1; print } }' "$f" "$OPS/review-exceptions.md" > "$TMP/exc.add" \
        || werr "read $OPS/review-exceptions.md"
      if [ -s "$TMP/exc.add" ]; then
        if [ -s "$f" ] && [ "$(tail -c 1 "$f" | wc -l | tr -d ' ')" = 0 ]; then printf '\n' >> "$f" || werr "append to $PSHOW/review-exceptions.md"; fi
        cat "$TMP/exc.add" >> "$f" || werr "append to $PSHOW/review-exceptions.md"
      fi
      rm -f -- "$OPS/review-exceptions.md" || werr "remove $OPS/review-exceptions.md"
    fi
  fi
}
if [ -z "$prof_reason" ]; then profile_act; fi
echo "$prof_line"

# write_import: the planned entries, one file each into the inbox; no index row.
write_import() {
  local n rel line mark entry
  while IFS="$TAB" read -r n rel line mark; do
    mkdir -p "$INBOX/learnings" || exit 2
    entry="$INBOX/learnings/$TODAY-migrated-rule-$n.md"
    {
      printf '## [%s] Migrated rule %s\n' "$TODAY" "$n"
      # No edition path: submitted as a remark, this text is committed knowledge.
      printf -- "- **Symptom:** the private copy's %s holds an authored line the committed copy (%s/) lacks: %s\n" "$rel" "$DIR" "$line"
      printf -- '- **Root cause:** written into the private copy before the project knowledge moved to the committed directory.\n'
      printf -- '- **Fix pattern:** the knowledge refresh makes it a rule file in %s/%s/, or drops it when the committed knowledge already says it.\n' "$DIR" "$RULESD"
      printf -- '- **Files touched:** %s/%s\n' "$DIR" "$rel"
      printf -- '- **Tags:** migration\n'
      printf '%s\n' "$mark"
    } > "$entry" || { echo "migrate-knowledge: could not write $entry" >&2; exit 2; }
  done < "$TMP/new"
}

case "$action" in
rename)
  # One rename: the knowledge directory appears whole or not at all. An empty
  # staging directory without a record is what an earlier start left; it goes.
  [ ! -d "$STAGE" ] || rmdir "$STAGE" 2>/dev/null
  { mkdir -p "$(dirname "$DIR")" && mv -- "$LEGACY" "$DIR"; } \
    || { echo "migrate-knowledge: could not move $LEGACY/ to $DIR/ (a file open elsewhere?); nothing of it was moved; fix that and run again" >&2; exit 2; }
  echo "$proj_line"
  extract_rules
  ;;
stage)
  mkdir -p "$STAGE" || { echo "migrate-knowledge: could not create $STAGE/" >&2; exit 2; }
  if [ -n "$SRC" ] && [ ! -f "$SRCREC" ]; then
    printf '%s\n' "$SRC" > "$SRCREC" || { echo "migrate-knowledge: could not write $SRCREC" >&2; exit 2; }
  fi
  while IFS= read -r e; do
    mv -- "$e" "$STAGE/${e##*/}" \
      || { echo "migrate-knowledge: could not move $e (read-only or open elsewhere?); fix that and run --first-commit again to finish" >&2; exit 2; }
  done < "$TMP/pentries"
  # The record goes with the staging directory and is removed only once the
  # rename succeeded, so a failed rename resumes from the same source.
  mv -- "$STAGE" "$DIR" || { echo "migrate-knowledge: could not rename $STAGE/ to $DIR/; fix that and run --first-commit again to finish" >&2; exit 2; }
  rm -f -- "$DIR/${SRCREC##*/}"
  [ -z "$SRC" ] || rmdir "$SRC" 2>/dev/null
  echo "$proj_line"
  extract_rules
  [ -z "$note_line" ] || echo "$note_line"
  ;;
drop)
  write_import
  { mkdir -p "$BK" && cp -Rp "$LEGACY/." "$BK/" && diff -r "$LEGACY" "$BK" >/dev/null 2>&1; } \
    || { echo "migrate-knowledge: could not back up $LEGACY/ to $BK/; nothing was removed" >&2; exit 2; }
  rm -rf -- "$LEGACY" || { echo "migrate-knowledge: could not remove $LEGACY/ (the backup is $BK/); fix that and run again" >&2; exit 2; }
  echo "$proj_line"
  ;;
import)
  write_import
  mkdir -p "$CAPS" && printf 'date=%s\nlines=%s\n' "$TODAY" "$K" > "$STAMP" \
    || { echo "migrate-knowledge: could not write $STAMP" >&2; exit 2; }
  echo "$proj_line"
  ;;
*)
  echo "$proj_line"
  ;;
esac
exit 0
