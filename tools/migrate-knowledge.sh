#!/usr/bin/env bash
# Dream Team — moves a project's knowledge out of this edition's own directory
# (knowledge.legacyDir). The operative files (LEARNINGS.md, learnings/,
# CAPABILITIES.md) go to knowledge.operativeDir and knowledge.capabilitiesDir;
# the old learnings inbox goes into the remarks dir; the project files go to
# knowledge.dir, the committed directory every edition reads. See
# team-manifest.json → knowledge.
#
#   bash <team-root>/tools/migrate-knowledge.sh [--dry-run] [--first-commit [--from <dir>] | --drop-legacy]
#                                                           (from the project root)
#
# The remarks dir is what `tools/knowledge-dir.sh remarks` prints:
# <knowledge.dir>/<knowledge.proposalsDir> once the resolver's project is
# knowledge.dir, else <knowledge.operativeDir>/<knowledge.proposalsDir>.
# Every copy into it is `tools/remarks.sh accept`: a source <name>.md becomes
# <name>-<hash6>.md (kept as it is when it already ends in its own hash6), a
# file of that name with the same bytes is "already there", nothing is ever
# overwritten, staged or committed. Before each copy the resolver must print
# the directory this script planned for it, or the run stops (exit 2).
#
# Every mode moves the operative files first. Then the inbox step (for
# --first-commit only after the project files moved, so that its remarks dir
# is <knowledge.dir>/<knowledge.proposalsDir>):
#   - sources: operativeDir/learnings/*.md, operativeDir/review-exceptions.md
#     and an older operativeDir/LEARNINGS.md.
#   - LEARNINGS.md, learnings/ and review-exceptions.md are backed up first to
#     operativeDir/inbox-backup-<YYYY-MM-DD-HHmm>/.
#   - The inline entries of an older LEARNINGS.md (each "## [date] title"
#     body, cut as checks/verify-knowledge-integrity.sh cuts it) become entry
#     files in learnings/, byte for byte, named <date>-<slug>.md by the rules
#     of templates/learnings-entry.md ("entry" for an empty slug; -2, -3
#     when taken); LEARNINGS.md then moves to
#     operativeDir/dropped-index-<YYYY-MM-DD-HHmm>.md. An unclosed fence or an
#     inline heading without a date refuses the run (exit 1).
#   - Each line of review-exceptions.md after its first line becomes an entry
#     file in learnings/ of two lines, "## [<the date after "accepted ">]
#     exception <path>" (<path>: the line after its leading "- ", up to the
#     first " · "; today when the line names no date) and "[EXCEPTION] <the
#     line without its leading "- ">", named <date>-exception-<slug of
#     path>.md (-2, -3 when taken); review-exceptions.md is then removed.
#   - Every learnings/*.md is accepted into the remarks dir, and each source
#     is removed once it is there.
#   - CAPABILITIES.md, the import stamp, the backups and the
#     legacy-knowledge-* directories stay in operativeDir.
# The copy: every *.md of operativeDir/<knowledge.proposalsDir> (the remarks
# accepted while the knowledge was the private copy) is accepted into
# <knowledge.dir>/<knowledge.proposalsDir> and stays where it is; a stamp,
# operativeDir/.remarks-copied, records that it was done and, one
# "remark=<name>" line each, which names it carried (the names of earlier
# stamps kept), so that --drop-legacy does not bring back a remark the
# refresh consumed since. A stamp without such lines (written before they
# were recorded) names nothing, and --drop-legacy then copies every remark
# as before: a consumed one may come back as an untracked file, which the
# note names, while skipping on a guess could lose a remark never copied.
# Then, for the project files:
#   default         the committed copy is tracked in this branch: authored
#                   lines of the private copy that the committed copy lacks
#                   become entry files accepted into the remarks dir, once per
#                   edition (a stamp in capabilitiesDir records it), and the
#                   private copy stays for branches without knowledge. When
#                   the resolver's project is knowledge.dir and the copy
#                   stamp is absent, the copy runs. Nothing tracked: the
#                   report says what the first commit still needs (a
#                   knowledge.dir holding only <knowledge.proposalsDir>/
#                   counts as absent).
#   --first-commit  the project files move into knowledge.dir, which must not
#                   exist yet or hold nothing but <knowledge.proposalsDir>/
#                   (the remarks dir the resolver can print before any
#                   knowledge is there; its entries go into the directory
#                   that becomes knowledge.dir before the rename, a name
#                   there with the same bytes dropped, with other bytes
#                   refused). This edition's directory moves with one rename;
#                   another edition's (--from picks it when both hold project
#                   files) is staged entry by entry in knowledge.dir.migrating,
#                   which is renamed at the end, so an interrupted run resumes
#                   and knowledge.dir only ever appears complete. Then
#                   tools/extract-rules.sh moves the authored lines of the
#                   moved files into knowledge.dir/<knowledge.rulesDir>/ and its line is
#                   printed. Then the inbox step and the copy.
#   --drop-legacy   the committed copy is tracked and the resolver's project
#                   is knowledge.dir: authored lines the remarks dir does not
#                   hold yet become remarks, the copy runs (a remark the
#                   copy stamp names is skipped: it was carried before),
#                   then the private copy is backed up to
#                   operativeDir/legacy-knowledge-<YYYY-MM-DD-HHmm>/ and
#                   operativeDir/<knowledge.proposalsDir> to that name with
#                   -proposals appended, each backup checked, and both are
#                   removed.
#   --dry-run       prints what a run would do, each line prefixed "would:";
#                   writes nothing.
#
# Report lines, in this order: "operative: ..."; "remarks: <remarks dir>: <N>
# moved, <M> already there", or "remarks: <remarks dir>: nothing to move" when
# there is no inbox (for --first-commit after the project lines); "project:
# ..." and the extractor's "rules: ..." line; "remarks: <knowledge.dir>/
# <knowledge.proposalsDir>: <C> copied from <operativeDir>/
# <knowledge.proposalsDir>, <D> already there" when the copy runs (with
# ", <S> copied before" when --drop-legacy skipped S remarks the copy stamp
# names, and "; <operativeDir>/<knowledge.proposalsDir> removed (backup
# <dir>)" when --drop-legacy removed it); the "note:"
# line about another edition's directory; and, when `git ls-files --
# <knowledge.dir>` prints anything, the remarks dir is
# <knowledge.dir>/<knowledge.proposalsDir> and this run added N > 0 files to
# it, "note: <N> new files under <remarks dir> are untracked: commit them
# with your next change, or delete them".
#
# In the default mode and --drop-legacy, an authored line of the private copy
# is already held, and becomes no remark, when the committed copy holds the
# whole line (CR ignored) or when its text (the line without the list marker,
# the source suffix and the CR) is the value of a "- Rule:", "- Check:",
# "- Zone:" or "- Exception:" line of a file directly inside knowledge.dir/<knowledge.rulesDir>/.
#
# Every refusal is decided before the first write, so a refused run leaves the
# tree as it found it. Moves are byte-exact (mv), copies are checked (cmp); a
# moved file is rewritten only by the extractor after a first commit, which
# removes its authored lines and keeps every other byte.
#
# Exit 0 = done, nothing to do, or a dry run. 1 = refused: a run is open, the
# run state is still in the legacy tracking directory, a name exists on both
# sides, an older LEARNINGS.md cannot be split, or the mode's precondition does
# not hold. 2 = error: bad arguments, the manifest, a symbolic link (an inbox
# entry file included), or a failed write.
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
PROPD="$(value_in knowledge proposalsDir)";      PROPD="${PROPD%/}";   rel_ok knowledge.proposalsDir "$PROPD"
TRK="$(value_in tracking dir)";                  TRK="${TRK%/}";       rel_ok tracking.dir "$TRK"
TRKOLD="$(value_in tracking legacyDir)";         TRKOLD="${TRKOLD%/}"; rel_ok tracking.legacyDir "$TRKOLD"
OTHERS="$(array_in knowledge otherEditionDirs)"

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
# Per edition: each edition's private copy is imported once, by its own migration.
STAMP="$CAPS/.legacy-rules-imported"
# The remarks dir of the private copy and of the committed directory; the
# copy from the first into the second is made once (the stamp records it).
RL="$OPS/$PROPD"
RC="$DIR/$PROPD"
COPIED="$OPS/.remarks-copied"
# An interrupted move from another edition's directory, and the source it records.
STAGE="$DIR.migrating"
SRCREC="$STAGE/.migrate-source"
TODAY="$(date +%Y-%m-%d)"
NOW="$(date +%Y-%m-%d-%H%M)"
TAB="$(printf '\t')"
CR=$'\r'
COMMIT_LINE="project: moved to $DIR: run /generate-knowledge, then commit it alone, one commit and one pull request, no other file"
UNTRACKED_TAIL="are untracked: commit them with your next change, or delete them"

