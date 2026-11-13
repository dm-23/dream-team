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
# A trailing CR is ignored, because an editor on Windows adds one. A line
# that names several team paths is reported once, with the first of them.
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
  # One search per file, never a process per line: starting a pipeline for
  # every line took minutes on a few thousand lines under Git Bash. grep
  # prints "<line>:<match>" once per match; the first match of a line is the
  # one reported. No pattern can match a CR, so a trailing one needs no care.
  hits="$(grep -a -n -o -E -- "$PATTERN" "$f" | F="$f" awk '
    { i = index($0, ":"); n = substr($0, 1, i - 1)
      if (n in seen) next
      seen[n] = 1
      print ENVIRON["F"] ":" n ": names a team path: " substr($0, i + 1) }')"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    FOUND=1
  fi
done <<EOF
$FILES
EOF

if [ "$FOUND" -ne 0 ]; then exit 1; fi
echo "knowledge neutral: ok"
exit 0
