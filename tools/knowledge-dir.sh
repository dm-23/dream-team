#!/usr/bin/env bash
# Dream Team — prints the project-root-relative directory that holds the
# project's knowledge, the operative files or the remarks. See
# team-manifest.json → knowledge.
#
#   bash <team-root>/tools/knowledge-dir.sh project|operative|remarks     (from the project root)
#
# project:   knowledge.dir when it holds a *.md directly inside; otherwise
#            knowledge.legacyDir when it holds a *.md directly inside other
#            than LEARNINGS.md and CAPABILITIES.md; otherwise knowledge.dir.
# operative: knowledge.operativeDir when it exists; else knowledge.legacyDir
#            when it holds LEARNINGS.md or learnings/; else
#            knowledge.operativeDir. Never an absolute path.
# remarks:   the proposals directory for remarks: knowledge.proposalsDir inside
#            knowledge.dir when project prints knowledge.dir, else inside
#            knowledge.operativeDir. Never created.
#
# Exit 0 = printed. 2 = bad argument, no manifest, or a key is missing.
set -uo pipefail

which="${1:-}"
case "$which" in
  project|operative|remarks) ;;
  *) echo "usage: knowledge-dir.sh project|operative|remarks" >&2; exit 2 ;;
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

has_md() { # <dir> [skip-learnings]: a *.md directly inside
  local f
  for f in "$1"/*.md; do
    [ -f "$f" ] || continue
    if [ "${2:-}" = skip ]; then
      case "${f##*/}" in LEARNINGS.md|CAPABILITIES.md) continue ;; esac
    fi
    return 0
  done
  return 1
}

if [ "$which" = project ] || [ "$which" = remarks ]; then
  DIR="$(need dir)" || exit 2
  if ! has_md "$DIR" && has_md "$LEGACY" skip; then
    DIR="$LEGACY"
    if [ "$which" = remarks ]; then DIR="$(need operativeDir)" || exit 2; fi
  fi
  if [ "$which" = remarks ]; then PD="$(need proposalsDir)" || exit 2; DIR="$DIR/$PD"; fi
else
  OPD="$(need operativeDir)" || exit 2
  if [ -d "$OPD" ]; then
    DIR="$OPD"
  elif [ -f "$LEGACY/LEARNINGS.md" ] || [ -d "$LEGACY/learnings" ]; then
    DIR="$LEGACY"
  else
    DIR="$OPD"
  fi
fi
printf '%s\n' "$DIR"