# --- 1. refusals ---------------------------------------------------------
links=""
for p in "$LEGACY" "$LEGACY/learnings" "$LEGACY/LEARNINGS.md" "$DIR" "$STAGE" "$OPS" "$OPS/learnings" "$OPS/LEARNINGS.md" "$OPS/review-exceptions.md" "$CAPS" "$RL" "$RC" ${from:+"$from"}; do
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
for p in "$LEGACY" "$DIR" "$STAGE" "$OPS" "$CAPS" "$RL" "$RC"; do
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
# knowledge.dir exists and holds anything but <proposalsDir>/: the remarks
# dir alone, which the resolver can print before any knowledge is there, is
# no knowledge directory yet.
dir_present() {
  [ -e "$DIR" ] || return 1
  [ -n "$(find "$DIR" -mindepth 1 -maxdepth 1 ! -name "$PROPD" 2>/dev/null | head -1)" ]
}
# What tools/knowledge-dir.sh prints for project or remarks, now.
resolve() {
  local r=""
  IFS= read -r r < <(bash "$TEAM_ROOT/tools/knowledge-dir.sh" "$1" 2>/dev/null | tr -d '\r')
  printf '%s' "${r%/}"
}
werr() { echo "migrate-knowledge: could not $1 (read-only or open elsewhere?); fix that and run again" >&2; exit 2; }

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

