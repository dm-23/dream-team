#!/usr/bin/env bash
# Reports whether a project is empty and whether its knowledge is a scaffold.
#
#   verify-knowledge-scaffold.sh <project-dir> <knowledge-dir>
#
# Two definitions live here and nowhere else; /generate-knowledge, /team,
# /team-setup and the prompt hook all call this script rather than restate
# them.
#
#   - The project is EMPTY when every top-level entry of <project-dir> is a
#     dot-prefixed name — the team's own directory, the run state, the
#     repository metadata, editor settings — or one of the root documents a
#     developer has before any code: a file named README*, LICENSE*, CLAUDE.md
#     or AGENTS.md, which a repository initialised on a hosting service or by
#     /init carries, and which /generate-knowledge reads as human
#     documentation either way. Any other entry, a file or a directory even
#     when that directory is empty, is content; so is a directory that
#     happens to carry one of those names.
#   - The knowledge is a SCAFFOLD when any knowledge file — a *.md directly
#     in <knowledge-dir>, never a topic or a learnings entry — opens with the
#     banner /generate-knowledge writes on an empty project. One bannered
#     file is enough: a run that regenerated a single file from code leaves
#     the other nine as scaffolds, and the reminder must not go quiet. The
#     banner is the whole marker: a separate marker file would be an
#     unclassified file to checks/verify-knowledge-integrity.sh and would need
#     a manifest key for no gain. A trailing CR and a leading byte-order mark
#     are tolerated, because an editor on Windows adds both. The date is
#     taken from PROJECT-OVERVIEW.md when it carries the banner, otherwise
#     from the first bannered file in name order, and is reported only when
#     it has the form YYYY-MM-DD; anything else reads "unknown", so a copied
#     template or a hand-edited banner never leaks a cut byte to a caller.
#
# Prints two lines, "project: empty | has content" and
# "knowledge: absent | generated | scaffold YYYY-MM-DD", then exits:
#   0 = nothing to say: the knowledge is absent or generated
#   1 = scaffold knowledge and the project has content: regeneration is due
#   2 = a path could not be read
#   3 = scaffold knowledge and the project is still empty
# 1 is kept apart from 3 so a caller that only wants "due" tests one code,
# as the prompt hook does with the remarks check. Writes nothing.
set -uo pipefail
export LC_ALL=C

project="${1:?usage: verify-knowledge-scaffold.sh <project-dir> <knowledge-dir>}"
knowledge="${2:?usage: verify-knowledge-scaffold.sh <project-dir> <knowledge-dir>}"
[ -d "$project" ] || { echo "FAIL: project dir not found: $project" >&2; exit 2; }

PREFIX='> SCAFFOLD — written on an empty project on '

[ -r "$project" ] && [ -x "$project" ] || { echo "FAIL: project dir not readable: $project" >&2; exit 2; }

state="empty"
for entry in "$project"/*; do          # the glob skips dot-prefixed names
  [ -e "$entry" ] || continue          # no match at all: the literal pattern
  name="${entry##*/}"
  if [ -f "$entry" ]; then
    case "$name" in README*|LICENSE*|CLAUDE.md|AGENTS.md) continue ;; esac
  fi
  state="has content"; break
done
echo "project: $state"

# banner_rest FILE -> prints what follows the prefix on FILE's first line, or
# nothing when the file does not open with the banner.
banner_rest() {
  local first
  first="$(head -1 "$1" 2>/dev/null | tr -d '\r')" || return 0
  first="${first#$'\xEF\xBB\xBF'}"
  case "$first" in
    "$PREFIX"*) printf '%s' "${first#"$PREFIX"}" ;;
  esac
}

overview="$knowledge/PROJECT-OVERVIEW.md"
if [ ! -f "$overview" ]; then
  echo "knowledge: absent"; exit 0
fi
[ -r "$overview" ] || { echo "FAIL: cannot read $overview" >&2; exit 2; }

rest="$(banner_rest "$overview")"
if [ -z "$rest" ]; then
  for f in "$knowledge"/*.md; do
    [ -f "$f" ] || continue
    rest="$(banner_rest "$f")"
    [ -n "$rest" ] && break
  done
fi
if [ -z "$rest" ]; then
  echo "knowledge: generated"; exit 0
fi

date="${rest:0:10}"
case "$date" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) date="unknown" ;;
esac
echo "knowledge: scaffold $date"
[ "$state" = "empty" ] && exit 3
exit 1
