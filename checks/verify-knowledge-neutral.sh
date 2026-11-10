#!/usr/bin/env bash
# Reports project knowledge that names a team path of either edition.
#
#   verify-knowledge-neutral.sh <knowledge-dir>
#
# The knowledge directory is read by both editions of the team, so a file in
# it must not name where one edition keeps its agents, skills, templates,
# hooks, checks, tools, knowledge or manifest: the other edition would be sent
# to a path that does not exist. Every file under the directory is scanned,
# recursively, topic directories included.
#
# A line that names a team path is reported as
#   <path>:<line>: names a team path: <match>
#
# Not team paths, so allowed: the project's own documents, the project profile
# and the docs directory of the Claude edition, and the repository files of
# the Copilot edition that belong to the project (workflows, the instructions
# file). None of them matches a pattern below.
#
# The patterns spell the dot as [.] so that the Copilot build, which rewrites
# every literal Claude-edition directory name in the files it ships, leaves
# them intact.
#
# A trailing CR is ignored, because an editor on Windows adds one.
#
# Exit 0 = nothing found (prints "knowledge neutral: ok"). Exit 1 = lines
# found. Exit 2 = the directory cannot be read. Writes nothing.
set -uo pipefail
export LC_ALL=C

PATTERN='[.]claude/(agents|skills|templates|hooks|checks|tools|knowledge)/|[.]claude/team-manifest[.]json|[.]github/(agents|skills|dream-team)/'

DIR="${1:-}"
if [ -z "$DIR" ] || [ ! -d "$DIR" ] || [ ! -r "$DIR" ]; then
  echo "verify-knowledge-neutral: cannot read directory: ${DIR:-<none>}" >&2
  exit 2
fi

FOUND=0
FILES="$(find "$DIR" -type f 2>/dev/null | sort)" || exit 2

while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    m="$(printf '%s\n' "$line" | grep -o -E "$PATTERN" | head -n 1)"
    if [ -n "$m" ]; then
      echo "$f:$n: names a team path: $m"
      FOUND=1
    fi
  done < "$f"
done <<EOF
$FILES
EOF

if [ "$FOUND" -ne 0 ]; then exit 1; fi
echo "knowledge neutral: ok"
exit 0