# --- 2b. the inbox, planned ------------------------------------------------------
# RD, the remarks dir the inbox moves into: the resolver's now (the operative
# move above changes nothing it reads), or, for a first commit, the committed
# directory's, because there the inbox moves after the project files.
if [ "$mode" = first ]; then
  RD="$RC"
else
  RD="$(resolve remarks)"
  [ -n "$RD" ] || { echo "migrate-knowledge: the remarks dir could not be resolved (tools/knowledge-dir.sh remarks)" >&2; exit 2; }
fi

slug() { # the slug of an entry title (templates/learnings-entry.md)
  printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//' | cut -c1-60 | sed 's/-$//'
}
lookup() { # <file> <name>: the path recorded for <name> in a name<TAB>path file
  LC_ALL=C awk -F'\t' -v n="$2" '$1 == n { print $2; exit }' "$1"
}
# remark_name <file> <base name>: the name tools/remarks.sh gives <file> in
# the remarks dir: -<hash6> before .md, hash6 the first six characters of
# `git hash-object` of its bytes, unless the name already ends in it.
remark_name() {
  local stem="${2%.md}" h=""
  IFS= read -r h < <(git hash-object --no-filters -- "$1" 2>/dev/null | tr -d '\r')
  [ -n "$h" ] || { echo "migrate-knowledge: could not hash $1" >&2; return 1; }
  h="${h:0:6}"
  case "$stem" in *"-$h") printf '%s\n' "$2" ;; *) printf '%s-%s.md\n' "$stem" "$h" ;; esac
}
# claim <file> <stem>: the first of <stem>.md, <stem>-2.md ... that no entry
# file of the inbox ($TMP/taken) holds, recorded and printed; nothing when one
# of them already holds the same bytes (an earlier, interrupted run wrote it).
claim() {
  local i=1 cand other
  while :; do
    if [ "$i" = 1 ]; then cand="$2.md"; else cand="$2-$i.md"; fi
    other="$(lookup "$TMP/taken" "$cand")"
    if [ -z "$other" ]; then
      printf '%s\t%s\n' "$cand" "$1" >> "$TMP/taken"; printf '%s\n' "$cand"; return 0
    fi
    ! cmp -s "$1" "$other" || return 0
    i=$((i + 1))
  done
}
# plan_accept <list> <dir>: for each name<TAB>file of <list>, what
# tools/remarks.sh accept would do in <dir>. Sets PA, the files it adds, and
# PT, those already there; a name in <dir> with other bytes is a conflict
# ($TMP/rconf). $TMP/rnames holds what this run adds, so a second source with
# the same bytes counts as already there.
: > "$TMP/rnames"; : > "$TMP/rconf"
plan_accept() {
  local b p nm
  PA=0 PT=0
  while IFS="$TAB" read -r b p; do
    [ -n "$b" ] || continue
    nm="$(remark_name "$p" "$b")" || exit 2
    if [ -e "$2/$nm" ] || [ -L "$2/$nm" ]; then
      if [ -f "$2/$nm" ] && cmp -s -- "$p" "$2/$nm"; then PT=$((PT + 1)); else echo "  $2/$nm (from $b)" >> "$TMP/rconf"; fi
    elif grep -qxF -- "$2/$nm" "$TMP/rnames"; then
      PT=$((PT + 1))
    else
      printf '%s\n' "$2/$nm" >> "$TMP/rnames"; PA=$((PA + 1))
    fi
  done < "$1"
}

