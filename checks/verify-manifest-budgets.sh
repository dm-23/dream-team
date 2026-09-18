#!/usr/bin/env bash
# Every knowledge file the team requires must carry a classification, and the
# budget block must define the keys the instruction files name. Exit 1 names
# what is missing.
#
#   verify-manifest-budgets.sh          (run from anywhere; it locates the
#                                        team root from its own path)
#
# The manifest is read structurally -- brace and bracket counting -- and never
# with a JSON parser, because this is a fixed bash/awk/sed/grep toolchain
# check. Two rules follow checks/verify-knowledge-integrity.sh, which was
# hardened for exactly this and whose reasoning applies here unchanged:
#
#   - Scope. A key only counts where it is nested under "knowledge". Nothing
#     stops an unrelated top-level key from carrying its own "classification"
#     or "budgets" object, and a file-wide search that took the first match
#     would report "ok" over a manifest whose knowledge block has neither.
#   - Refuse, do not guess. If the manifest is ambiguous about a key -- more
#     than one block of that name anywhere in it -- this exits 1 and says so.
#     Choosing among candidates in the manifest is the same defect these
#     checks exist to catch, one level up, in their own input.
#
# Both rules are needed. Scoping alone would still accept the single block
# that exists when it happens to sit outside "knowledge"; the ambiguity count
# alone would not know which of several candidates is the real one.
set -uo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.." || exit 1
m=team-manifest.json
[ -f "$m" ] || { echo "FAIL: $m not found beside $(pwd)" >&2; exit 1; }

status=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Count occurrences of a JSON `"key": {` or `"key": [` opening in a file.
# The opening character is passed bare and the regex escape is added inside
# awk, so no argument ever carries a backslash escape that one awk reads and
# another warns about.
count_key_blocks() {
  awk -v key="$1" -v openchar="$2" '
    { n = gsub("\"" key "\"[[:space:]]*:[[:space:]]*\\" openchar, "&"); total += n }
    END { print total + 0 }
  ' "$3"
}

# Extract the raw text strictly between a named key's opening bracket and its
# matching closing one, by depth. Callers must first confirm with
# count_key_blocks that exactly one such key exists in the input.
extract_key_block() {
  awk -v key="$1" -v openchar="$2" -v closechar="$3" '
    BEGIN { found = 0; level = 0 }
    !found && $0 ~ ("\"" key "\"[[:space:]]*:[[:space:]]*\\" openchar) {
      found = 1; level = 1; next
    }
    found && level > 0 {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == openchar) level++
        else if (c == closechar) { level--; if (level == 0) exit }
      }
      print
    }
  ' "$4"
}

knowledge_blocks="$(count_key_blocks knowledge "{" "$m")"
if [ "$knowledge_blocks" -ne 1 ]; then
  echo "FAIL: $m defines $knowledge_blocks \"knowledge\" blocks, expected exactly 1" >&2
  exit 1
fi
extract_key_block knowledge "{" "}" "$m" > "$tmp/knowledge-block"

# Extracts knowledge.<key> into "$tmp/<key>-block", refusing an ambiguous or
# unscoped manifest. $2/$3 are the bracket pair the key opens.
extract_scoped() {
  local key="$1" openchar="$2" closechar="$3" total inside

  total="$(count_key_blocks "$key" "$openchar" "$m")"
  if [ "$total" -ne 1 ]; then
    echo "FAIL: $m defines $total \"$key\" blocks; refusing to guess which one is knowledge.$key" >&2
    exit 1
  fi

  inside="$(count_key_blocks "$key" "$openchar" "$tmp/knowledge-block")"
  if [ "$inside" -ne 1 ]; then
    echo "FAIL: no \"$key\" block found nested under \"knowledge\" in $m" >&2
    exit 1
  fi

  extract_key_block "$key" "$openchar" "$closechar" "$tmp/knowledge-block" > "$tmp/$key-block"
}

extract_scoped budgets "{" "}"
extract_scoped classification "{" "}"
extract_scoped required "[" "]"

# The budget keys the skills and the instruction files name. Every number the
# team applies lives here; an instruction file names the key, never the value,
# so a key missing from the manifest leaves a rule with nothing behind it.
for key in indexTokens topicTokens wholeFileTokens \
           learningsIndexRowTokens learningsIndexRowTitleChars learningsIndexRowMaxTags; do
  grep -q "\"$key\"" "$tmp/budgets-block" \
    || { echo "FAIL: knowledge.budgets.$key missing" >&2; status=1; }
done

if [ ! -s "$tmp/classification-block" ]; then
  echo "FAIL: knowledge.classification is empty" >&2
  status=1
fi

# Every required file, plus the persistent learnings log, needs a class.
sed -n 's/.*"\([^"]*\.md\)".*/\1/p' "$tmp/required-block" > "$tmp/required-files"
if [ ! -s "$tmp/required-files" ]; then
  echo "FAIL: knowledge.required lists no files" >&2
  status=1
fi

while read -r f; do
  [ -n "$f" ] || continue
  grep -q "\"$f\"" "$tmp/classification-block" \
    || { echo "FAIL: no classification for $f" >&2; status=1; }
done < "$tmp/required-files"

grep -q '"LEARNINGS.md"' "$tmp/classification-block" \
  || { echo "FAIL: no classification for LEARNINGS.md" >&2; status=1; }

[ $status -eq 0 ] && echo "manifest budgets: ok"
exit $status
