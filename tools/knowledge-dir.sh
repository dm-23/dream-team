#!/usr/bin/env bash
# Dream Team — prints the project-root-relative directory that holds the
# project's knowledge or the operative files. See team-manifest.json → knowledge.
#
#   bash <team-root>/tools/knowledge-dir.sh project|operative     (from the project root)
#
# project:   knowledge.dir when it exists; otherwise knowledge.legacyDir when
#            it holds a *.md directly inside other than LEARNINGS.md and
#            CAPABILITIES.md; otherwise knowledge.dir.
# operative: knowledge.operativeDir when it exists; otherwise
#            knowledge.legacyDir when LEARNINGS.md is in it; otherwise
#            knowledge.operativeDir.
#
# Exit 0 = printed. 2 = bad argument, no manifest, or a key is missing.
set -uo pipefail

which="${1:-}"
case "$which" in
  project|operative) ;;
  *) echo "usage: knowledge-dir.sh project|operative" >&2; exit 2 ;;
esac

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 2
M="$TEAM_ROOT/team-manifest.json"
[ -f "$M" ] || { echo "knowledge-dir: no team-manifest.json in $TEAM_ROOT" >&2; exit 2; }

# The string value of a key placed directly inside a top-level block.
value_in() {
  tr -d '\r' < "$M" | awk -v b="$1" -v k="$2" '
    index($0, "  \"" b "\": {") == 1 { f = 1; next }
    f && /^  }/ { exit }
    f && index($0, "    \"" k "\":") == 1 { sub(/^[^:]*:[ \t]*"/, ""); sub(/".*$/, ""); print; exit }'
}

need() {
  local v
  v="$(value_in knowledge "$1")"
  [ -n "$v" ] || { echo "knowledge-dir: knowledge.$1 is missing from the manifest" >&2; exit 2; }
  printf '%s' "${v%/}"
}

LEGACY="$(need legacyDir)" || exit 2

if [ "$which" = project ]; then
  DIR="$(need dir)" || exit 2
  if [ ! -d "$DIR" ] && [ -d "$LEGACY" ]; then
    for f in "$LEGACY"/*.md; do
      [ -f "$f" ] || continue
      case "${f##*/}" in LEARNINGS.md|CAPABILITIES.md) continue ;; esac
      DIR="$LEGACY"
      break
    done
  fi
else
  DIR="$(need operativeDir)" || exit 2
  if [ ! -d "$DIR" ] && [ -f "$LEGACY/LEARNINGS.md" ]; then
    DIR="$LEGACY"
  fi
fi
printf '%s\n' "$DIR"