# inbox_plan: the inbox as the operative part above leaves it. Fills
# $TMP/taken (name, where its bytes are now: every entry file the step
# accepts), $TMP/lifts and $TMP/excs (the file to write, its name in
# learnings/); sets PEXC, IN, IM and iidle, or inbox_reason when the inbox
# cannot be read.
inbox_plan() {
  local f src dst h d p s edate etitle eslug nm nonl pidx
  inbox_reason=""
  : > "$TMP/taken"; : > "$TMP/elinks"
  if [ -d "$OPS/learnings" ]; then
    for f in "$OPS/learnings"/*.md; do
      if [ -L "$f" ]; then echo "  $f" >> "$TMP/elinks"; continue; fi
      [ ! -f "$f" ] || printf '%s\t%s\n' "${f##*/}" "$f" >> "$TMP/taken"
    done
  fi
  pidx=""; [ ! -f "$OPS/LEARNINGS.md" ] || pidx="$OPS/LEARNINGS.md"
  while IFS="$TAB" read -r src dst; do
    case "$dst" in
      "$OPS/LEARNINGS.md") pidx="$src" ;;
      "$OPS/learnings/"*.md)
        if [ -L "$src" ]; then echo "  $src" >> "$TMP/elinks"; continue; fi
        [ ! -f "$src" ] || printf '%s\t%s\n' "${dst##*/}" "$src" >> "$TMP/taken" ;;
    esac
  done < "$TMP/moves"
  # tools/remarks.sh refuses a symbolic link; refused here, before any write.
  if [ -s "$TMP/elinks" ]; then
    echo "migrate-knowledge: these inbox entries are symbolic links; refusing to touch anything. Replace each with the file it points to and run again:" >&2
    cat "$TMP/elinks" >&2
    exit 2
  fi
  PEXC=0; [ ! -f "$OPS/review-exceptions.md" ] || PEXC=1

  # The lift: split_entries of checks/verify-knowledge-integrity.sh, writing
  # every line as read, so CRs and a missing last newline survive
  # (BINMODE=3: gawk on Windows otherwise drops the CR of a CRLF line).
  : > "$TMP/lifts"
  rm -rf "$TMP/split"; mkdir -p "$TMP/split"
  if [ -n "$pidx" ]; then
    nonl=0; [ ! -s "$pidx" ] || [ "$(tail -c 1 "$pidx" | wc -l | tr -d ' ')" != 0 ] || nonl=1
    LC_ALL=C awk -v BINMODE=3 -v out="$TMP/split" -v nonl="$nonl" '
      { if (have) printf "%s\n", pl > pf; have = 0 }
      /^```/                 { fence = !fence }
      !fence && /^## \[/     { if (f != "") close(f); n++; f = sprintf("%s/entry-%04d", out, n) }
      n > 0                  { pl = $0; pf = f; have = 1 }
      END                    { if (have) printf "%s%s", pl, (nonl ? "" : "\n") > pf; if (fence) exit 2 }
    ' "$pidx"
    case $? in
      0) ;;
      2) inbox_reason="LEARNINGS.md ends inside a fenced block; balance its fences and run again"; return ;;
      *) echo "migrate-knowledge: could not read $pidx" >&2; exit 2 ;;
    esac
    for f in "$TMP/split"/entry-*; do
      [ -f "$f" ] || continue
      h=""; IFS= read -r h < "$f"; h="${h%"$CR"}"
      d="${h#"## ["}"; edate="${d%%"]"*}"; etitle="${d#*"]"}"; etitle="${etitle# }"
      case "$edate" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
        *) inbox_reason="an inline entry of LEARNINGS.md has no date in its heading ($h); fix the heading and run again"; return ;;
      esac
      # A title with no ASCII letter or digit: "entry", as extract-rules.sh says "rule".
      eslug="$(slug "$etitle")"; [ -n "$eslug" ] || eslug=entry
      nm="$(claim "$f" "$edate-$eslug")"
      [ -z "$nm" ] || printf '%s\t%s\n' "$f" "$nm" >> "$TMP/lifts"
    done
  fi

  # review-exceptions.md: every line after the first, CR and blank lines
  # aside, becomes an entry of two lines (references/accepted-exceptions.md
  # of the team skill gives the line's form).
  : > "$TMP/excs"; : > "$TMP/exclist"
  rm -rf "$TMP/exc"; mkdir -p "$TMP/exc"
  if [ "$PEXC" = 1 ]; then
    LC_ALL=C awk -v BINMODE=3 -v out="$TMP/exc" -v today="$TODAY" '
      NR == 1 { next }
      { sub(/\r$/, "") }
      /^[ \t]*$/ { next }
      { t = $0; sub(/^- /, "", t)
        p = t; i = index(p, " · "); if (i) p = substr(p, 1, i - 1)
        d = today; j = index(t, "accepted ")
        if (j) { c = substr(t, j + 9, 10); if (c ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) d = c }
        n++; f = sprintf("%s/exc-%04d", out, n)
        printf "## [%s] exception %s\n[EXCEPTION] %s\n", d, p, t > f; close(f)
        printf "%s\t%s\t%s\n", f, d, p }' "$OPS/review-exceptions.md" > "$TMP/exclist" \
      || { echo "migrate-knowledge: could not read $OPS/review-exceptions.md" >&2; exit 2; }
    while IFS="$TAB" read -r f d p; do
      s="$(slug "$p")"; nm="$d-exception"; [ -z "$s" ] || nm="$nm-$s"
      nm="$(claim "$f" "$nm")"
      [ -z "$nm" ] || printf '%s\t%s\n' "$f" "$nm" >> "$TMP/excs"
    done < "$TMP/exclist"
  fi

  iidle=0
  [ -n "$pidx" ] || [ -s "$TMP/taken" ] || [ "$PEXC" = 1 ] || iidle=1
  plan_accept "$TMP/taken" "$RD"; IN=$PA IM=$PT
}
inbox_plan
if [ -n "$inbox_reason" ]; then
  echo "migrate-knowledge: refused — $inbox_reason; nothing was moved." >&2
  exit 1
fi
if [ "$iidle" = 1 ]; then rem_line="remarks: $RD: nothing to move"; else rem_line="remarks: $RD: $IN moved, $IM already there"; fi

# plan_copy [skip]: every remark of RL, accepted into RC; with "skip", less
# those the copy stamp names (carried before). Fills $TMP/csrcs; sets CN, CM,
# CS (skipped) and CSP (its report clause), and copy_line when there is
# anything to copy.
CN=0 CM=0 CS=0 CSP="" copy_line=""
: > "$TMP/csrcs"; : > "$TMP/cnames"
[ ! -f "$COPIED" ] || tr -d '\r' < "$COPIED" | grep '^remark=' > "$TMP/cnames"
plan_copy() {
  local f
  if [ -d "$RL" ]; then
    for f in "$RL"/*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      if [ "${1:-}" = skip ] && grep -qxF -- "remark=${f##*/}" "$TMP/cnames"; then CS=$((CS + 1)); continue; fi
      printf '%s\t%s\n' "${f##*/}" "$f" >> "$TMP/csrcs"
    done
  fi
  [ "$CS" = 0 ] || CSP=", $CS copied before"
  plan_accept "$TMP/csrcs" "$RC"; CN=$PA CM=$PT
  [ ! -s "$TMP/csrcs" ] || copy_line="remarks: $RC: $CN copied from $RL, $CM already there$CSP"
}

# --- 3. the project part, planned --------------------------------------------
tracked=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -z "$(git ls-files -- "$DIR" 2>/dev/null | head -1)" ] || tracked=1
fi
legacy_project=0; has_project "$LEGACY" && legacy_project=1
action=none note_line="" SRC="" K=0 do_import=0 drop_legacy=0 pre_props=0 HOLDT=""

# plan_import: the authored lines of the private copy, what the remarks dirs
# already hold, and what this run writes. Fills $TMP/new (n, rel, line, mark
# per entry to write); sets K, the number of entries this run writes.
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

  # The inbox as it is before this run, and the remarks dirs: their marks
  # (resolved ones count as present) with the file holding each, and an older
  # index file when one is still there, read only for the numbering below.
  : > "$TMP/marks"
  for d in "$OPS/learnings" "$LEGACY/learnings" "$RD" "$RL" "$RC"; do
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
    for d in "$OPS/learnings" "$LEGACY/learnings" "$RD" "$RL" "$RC"; do
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
    # Already a remark: an earlier run, or an interrupted one, wrote it.
    [ -z "$hit" ] || continue
    n=$((n + 1))
    printf '%s\t%s\t%s\t%s\n' "$n" "$rel" "$line" "$mark" >> "$TMP/new"
    printf '%s\t%s-migrated-rule-%s.md\n' "$mark" "$TODAY" "$n" >> "$TMP/marks"
  done < "$TMP/kept"
  K="$(wc -l < "$TMP/new" | tr -d ' ')"
}

case "$mode" in
first)
  if dir_present || [ "$tracked" = 1 ]; then
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
  # knowledge.dir holding only its remarks dir: those remarks go into the
  # directory that becomes knowledge.dir (HOLDT), before the rename, so they
  # land where they were and an interrupted run still carries them. A name
  # already there with the same bytes is dropped; with other bytes, refused.
  : > "$TMP/hold"; : > "$TMP/conflicts"; pre_props=0
  if [ -d "$DIR" ]; then
    pre_props=1
    if [ "$action" = rename ]; then HOLDT="$LEGACY/$PROPD"; else HOLDT="$STAGE/$PROPD"; fi
    # What the move puts into HOLDT: its own files, and in the stage path
    # a <proposalsDir>/ of the source staged before.
    SRCP=""; [ "$action" != stage ] || [ -z "$SRC" ] || SRCP="$SRC/$PROPD"
    find "$RC" -mindepth 1 -maxdepth 1 2>/dev/null | LC_ALL=C sort > "$TMP/pre"
    while IFS= read -r e; do
      nm="${e##*/}" other=""
      if [ -e "$HOLDT/$nm" ] || [ -L "$HOLDT/$nm" ]; then other="$HOLDT/$nm"
      elif [ -n "$SRCP" ] && { [ -e "$SRCP/$nm" ] || [ -L "$SRCP/$nm" ]; }; then other="$SRCP/$nm"; fi
      if [ -z "$other" ]; then
        printf 'move\t%s\n' "$e" >> "$TMP/hold"
      elif [ -f "$e" ] && [ ! -L "$e" ] && [ -f "$other" ] && [ ! -L "$other" ] && cmp -s -- "$e" "$other"; then
        printf 'same\t%s\n' "$e" >> "$TMP/hold"
      else
        echo "  $nm (in $RC/ and ${other%/*}/)" >> "$TMP/conflicts"
      fi
    done < "$TMP/pre"
    if [ -s "$TMP/conflicts" ]; then
      echo "migrate-knowledge: refused — $DIR/ holds only remarks, and these names exist with other content in the directory that becomes $DIR/. Keep one of each by hand, then run --first-commit again; nothing was moved:" >&2
      cat "$TMP/conflicts" >&2; exit 1
    fi
  fi
  # The remarks of the private copy follow the knowledge into its new directory.
  plan_copy
  ;;
drop)
  if [ "$tracked" = 0 ]; then
    echo "migrate-knowledge: refused — nothing under $DIR/ is tracked in this branch, so the private copy in $LEGACY/ is the only knowledge here; nothing was removed." >&2
    exit 1
  fi
  if [ "$RD" != "$RC" ]; then
    echo "migrate-knowledge: refused — $DIR/ holds no knowledge file directly inside, so the remarks dir is still $RD/; nothing was removed." >&2
    exit 1
  fi
  BK="$OPS/legacy-knowledge-$NOW"
  [ ! -e "$BK" ] || BK="$BK-$$"
  PBK="$BK-proposals"
  # A remark carried before and consumed since must not come back.
  plan_copy skip
  [ ! -d "$RL" ] || copy_line="remarks: $RC: $CN copied from $RL, $CM already there$CSP; $RL removed (backup $PBK)"
  if [ -d "$LEGACY" ] && [ -n "$(project_entries "$LEGACY")" ]; then
    plan_import
    drop_legacy=1
    proj_line="project: private copy removed (backup $BK; $K authored lines kept as remarks)"
  else
    proj_line="project: in place ($DIR)"
  fi
  action=drop
  ;;
default)
  if [ "$tracked" = 1 ]; then
    if [ "$legacy_project" = 1 ] && [ ! -f "$STAMP" ]; then
      plan_import
      do_import=1
      proj_line="project: in place ($DIR); private copy kept for branches without knowledge ($K authored lines kept as remarks)"
    else
      proj_line="project: in place ($DIR)"
    fi
    # The first pass that sees the committed directory as the knowledge
    # carries the private copy's remarks into it, once.
    [ -f "$COPIED" ] || [ "$(resolve project)" != "$DIR" ] || plan_copy
    [ "$do_import" = 0 ] && [ ! -s "$TMP/csrcs" ] || action=import
    # The committed copy is what counts now; a staging directory beside it is
    # an interrupted move from before it was committed.
    [ ! -d "$STAGE" ] || proj_line="$proj_line; an interrupted move left $STAGE/: $DIR/ is committed, so remove it once nothing in it is missing from $DIR/"
  elif dir_present; then
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

if [ -s "$TMP/rconf" ]; then
  echo "migrate-knowledge: refused — these remarks exist with other content than the file that would be copied there; move them aside by hand, then run again; nothing was moved:" >&2
  cat "$TMP/rconf" >&2
  exit 1
fi

# The note on remarks this run adds to a committed knowledge directory.
untracked_note() { # <files added>
  [ "$tracked" = 1 ] && [ "$RD" = "$RC" ] && [ "$1" -gt 0 ] || return 0
  echo "note: $1 new files under $RC $UNTRACKED_TAIL"
}

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
  [ "$mode" = first ] || echo "would: $rem_line"
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
    echo "would: $rem_line"
  fi
  [ -z "$copy_line" ] || echo "would: $copy_line"
  [ -z "$note_line" ] || echo "would: $note_line"
  u="$(untracked_note "$((IN + K + CN))")"
  [ -z "$u" ] || echo "would: $u"
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

# accept_into <dir> <file> ...: tools/remarks.sh accept, once the resolver
# prints <dir> as the remarks dir; sets AA (added) and AT (already there).
accept_into() {
  local d="$1" r
  shift
  r="$(resolve remarks)"
  [ "$r" = "$d" ] || { echo "migrate-knowledge: the remarks dir is now '$r', not $d as planned; nothing more was copied; run again" >&2; exit 2; }
  bash "$TEAM_ROOT/tools/remarks.sh" accept "$@" > "$TMP/acc" 2> "$TMP/accerr" \
    || { cat "$TMP/accerr" >&2; echo "migrate-knowledge: could not copy the remarks into $d/; fix that and run again" >&2; exit 2; }
  AA="$(grep -c '^added: ' "$TMP/acc")"; AT="$(grep -c '^already there: ' "$TMP/acc")"
}

# --- 4b. the inbox ----------------------------------------------------------------
IA=0
inbox_act() {
  local IB DI f nm
  if [ "$iidle" = 1 ]; then echo "$rem_line"; return 0; fi
  # The backup, before the first write.
  IB="$OPS/inbox-backup-$NOW"; [ ! -e "$IB" ] || IB="$IB-$$"
  mkdir -p "$IB" || werr "create $IB/"
  for nm in LEARNINGS.md learnings review-exceptions.md; do
    [ -e "$OPS/$nm" ] || continue
    { cp -Rp "$OPS/$nm" "$IB/$nm" && diff -r "$OPS/$nm" "$IB/$nm" >/dev/null 2>&1; } || werr "back up $OPS/$nm to $IB/; nothing was moved"
  done
  # The lifted entries and the exception entries become entry files.
  cat "$TMP/lifts" "$TMP/excs" > "$TMP/gen"
  while IFS="$TAB" read -r f nm; do
    { mkdir -p "$OPS/learnings" && cp -- "$f" "$OPS/learnings/$nm"; } || werr "write $OPS/learnings/$nm"
  done < "$TMP/gen"
  # Every entry file into the remarks dir; the sources go once they are there.
  set --
  if [ -d "$OPS/learnings" ]; then
    for f in "$OPS/learnings"/*.md; do [ ! -f "$f" ] || set -- "$@" "$f"; done
  fi
  AA=0 AT=0
  if [ "$#" -gt 0 ]; then
    accept_into "$RD" "$@"
    rm -f -- "$@" || werr "remove the moved entry files from $OPS/learnings/"
  fi
  [ ! -d "$OPS/learnings" ] || rmdir "$OPS/learnings" 2>/dev/null
  if [ -f "$OPS/LEARNINGS.md" ]; then
    DI="$OPS/dropped-index-$NOW.md"; [ ! -e "$DI" ] || DI="$OPS/dropped-index-$NOW-$$.md"
    mv -- "$OPS/LEARNINGS.md" "$DI" || werr "move $OPS/LEARNINGS.md to $DI"
  fi
  if [ "$PEXC" = 1 ]; then rm -f -- "$OPS/review-exceptions.md" || werr "remove $OPS/review-exceptions.md"; fi
  IA=$AA
  echo "remarks: $RD: $AA moved, $AT already there"
}
[ "$mode" = first ] || inbox_act

# write_import: the planned entries, one file each, accepted into the remarks
# dir; sets KA, the files added.
KA=0
write_import() {
  local n rel line mark entry
  set --
  while IFS="$TAB" read -r n rel line mark; do
    mkdir -p "$OPS/learnings" || werr "create $OPS/learnings/"
    entry="$OPS/learnings/$TODAY-migrated-rule-$n.md"
    {
      printf '## [%s] Migrated rule %s\n' "$TODAY" "$n"
      # No edition path: as a remark, this text becomes committed knowledge.
      printf -- "- **Symptom:** the private copy's %s holds an authored line the committed copy (%s/) lacks: %s\n" "$rel" "$DIR" "$line"
      printf -- '- **Root cause:** written into the private copy before the project knowledge moved to the committed directory.\n'
      printf -- '- **Fix pattern:** the knowledge refresh makes it a rule file in %s/%s/, or drops it when the committed knowledge already says it.\n' "$DIR" "$RULESD"
      printf -- '- **Files touched:** %s/%s\n' "$DIR" "$rel"
      printf -- '- **Tags:** migration\n'
      printf '%s\n' "$mark"
    } > "$entry" || werr "write $entry"
    set -- "$@" "$entry"
  done < "$TMP/new"
  [ "$#" -gt 0 ] || return 0
  accept_into "$RD" "$@"; KA=$AA
  rm -f -- "$@" || werr "remove the migrated entry files from $OPS/learnings/"
  rmdir "$OPS/learnings" 2>/dev/null
  return 0
}

# carry: the remarks of RL accepted into RC; they stay in RL. Sets CA, the
# files added, CT, those already there, and copy_line from what was done.
# The stamp names every remark carried, this run's and earlier runs'.
CA=0 CT=0
carry() {
  local b p
  [ -s "$TMP/csrcs" ] || return 0
  set --
  while IFS="$TAB" read -r b p; do set -- "$@" "$p"; printf 'remark=%s\n' "$b" >> "$TMP/cnames"; done < "$TMP/csrcs"
  accept_into "$RC" "$@"; CA=$AA CT=$AT
  copy_line="remarks: $RC: $AA copied from $RL, $AT already there$CSP"
  { printf 'date=%s\ncopied=%s\n' "$TODAY" "$AA"; LC_ALL=C sort -u "$TMP/cnames"; } > "$TMP/stamp" \
    && cp -- "$TMP/stamp" "$COPIED" || werr "write $COPIED"
}

# carry_in <dir>: the entries of a knowledge.dir that holds only its remarks
# dir, as planned ($TMP/hold), into <dir>; then the emptied knowledge.dir goes,
# so the rename below can create it.
carry_in() {
  local how e
  [ "$pre_props" = 1 ] || return 0
  if [ -s "$TMP/hold" ]; then
    mkdir -p "$1" || werr "create $1/"
    while IFS="$TAB" read -r how e; do
      case "$how" in
        move) mv -- "$e" "$1/${e##*/}" || werr "move $e to $1/" ;;
        same) rm -f -- "$e" || werr "remove $e (the same bytes are in $1/)" ;;
      esac
    done < "$TMP/hold"
  fi
  [ ! -d "$RC" ] || rmdir -- "$RC" || werr "remove the emptied $RC/"
  rmdir -- "$DIR" || werr "remove the emptied $DIR/"
}

case "$action" in
rename)
  # One rename: the knowledge directory appears whole or not at all. An empty
  # staging directory without a record is what an earlier start left; it goes.
  [ ! -d "$STAGE" ] || rmdir "$STAGE" 2>/dev/null
  carry_in "$HOLDT"
  { mkdir -p "$(dirname "$DIR")" && mv -- "$LEGACY" "$DIR"; } \
    || { echo "migrate-knowledge: could not move $LEGACY/ to $DIR/ (a file open elsewhere?); nothing of it was moved; fix that and run again" >&2; exit 2; }
  echo "$proj_line"
  extract_rules
  inbox_act
  carry
  [ -z "$copy_line" ] || echo "$copy_line"
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
  carry_in "$HOLDT"
  # The record goes with the staging directory and is removed only once the
  # rename succeeded, so a failed rename resumes from the same source.
  mv -- "$STAGE" "$DIR" || { echo "migrate-knowledge: could not rename $STAGE/ to $DIR/; fix that and run --first-commit again to finish" >&2; exit 2; }
  rm -f -- "$DIR/${SRCREC##*/}"
  [ -z "$SRC" ] || rmdir "$SRC" 2>/dev/null
  echo "$proj_line"
  extract_rules
  inbox_act
  carry
  [ -z "$copy_line" ] || echo "$copy_line"
  [ -z "$note_line" ] || echo "$note_line"
  ;;
drop)
  [ "$drop_legacy" = 0 ] || write_import
  carry
  if [ "$drop_legacy" = 1 ]; then
    { mkdir -p "$BK" && cp -Rp "$LEGACY/." "$BK/" && diff -r "$LEGACY" "$BK" >/dev/null 2>&1; } \
      || { echo "migrate-knowledge: could not back up $LEGACY/ to $BK/; nothing was removed" >&2; exit 2; }
  fi
  if [ -d "$RL" ]; then
    { mkdir -p "$PBK" && cp -Rp "$RL/." "$PBK/" && diff -r "$RL" "$PBK" >/dev/null 2>&1; } \
      || { echo "migrate-knowledge: could not back up $RL/ to $PBK/; nothing was removed" >&2; exit 2; }
  fi
  if [ "$drop_legacy" = 1 ]; then
    rm -rf -- "$LEGACY" || { echo "migrate-knowledge: could not remove $LEGACY/ (the backup is $BK/); fix that and run again" >&2; exit 2; }
  fi
  if [ -d "$RL" ]; then
    rm -rf -- "$RL" || { echo "migrate-knowledge: could not remove $RL/ (the backup is $PBK/); fix that and run again" >&2; exit 2; }
    copy_line="remarks: $RC: $CA copied from $RL, $CT already there$CSP; $RL removed (backup $PBK)"
  fi
  echo "$proj_line"
  [ -z "$copy_line" ] || echo "$copy_line"
  ;;
import)
  [ "$do_import" = 0 ] || write_import
  carry
  if [ "$do_import" = 1 ]; then
    mkdir -p "$CAPS" && printf 'date=%s\nlines=%s\n' "$TODAY" "$K" > "$STAMP" \
      || { echo "migrate-knowledge: could not write $STAMP" >&2; exit 2; }
  fi
  echo "$proj_line"
  [ -z "$copy_line" ] || echo "$copy_line"
  ;;
*)
  echo "$proj_line"
  ;;
esac
untracked_note "$((IA + KA + CA))"
exit 0
