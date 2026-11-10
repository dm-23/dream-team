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
# Every mode moves the operative files first. Then, for the project files:
#   default         the committed copy is tracked in this branch: authored
#                   lines of the private copy that the committed copy lacks
#                   become inbox entries, once (a stamp file records it), and
#                   the private copy stays for branches without knowledge.
#                   Nothing tracked: the report says the first commit waits.
#   --first-commit  the project files move into knowledge.dir, which must not
#                   exist yet. --from picks the source when this edition's
#                   directory and another edition's both hold project files.
#   --drop-legacy   the committed copy is tracked: the private copy is backed
#                   up under operativeDir, then removed.
#   --dry-run       prints what a run would do, prefixed "would:"; writes nothing.
#
# Every refusal is decided before the first write, so a refused run leaves the
# tree as it found it. Moves are byte-exact (mv); a moved file is never
# rewritten.
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
# The string value of a key inside an object placed inside a top-level block.
nested_in() {
  tr -d '\r' < "$M" | awk -v b="$1" -v o="$2" -v k="$3" '
    index($0, "  \"" b "\": {") == 1 { f = 1; next }
    f && /^  }/ { exit }
    f && index($0, "    \"" o "\": {") == 1 { g = 1; next }
    g && /^    }/ { exit }
    g && index($0, "      \"" k "\":") == 1 { sub(/^[^:]*:[ \t]*"/, ""); sub(/".*$/, ""); print; exit }'
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
TRK="$(value_in tracking dir)";                  TRK="${TRK%/}";       rel_ok tracking.dir "$TRK"
TRKOLD="$(value_in tracking legacyDir)";         TRKOLD="${TRKOLD%/}"; rel_ok tracking.legacyDir "$TRKOLD"
TPL="$(nested_in knowledge persistentTemplates LEARNINGS.md)";         rel_ok "knowledge.persistentTemplates LEARNINGS.md" "$TPL"
OTHERS="$(array_in knowledge otherEditionDirs)"

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
STAMP="$OPS/.legacy-rules-imported"
TODAY="$(date +%Y-%m-%d)"
# GNU sed on Windows (Git Bash) drops CR in text mode; -b keeps CRLF files intact.
SEDB=""; sed -b p </dev/null >/dev/null 2>&1 && SEDB="-b"

# --- 1. refusals ---------------------------------------------------------
links=""
for p in "$LEGACY" "$LEGACY/learnings" "$DIR" "$OPS" "$OPS/learnings" "$CAPS" ${from:+"$from"}; do
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
for p in "$LEGACY" "$DIR" "$OPS" "$CAPS"; do
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

# --- 3. the project part, planned --------------------------------------------
tracked=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ -z "$(git ls-files -- "$DIR" 2>/dev/null | head -1)" ] || tracked=1
fi
legacy_project=0; has_project "$LEGACY" && legacy_project=1
action=none INDEX_FROM=""

case "$mode" in
first)
  if [ -e "$DIR" ]; then
    echo "migrate-knowledge: refused — $DIR/ already exists; the first knowledge commit has been made. Run without --first-commit." >&2
    exit 1
  fi
  : > "$TMP/cands"
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
    SRC="$(head -1 "$TMP/cands")"
  fi
  project_entries "$SRC" > "$TMP/pentries"
  proj_line="project: moved to $DIR: run /generate-knowledge, then commit it alone, one commit and one pull request, no other file"
  action=first
  ;;
drop)
  if [ "$tracked" = 0 ]; then
    echo "migrate-knowledge: refused — nothing under $DIR/ is tracked in this branch, so the private copy in $LEGACY/ is the only knowledge here; nothing was removed." >&2
    exit 1
  fi
  if [ -d "$LEGACY" ] && [ -n "$(project_entries "$LEGACY")" ]; then
    BK="$OPS/legacy-knowledge-$(date +%Y-%m-%d-%H%M)"
    [ ! -e "$BK" ] || BK="$BK-$$"
    proj_line="project: private copy removed (backup $BK)"
    action=drop
  else
    proj_line="project: in place ($DIR)"
  fi
  ;;
default)
  if [ "$legacy_project" = 1 ]; then
    if [ "$tracked" = 0 ]; then
      proj_line="project: waiting for $DIR in the repository; the first knowledge commit is made with --first-commit"
    elif [ -f "$STAMP" ]; then
      proj_line="project: in place ($DIR)"
    else
      action=import
    fi
  elif [ "$tracked" = 1 ]; then
    proj_line="project: in place ($DIR)"
  else
    proj_line="project: nothing to move"
  fi
  ;;
