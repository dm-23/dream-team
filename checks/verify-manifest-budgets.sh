#!/usr/bin/env bash
# Every knowledge file the team requires must carry a classification, and the
# budget block must define the four defaults. Exit 1 names what is missing.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
m=team-manifest.json
status=0

for key in indexTokens topicTokens wholeFileTokens learningsIndexRowTokens; do
  grep -q "\"$key\"" "$m" || { echo "FAIL: knowledge.budgets.$key missing" >&2; status=1; }
done
grep -q '"classification"' "$m" || { echo "FAIL: knowledge.classification missing" >&2; status=1; }

# Every required file, plus LEARNINGS.md, needs a classification entry.
files=$(sed -n '/"required"/,/]/p' "$m" | grep -oE '[A-Z][A-Z-]*\.md')
for f in $files LEARNINGS.md; do
  sed -n '/"classification"/,/}/p' "$m" | grep -q "\"$f\"" \
    || { echo "FAIL: no classification for $f" >&2; status=1; }
done

[ $status -eq 0 ] && echo "manifest budgets: ok"
exit $status
