#!/usr/bin/env bash
# Dream Team — moves a project's run state from the legacy directory
# (tracking.legacyDir) into the shared one (tracking.dir) that every edition
# of the team reads. See team-manifest.json → tracking.
#
#   bash .claude/tools/migrate-tracking.sh [--dry-run]     (from the project root)
#
# Order serves an interrupted run: the knowledge directory is backed up and
# rewritten first, then the path is rewritten inside the legacy tree, then
# its entries are moved, then the empty legacy directory is removed. Until
# that last step the legacy directory exists, so running again repeats every
# step, and each step is idempotent.
#
# Never written: knowledge backups (byte-exact copies), binary files, and the
# project's own files — those that name the legacy directory are listed for
# the user to edit.
#
# Exit 0 = migrated, nothing to migrate, or dry run. 1 = refused: a run is
# open, or a name exists in both directories. 2 = error.
set -uo pipefail

dry=0
case "${1:-}" in
  --dry-run) dry=1 ;;
  "") ;;
  *) echo "usage: migrate-tracking.sh [--dry-run]" >&2; exit 2 ;;
esac

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 2
M="$TEAM_ROOT/team-manifest.json"
[ -f "$M" ] || { echo "migrate: no team-manifest.json in $TEAM_ROOT" >&2; exit 2; }

# The string value of a key placed directly inside a top-level block.
value_in() {
  tr -d '\r' < "$M" | awk -v b="$1" -v k="$2" '
    index($0, "  \"" b "\": {") == 1 { f = 1; next }
    f && /^  }/ { exit }
    f && index($0, "    \"" k "\":") == 1 { sub(/^[^:]*:[ \t]*"/, ""); sub(/".*$/, ""); print; exit }'
}
NEW="$(value_in tracking dir)"
OLD="$(value_in tracking legacyDir)"
KNOW="$(value_in knowledge dir)"
for v in "$NEW" "$OLD"; do
  case "$v" in
    ''|*/*|*[!A-Za-z0-9._-]*)
      echo "migrate: tracking.dir and tracking.legacyDir must be plain directory names (got '$v')" >&2; exit 2 ;;
  esac
done
[ -n "$KNOW" ] || { echo "migrate: knowledge.dir is missing from the manifest" >&2; exit 2; }

for p in "$OLD" "$NEW"; do
  [ ! -L "$p" ] || { echo "migrate: $p is a symbolic link; refusing to touch anything. Replace it with a real directory and run again." >&2; exit 2; }
done
[ -e "$OLD" ] || { echo "migrate: nothing to migrate ($OLD/ not found)"; exit 0; }
[ -d "$OLD" ] || { echo "migrate: $OLD exists but is not a directory" >&2; exit 2; }
[ ! -e "$NEW" ] || [ -d "$NEW" ] || { echo "migrate: $NEW exists but is not a directory" >&2; exit 2; }

for d in "$OLD" "$NEW"; do
  [ -f "$d/.team-mode" ] || continue
  cid="$(sed -n 's/^context_id=//p' "$d/.team-mode" | head -1 | tr -d '\r')"
  echo "migrate: refused — a run is open: ${cid:-unknown} (marker $d/.team-mode)." >&2
  echo "In the session that runs it: /team stop. Then /team-setup fix, then /team resume." >&2
  exit 1
done

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

find "$OLD" -mindepth 1 -maxdepth 1 | LC_ALL=C sort > "$TMP/entries"
: > "$TMP/conflicts"
while IFS= read -r e; do
  [ ! -e "$NEW/${e##*/}" ] || echo "${e##*/}" >> "$TMP/conflicts"
done < "$TMP/entries"
if [ -s "$TMP/conflicts" ]; then
  echo "migrate: refused — these names exist in both $OLD/ and $NEW/. Keep one of each (delete or merge the other by hand), then run again:" >&2
  sed 's/^/  /' "$TMP/conflicts" >&2
  exit 1
fi

# Text files under a directory that name the legacy directory; knowledge
# backups excluded, binary files skipped by -I.
mentions() {
  [ -d "$1" ] || return 0
  grep -rlIF --exclude-dir='knowledge-backup-*' --exclude='*.mt-tmp' -- "$OLD" "$1" 2>/dev/null | LC_ALL=C sort
}
# The project's own files that name it: git grep sees tracked and untracked
# files and skips ignored ones; the team's directories are left out. The
# patterns spell the dot as [.] so no literal team path appears here.
project_mentions() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "  (not a git work tree; project files were not searched)"; return 0; }
  local hits
  hits="$(git -c core.quotepath=off grep --untracked -nIF -- "$OLD" 2>/dev/null \
    | grep -v -e '^[.]claude/' -e '^[.]github/dream-team/' -e "^$OLD/" -e "^$NEW/")"
  if [ -n "$hits" ]; then printf '%s\n' "$hits" | sed 's/^/  /'; else echo "  none"; fi
}
PAT="$(printf '%s' "$OLD" | sed 's/[.[\*^$/]/\\&/g')"
# GNU sed on Windows (Git Bash) drops CR in text mode; -b keeps CRLF files intact.
SEDB=""; sed -b p </dev/null >/dev/null 2>&1 && SEDB="-b"
rewrite() {
  cp -p -- "$1" "$1.mt-tmp" && sed $SEDB "s/$PAT/$NEW/g" "$1" > "$1.mt-tmp" && mv -f -- "$1.mt-tmp" "$1" || { rm -f -- "$1.mt-tmp"; return 1; }
}