esac

if [ "$action" = import ]; then
  # Authored lines of the private copy: they end in "— source: user" or carry
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
  LC_ALL=C awk '
    FILENAME == ARGV[1] { c[$0] = 1; next }
    { t = index($0, "\t"); line = substr($0, t + 1)
      if (!(line in c) && !(line in seen)) { seen[line] = 1; print } }' "$TMP/committed" "$TMP/cand" > "$TMP/kept"
  K="$(wc -l < "$TMP/kept" | tr -d ' ')"
  proj_line="project: in place ($DIR); private copy kept for branches without knowledge ($K authored lines kept as inbox entries)"

  # Numbering continues after the highest Migrated rule already present.
  {
    for d in "$OPS/learnings" "$LEGACY/learnings"; do
      [ -d "$d" ] && find "$d" -mindepth 1 -maxdepth 1 -name '*-migrated-rule-*' | sed -n 's/.*-migrated-rule-\([0-9][0-9]*\)[^/]*$/\1/p'
    done
    for f in "$OPS/LEARNINGS.md" "$LEGACY/LEARNINGS.md"; do
      [ -f "$f" ] && tr -d '\r' < "$f" | sed -n 's/^|[^|]*| *Migrated rule \([0-9][0-9]*\) *|.*/\1/p'
    done
    echo 0
  } | sort -n | tail -1 > "$TMP/maxn"
  # Marks an interrupted run already wrote are not written twice.
  : > "$TMP/marks"
  for d in "$OPS/learnings" "$LEGACY/learnings"; do
    [ -d "$d" ] || continue
    find "$d" -mindepth 1 -maxdepth 1 -type f -name '*-migrated-rule-*.md' -exec awk '{ sub(/\r$/, "") } /^\[PROMOTE\] / { print }' {} + >> "$TMP/marks" 2>/dev/null
  done
  if [ "$K" -gt 0 ] && [ ! -f "$OPS/LEARNINGS.md" ] && [ ! -f "$LEGACY/LEARNINGS.md" ]; then
    INDEX_FROM="$TPL"
    [ -f "$INDEX_FROM" ] || INDEX_FROM="$TEAM_ROOT/templates/${TPL##*/}"
    [ -f "$INDEX_FROM" ] || { echo "migrate-knowledge: the LEARNINGS.md template ($TPL) is missing; nothing was moved or written" >&2; exit 2; }
  fi
fi

# --- dry run ------------------------------------------------------------------
if [ "$dry" = 1 ]; then
  echo "would: $ops_line"
  echo "would: $proj_line"
  exit 0
fi

# --- 4. act ---------------------------------------------------------------------
while IFS="$(printf '\t')" read -r src dst; do
  mkdir -p "$(dirname "$dst")" && mv -- "$src" "$dst" \
    || { echo "migrate-knowledge: could not move $src to $dst (read-only or open elsewhere?); fix that and run again" >&2; exit 2; }
done < "$TMP/moves"
[ ! -d "$LEGACY/learnings" ] || rmdir "$LEGACY/learnings" 2>/dev/null
[ ! -d "$LEGACY" ] || rmdir "$LEGACY" 2>/dev/null
echo "$ops_line"

case "$action" in
first)
  mkdir -p "$DIR" || { echo "migrate-knowledge: could not create $DIR/" >&2; exit 2; }
  while IFS= read -r e; do
    mv -- "$e" "$DIR/${e##*/}" || { echo "migrate-knowledge: could not move $e (read-only or open elsewhere?); fix that and run again" >&2; exit 2; }
  done < "$TMP/pentries"
  rmdir "$SRC" 2>/dev/null
  echo "$proj_line"
  [ ! -d "$SRC" ] || echo "note: $SRC/ keeps its operative files for that edition's own migration"
  ;;
drop)
  { mkdir -p "$BK" && cp -Rp "$LEGACY/." "$BK/" && diff -r "$LEGACY" "$BK" >/dev/null 2>&1; } \
    || { echo "migrate-knowledge: could not back up $LEGACY/ to $BK/; nothing was removed" >&2; exit 2; }
  rm -rf -- "$LEGACY" || { echo "migrate-knowledge: could not remove $LEGACY/ (the backup is $BK/); fix that and run again" >&2; exit 2; }
  echo "$proj_line"
  ;;
