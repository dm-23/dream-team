#!/usr/bin/env bash
# Reports whether a project's remarks need /generate-knowledge.
#
#   verify-learnings-inbox.sh <remarks-dir>
#
# The remarks dir (the proposals directory inside the knowledge, or inside the
# operative dir while the knowledge is a legacy private copy; `bash
# tools/knowledge-dir.sh remarks` prints it) holds one file per remark,
# directly inside it: *.md. Its index is not a file: knowledge.learningsIndex
# prints it from the entry files, one row per entry. Three things make the
# remarks due, each against a limit in knowledge.budgets of the manifest beside
# the checks directory ("$(dirname "$0")/../team-manifest.json": the team root,
# which holds the checks and the manifest in a deployment, wherever the remarks
# themselves live):
#
#   - more index rows than learningsIndexMaxRows. The orchestrator reads the
#     index whole on every run, so its length is a cost every run pays. The
#     rows are the entry files.
#   - an entry longer than learningsEntryLines.
#   - an unresolved [PROMOTE] or [STALE-CHECK] mark: a rule or a fact waiting
#     to be written into a knowledge file. The resolved forms carry RESOLVED
#     inside the brackets and do not count. An entry whose body is an
#     [EXCEPTION] line carries no such mark: it counts as an index row only.
#
# Fence-aware for the reason checks/verify-knowledge-integrity.sh gives: an
# entry may document the entry format, marks included, inside a fenced block,
# and that example is not a mark. An unbalanced fence makes every line below it
# unreadable, so it is exit 2, never a guess.
#
# The manifest is read structurally, never with a JSON parser, with the
# scoping and ambiguity rules checks/verify-manifest-budgets.sh explains: a
# key only counts nested under "knowledge", and a manifest with more than one
# block of that name is refused. A manifest that predates the two keys is
# exit 2 as well: a limit that cannot be read is not a limit, and reporting
# the remarks clean against it would be the one wrong answer.
#
# Exit 0 = remarks clean, no entries yet, or no such directory. Exit 1 =
# /generate-knowledge all is due; the report says why. Exit 2 = the manifest,
# a limit or a file could not be read. Writes nothing.
set -uo pipefail
export LC_ALL=C

current="${1:?usage: verify-learnings-inbox.sh <remarks-dir>}"
# No directory is no remarks: nothing has been accepted yet.
[ -d "$current" ] || { echo "learnings inbox: ok (no entries yet)"; exit 0; }

manifest="$(cd "$(dirname "$0")/.." && pwd)/team-manifest.json"
[ -f "$manifest" ] || { echo "FAIL: manifest not found at $manifest (needed to read knowledge.budgets)" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Count occurrences of a JSON `"key": {` opening in a file.
count_key_blocks() {
  awk -v key="$1" '
    { n = gsub("\"" key "\"[[:space:]]*:[[:space:]]*\\{", "&"); total += n }
    END { print total + 0 }
  ' "$2"
}

# Extract the raw text strictly between a named key's opening { and its
# matching closing }, by brace depth. Callers confirm first that exactly one
# such key exists.
extract_key_block() {
  awk -v key="$1" '
    BEGIN { found = 0; level = 0 }
    !found && $0 ~ ("\"" key "\"[[:space:]]*:[[:space:]]*\\{") {
      found = 1; level = 1; next
    }
    found && level > 0 {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "{") level++
        else if (c == "}") { level--; if (level == 0) exit }
      }
      print
    }
  ' "$2"
}

n="$(count_key_blocks knowledge "$manifest")"
[ "$n" -eq 1 ] || { echo "FAIL: $manifest defines $n \"knowledge\" blocks, expected exactly 1" >&2; exit 2; }
extract_key_block knowledge "$manifest" > "$tmp/knowledge-block"