mentions "$OLD" > "$TMP/run"
mentions "$KNOW" > "$TMP/know"

if [ "$dry" = 1 ]; then
  echo "Dream Team run-state migration: $OLD/ → $NEW/"
  echo "Entries to move: $(wc -l < "$TMP/entries" | tr -d ' ')"
  sed 's|^.*/|  |' "$TMP/entries"
  echo "Files to rewrite: $(wc -l < "$TMP/run" | tr -d ' ') in the run state, $(wc -l < "$TMP/know" | tr -d ' ') in $KNOW/ (backed up first)"
  echo "Project files that still mention $OLD (edit these yourself; the migration never does):"
  project_mentions
  echo "migrate: dry run; nothing was changed"
  exit 0
fi

# Leftovers of an interrupted rewrite; the suffix belongs to this script.
find "$OLD" -type f -name '*.mt-tmp' -exec rm -f -- {} + 2>/dev/null
[ ! -d "$KNOW" ] || find "$KNOW" -type f -name '*.mt-tmp' -exec rm -f -- {} + 2>/dev/null
mkdir -p "$NEW" || { echo "migrate: could not create $NEW/" >&2; exit 2; }

kn=0 bk=""
if [ -s "$TMP/know" ]; then
  bk="$NEW/knowledge-backup-$(date +%Y-%m-%d-%H%M)-tracking"
  [ ! -e "$bk" ] || bk="$bk-$$"
  { mkdir -p "$bk" && cp -R "$KNOW/." "$bk/"; } \
    || { echo "migrate: could not back up $KNOW/ to $bk/; nothing was rewritten or moved" >&2; exit 2; }
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    rewrite "$f" || { echo "migrate: could not rewrite $f (read-only or locked?); fix that and run again" >&2; exit 2; }
    kn=$((kn + 1))
  done < "$TMP/know"
fi

rn=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  rewrite "$f" || { echo "migrate: could not rewrite $f (read-only or locked?); fix that and run again" >&2; exit 2; }
  rn=$((rn + 1))
done < "$TMP/run"

moved=0; : > "$TMP/moved"
while IFS= read -r e; do
  mv -- "$e" "$NEW/${e##*/}" || { echo "migrate: could not move $e (read-only or open elsewhere?); fix that and run again" >&2; exit 2; }
  moved=$((moved + 1)); echo "${e##*/}" >> "$TMP/moved"
done < "$TMP/entries"
rmdir "$OLD" || { echo "migrate: $OLD/ is not empty after the move (a file could not be moved?); fix that and run again" >&2; exit 2; }

echo "Migrated $OLD/ → $NEW/: $moved entries moved; text rewritten in $rn run-state files and $kn knowledge files."
sed 's/^/  /' "$TMP/moved"
[ -z "$bk" ] || echo "Knowledge backup: $bk/"
echo "Project files that still mention $OLD (edit these yourself; the migration never does):"
project_mentions
