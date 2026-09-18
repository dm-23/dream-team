#!/usr/bin/env bash
# Every knowledge file the team requires must carry a classification, and the
# budget block must define the four defaults. Exit 1 names what is missing.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
m=team-manifest.json
status=0

# Function to extract a JSON block (object or array) by its key
# Properly scoped by counting braces/brackets to find the matching close
extract_block() {
  local key=$1
  local open_char=$2  # { or [
  local close_char=$3 # } or ]

  awk -v k="$key" -v openchar="$open_char" -v closechar="$close_char" '
    BEGIN { found = 0; level = 0 }
    !found && /"'"$key"'"\s*:\s*'"$open_char"'/ {
      found = 1
      print
      level = 1
      next
    }
    found && level > 0 {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == openchar) level++
        else if (c == closechar) level--
      }
      print
      if (level == 0) exit
    }
  ' "$m"
}

# Extract the required blocks from their proper locations in the manifest
# Note: [ and ] need to be passed as-is; they're interpreted in the awk regex within the function
budgets=$(extract_block "budgets" "{" "}")
classification=$(extract_block "classification" "{" "}")
required=$(extract_block "required" "\[" "\]")

# Check budget keys only within the budgets block
for key in indexTokens topicTokens wholeFileTokens learningsIndexRowTokens; do
  echo "$budgets" | grep -q "\"$key\"" || { echo "FAIL: knowledge.budgets.$key missing" >&2; status=1; }
done

# Check classification block exists
if [ -z "$classification" ]; then
  echo "FAIL: knowledge.classification missing" >&2
  status=1
fi

# Extract file list from the required array only (not any other "required" in the manifest)
files=$(echo "$required" | grep -oE '[A-Z][A-Z-]*\.md')

# Check each file has a classification entry
for f in $files LEARNINGS.md; do
  echo "$classification" | grep -q "\"$f\"" \
    || { echo "FAIL: no classification for $f" >&2; status=1; }
done

[ $status -eq 0 ] && echo "manifest budgets: ok"
exit $status