n="$(count_key_blocks budgets "$manifest")"
[ "$n" -eq 1 ] || { echo "FAIL: $manifest defines $n \"budgets\" blocks; refusing to guess which one is knowledge.budgets" >&2; exit 2; }
n="$(count_key_blocks budgets "$tmp/knowledge-block")"
[ "$n" -eq 1 ] || { echo "FAIL: no \"budgets\" block nested under \"knowledge\" in $manifest" >&2; exit 2; }
extract_key_block budgets "$tmp/knowledge-block" > "$tmp/budgets-block"

# Prints knowledge.budgets.<key>, or exits 2 when it is absent, repeated or
# not a plain number.
read_budget() {
  local v
  v="$(sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$tmp/budgets-block")"
  case "$v" in
    ''|*[!0-9]*)
      echo "FAIL: knowledge.budgets.$1 is missing, repeated or not a number in $manifest" >&2
      echo "  A manifest older than this check has no such key: update the team, then run again." >&2
      exit 2 ;;
  esac
  echo "$v"
}
max_rows="$(read_budget learningsIndexMaxRows)" || exit 2
max_lines="$(read_budget learningsEntryLines)" || exit 2

nfiles=0
for f in "$current"/*.md; do [ -f "$f" ] && nfiles=$((nfiles + 1)); done
if [ "$nfiles" -eq 0 ]; then
  echo "learnings inbox: ok (no entries yet)"
  exit 0
fi

fence_fail() {
  echo "FAIL: $1 ends inside a fenced block (an odd number of lines starting with three backticks)" >&2
  echo "  Entries cannot be told apart from documentation below an unclosed fence." >&2
  echo "  Balance the fences in that file and run this check again." >&2
  exit 2
}

# measure <file> <label>: one line, "<label>\t<lines>\t<pending marks>". The
# whole file is one entry. Trailing blank lines are not counted.
measure() {
  tr -d '\r' < "$1" | awk -v label="$2" '
    {
      isfence = ($0 ~ /^```/)
      n++
      blank[n] = ($0 ~ /^[[:space:]]*$/)
      if (!fence && !isfence && $0 ~ /^[[:space:]]*(- )?\[(PROMOTE|STALE-CHECK)\]/) marks++
      if (isfence) fence = !fence
    }
    END {
      if (fence) exit 2
      while (n > 0 && blank[n]) n--
      printf "%s\t%d\t%d\n", label, n, marks + 0
    }
  '
}

: > "$tmp/entries"
for f in "$current"/*.md; do
  [ -f "$f" ] || continue
  measure "$f" "$(basename "$f")" >> "$tmp/entries" || fence_fail "$f"
done

# One index row per entry file.
rows="$nfiles"
entries="$(wc -l < "$tmp/entries" | tr -d ' ')"
awk -F'\t' -v max="$max_lines" '$2 > max' "$tmp/entries" > "$tmp/long"
long="$(wc -l < "$tmp/long" | tr -d ' ')"
marks="$(awk -F'\t' '{ s += $3 } END { print s + 0 }' "$tmp/entries")"
marked="$(awk -F'\t' '$3 > 0' "$tmp/entries" | wc -l | tr -d ' ')"

echo "learnings inbox: $rows index rows (max $max_rows), $entries entries, $marks pending marks"
due=0
if [ "$rows" -gt "$max_rows" ]; then
  echo "  over: the index has $rows rows, the budget is $max_rows"
  due=1
fi
if [ "$long" -gt 0 ]; then
  echo "  over: $long entries longer than $max_lines lines:"
  awk -F'\t' '{ printf "    %s (%d lines)\n", $1, $2 }' "$tmp/long"
  due=1
fi
if [ "$marks" -gt 0 ]; then
  echo "  pending: $marks unresolved [PROMOTE] / [STALE-CHECK] marks in $marked entries"
  due=1
fi
if [ "$due" -eq 1 ]; then
  echo "learnings inbox: due -- run /generate-knowledge"
  exit 1
fi
echo "learnings inbox: ok"
exit 0
