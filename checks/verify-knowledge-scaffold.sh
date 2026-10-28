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
#   - The knowledge is a SCAFFOLD when <knowledge-dir>/PROJECT-OVERVIEW.md
#     exists and its first line is the banner /generate-knowledge writes on
#     an empty project. The banner is the whole marker: a separate marker
#     file would be an unclassified file to checks/verify-knowledge-integrity.sh
#     and would need a manifest key for no gain. A trailing CR and a leading
#     byte-order mark are tolerated, because an editor on Windows adds both.
#
# Prints two lines, "project: empty | has content" and
# "knowledge: absent | generated | scaffold YYYY-MM-DD", then exits:
#   0 = nothing to say: the knowledge is absent or generated
#   1 = scaffold knowledge and the project has content: regeneration is due
#   2 = a path could not be read
#   3 = scaffold knowledge and the project is still empty
# 1 is kept apart from 3 so a caller that only wants "due" tests one code,
# as the prompt hook does with the learnings inbox check. Writes nothing.
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

overview="$knowledge/PROJECT-OVERVIEW.md"
if [ ! -f "$overview" ]; then
  echo "knowledge: absent"; exit 0
fi
first="$(head -1 "$overview" 2>/dev/null | tr -d '\r')" || { echo "FAIL: cannot read $overview" >&2; exit 2; }
first="${first#$'\xEF\xBB\xBF'}"
case "$first" in
  "$PREFIX"*)
    rest="${first#"$PREFIX"}"
    echo "knowledge: scaffold ${rest:0:10}"
    [ "$state" = "empty" ] && exit 3
    exit 1 ;;
  *)
    echo "knowledge: generated"; exit 0 ;;
esac
