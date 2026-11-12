#!/usr/bin/env bash
# Dream Team — prints the project-root-relative directory that holds the
# project's knowledge or the operative files, or the project key. See
# team-manifest.json → knowledge.
#
#   bash <team-root>/tools/knowledge-dir.sh project|operative|remarks|key     (from the project root)
#
# project:   knowledge.dir when it holds a *.md directly inside; otherwise
#            knowledge.legacyDir when it holds a *.md directly inside other
#            than LEARNINGS.md and CAPABILITIES.md; otherwise knowledge.dir.
# operative: (1) the profile directory <profile root>/<key> when
#            knowledge.profileDir is not empty, the key resolves and that
#            directory exists (the resolver never creates it); (2) else
#            knowledge.operativeDir when it exists; (3) else
#            knowledge.legacyDir when it holds LEARNINGS.md or learnings/;
#            (4) else knowledge.operativeDir. The profile root is
#            $DREAM_TEAM_PROFILE when set, else profileDir with a leading ~
#            replaced by $HOME; it is printed through cygpath -m when cygpath
#            exists (C:/Users/... on Windows). Results (2)-(4) are
#            project-root-relative.
# remarks:   the proposals directory for remarks: knowledge.proposalsDir inside
#            knowledge.dir when project prints knowledge.dir, else inside
#            knowledge.operativeDir. Never created.
# key:       the project key, from the git remote: the slug of the last path
#            segment of the normalized address, a hyphen, and the first 8
#            characters of the address's git blob hash. The address is
#            remote.origin.url, else the first remote by name. Normalized:
#            no trailing / or .git, no scheme://, no user@ or user:password@,
#            scp-form first : turned into /, no :port, lower-cased.
#            Prints nothing and exits 1 when there is no repository or remote.
#
# Exit 0 = printed. 1 = key: no repository or no remote. 2 = bad argument, no
# manifest, or a key is missing.
set -uo pipefail

which="${1:-}"
case "$which" in
  project|operative|remarks|key) ;;
  *) echo "usage: knowledge-dir.sh project|operative|remarks|key" >&2; exit 2 ;;
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

# The project key, or nothing and status 1.
project_key() {
  local a r rest auth path head last slug h
  git rev-parse --git-dir >/dev/null 2>&1 || return 1
  a="$(git config --get remote.origin.url 2>/dev/null | tr -d '\r')"
  if [ -z "$a" ]; then
    r="$(git remote 2>/dev/null | tr -d '\r' | LC_ALL=C sort | head -n 1)"
    [ -n "$r" ] || return 1
    a="$(git config --get "remote.$r.url" 2>/dev/null | tr -d '\r')"
  fi
  [ -n "$a" ] || return 1
  a="${a%/}"; a="${a%.git}"; a="${a%/}"
  case "$a" in
    *://*)
      rest="${a#*://}"
      auth="${rest%%/*}"
      path=""
      case "$rest" in */*) path="/${rest#*/}" ;; esac
      auth="${auth##*@}"
      auth="${auth%%:*}"
      a="$auth$path"
      ;;
    *)
      head="${a%%[:/]*}"
      case "$head" in *@*) a="${a#*@}" ;; esac
      case "${a%%/*}" in *:*) a="${a/:/\/}" ;; esac
      ;;
  esac
  a="$(printf '%s' "$a" | tr 'A-Z' 'a-z')"
  [ -n "$a" ] || return 1
  last="${a##*/}"
  slug="$(printf '%s' "$last" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//')"
  [ -n "$slug" ] || slug="project"
  h="$(printf '%s' "$a" | git hash-object --stdin 2>/dev/null | tr -d '\r')"
  [ -n "$h" ] || return 1
  printf '%s-%s\n' "$slug" "${h:0:8}"
}

if [ "$which" = key ]; then
  project_key
  exit $?
fi

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
  DIR=""
  PROFILE="$(value_in knowledge profileDir)"
  if [ -n "$PROFILE" ]; then
    ROOT_P="${DREAM_TEAM_PROFILE:-}"
    if [ -z "$ROOT_P" ]; then
      case "$PROFILE" in
        "~"|"~/"*) ROOT_P="${HOME:-}${PROFILE#\~}" ;;
        *) ROOT_P="$PROFILE" ;;
      esac
    fi
    KEY="$(project_key)" && [ -n "$KEY" ] && [ -n "$ROOT_P" ] || KEY=""
    if [ -n "$KEY" ] && [ -d "${ROOT_P%/}/$KEY" ]; then
      DIR="${ROOT_P%/}/$KEY"
      if command -v cygpath >/dev/null 2>&1; then DIR="$(cygpath -m "$DIR")"; fi
    fi
  fi
  if [ -z "$DIR" ]; then
    if [ -d "$OPD" ]; then
      DIR="$OPD"
    elif [ -f "$LEGACY/LEARNINGS.md" ] || [ -d "$LEGACY/learnings" ]; then
      DIR="$LEGACY"
    else
      DIR="$OPD"
    fi
  fi
fi
printf '%s\n' "$DIR"
