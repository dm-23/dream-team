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
#     dot-prefixed name: the team's own directory, the run state, the
#     repository metadata, editor settings. Any other entry, a file or a
#     directory even when that directory is empty, is content.
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

if [ -n "$(find "$project" -mindepth 1 -maxdepth 1 ! -name '.*' -print -quit 2>/dev/null)" ]; then
  state="has content"
else
  state="empty"
fi
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