import)
  n="$(cat "$TMP/maxn")"
  : > "$TMP/rows"
  while IFS= read -r kept; do
    rel="${kept%%"$(printf '\t')"*}"; line="${kept#*"$(printf '\t')"}"
    rule="$(printf '%s\n' "$line" | LC_ALL=C awk '
      BEGIN { u = "— source: user"; l = "— source: learnings " }
      { s = $0
        if (length(s) >= length(u) && substr(s, length(s) - length(u) + 1) == u) s = substr(s, 1, length(s) - length(u))
        else { i = index(s, l); if (i) s = substr(s, 1, i - 1) }
        sub(/[ \t]+$/, "", s); sub(/^[ \t]*([-*+]|[0-9]+\.)[ \t]+/, "", s); sub(/^[ \t]+/, "", s)
        print s }')"
    mark="[PROMOTE] $rel — $rule"
    ! grep -qxF -- "$mark" "$TMP/marks" || continue
    n=$((n + 1))
    mkdir -p "$OPS/learnings" || exit 2
    entry="$OPS/learnings/$TODAY-migrated-rule-$n.md"
    {
      printf '## [%s] Migrated rule %s\n' "$TODAY" "$n"
      printf -- '- **Symptom:** the private knowledge copy (%s/%s) holds an authored line the committed copy (%s/) lacks: %s\n' "$LEGACY" "$rel" "$DIR" "$line"
      printf -- '- **Root cause:** written into the private copy before the project knowledge moved to the committed directory.\n'
      printf -- '- **Fix pattern:** /generate-knowledge writes the rule into %s/%s, or drops it when the committed copy already says it.\n' "$DIR" "$rel"
      printf -- '- **Files touched:** %s/%s\n' "$DIR" "$rel"
      printf -- '- **Tags:** migration\n'
      printf '%s\n' "$mark"
    } > "$entry" || { echo "migrate-knowledge: could not write $entry" >&2; exit 2; }
    printf '| %s | Migrated rule %s | migration |\n' "$TODAY" "$n" >> "$TMP/rows"
  done < "$TMP/kept"

  if [ -s "$TMP/rows" ]; then
    IDX="$OPS/LEARNINGS.md"
    if [ ! -f "$IDX" ]; then
      { [ -n "$INDEX_FROM" ] && cp -p -- "$INDEX_FROM" "$IDX"; } || { echo "migrate-knowledge: could not create $IDX" >&2; exit 2; }
    fi
    # Rows go after the last row of the index table, in the file's own line ending.
    # $'\r', not $(printf '\r'): command substitution drops a trailing CR in Git Bash.
    cr=""; [ "$(head -n 1 "$IDX" | tr -cd '\r' | wc -c | tr -d ' ')" = 0 ] || cr=$'\r'
    pos="$(tr -d '\r' < "$IDX" | awk '
      /^```/ { fence = !fence; next }
      fence { next }
      /^## / { inidx = ($0 ~ /^## Index[ \t]*$/); if (inidx && !h) h = NR; next }
      inidx && /^\|/ { last = NR }
      END { print (last ? last : 0) " " (h ? h : 0) }')"
    last="${pos% *}"; hd="${pos#* }"
    {
      if [ "$last" = 0 ]; then
        [ "$hd" != 0 ] || printf '%s\n## Index%s\n' "$cr" "$cr"
        printf '%s\n| Date | Title | Tags |%s\n|------|-------|------|%s\n' "$cr" "$cr" "$cr"
      fi
      while IFS= read -r r; do printf '%s%s\n' "$r" "$cr"; done < "$TMP/rows"
    } > "$TMP/insert"
    if [ "$last" != 0 ]; then at="$last"; elif [ "$hd" != 0 ]; then at="$hd"; else at='$'; fi
    { LC_ALL=C sed $SEDB "${at}r $TMP/insert" "$IDX" > "$IDX.mk-tmp" && mv -f -- "$IDX.mk-tmp" "$IDX"; } \
      || { rm -f -- "$IDX.mk-tmp"; echo "migrate-knowledge: could not add the index rows to $IDX" >&2; exit 2; }
  fi
  mkdir -p "$OPS" && printf 'date=%s\nlines=%s\n' "$TODAY" "$K" > "$STAMP" \
    || { echo "migrate-knowledge: could not write $STAMP" >&2; exit 2; }
  echo "$proj_line"
  ;;
*)
  echo "$proj_line"
  ;;
esac
exit 0
