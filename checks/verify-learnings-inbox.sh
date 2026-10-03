#!/usr/bin/env bash
# Reports whether a project's learnings inbox needs /generate-knowledge all.
#
#   verify-learnings-inbox.sh <knowledge-dir>
#
# The inbox is LEARNINGS.md, an index, plus one file per entry under
# learnings/. Three things make it due, each against a limit in
# knowledge.budgets of the manifest beside the knowledge dir
# ("$(dirname <knowledge-dir>)/team-manifest.json", the deployed layout):
#
#   - more index rows than learningsIndexMaxRows. The orchestrator reads the
#     index whole on every run, so its length is a cost every run pays.
#   - an entry longer than learningsEntryLines.
#   - an unresolved [PROMOTE] or [STALE-CHECK] mark: a rule or a fact waiting
#     to be written into a knowledge file. The resolved forms carry RESOLVED
#     inside the brackets and do not count.
#
# Entries still inline below the index -- a deployment that fix has not
# migrated -- are measured the same way as entry files.
#
# Fence-aware for the reason checks/verify-knowledge-integrity.sh gives: the
# template documents the entry format, marks included, inside a fenced block
# every deployed LEARNINGS.md carries, and that example is not an entry. An
# unbalanced fence makes every line below it unreadable, so it is exit 2,
# never a guess.
#
# The manifest is read structurally, never with a JSON parser, with the
# scoping and ambiguity rules checks/verify-manifest-budgets.sh explains: a
# key only counts nested under "knowledge", and a manifest with more than one
# block of that name is refused. A manifest that predates the two keys is
# exit 2 as well: a limit that cannot be read is not a limit, and reporting
# the inbox clean against it would be the one wrong answer.
#
# Exit 0 = inbox clean, or no LEARNINGS.md yet. Exit 1 = /generate-knowledge
# all is due; the report says why. Exit 2 = the manifest, a limit or a file
# could not be read. Writes nothing.
set -uo pipefail
export LC_ALL=C

current="${1:?usage: verify-learnings-inbox.sh <knowledge-dir>}"
[ -d "$current" ] || { echo "FAIL: knowledge dir not found: $current" >&2; exit 2; }

manifest="$(dirname "$current")/team-manifest.json"
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

log="$current/LEARNINGS.md"
if [ ! -f "$log" ]; then
  echo "learnings inbox: ok (no LEARNINGS.md yet)"
  exit 0
fi

fence_fail() {
  echo "FAIL: $1 ends inside a fenced block (an odd number of lines starting with three backticks)" >&2
  echo "  Entries cannot be told apart from documentation below an unclosed fence." >&2
  echo "  Balance the fences in that file and run this check again." >&2
  exit 2
}

# Index rows: table lines under "## Index", outside fences, minus the header
# row; separator rows are not counted. Any "## " heading ends the index, an
# inline entry's included.
tr -d '\r' < "$log" | awk '
  /^```/ { fence = !fence; next }
  fence  { next }
  /^## / { inindex = ($0 ~ /^## Index[[:space:]]*$/); next }
  inindex && /^\|/ {
    if ($0 ~ /^\|[-:| ]+$/) next
    rows++
  }
  END { if (fence) exit 2; print (rows > 0 ? rows - 1 : 0) }
' > "$tmp/rows" || fence_fail "$log"

# measure <file> <log|file> <label>: one line per entry,
# "<label>\t<lines>\t<pending marks>". In log mode an entry starts at a
# "## [" heading outside a fence and ends at the next "## " heading; in file
# mode the whole file is one entry. Trailing blank lines are not counted.
measure() {
  tr -d '\r' < "$1" | awk -v mode="$2" -v label="$3" '
    function flush() {
      if (open) {
        while (n > 0 && blank[n]) n--
        printf "%s\t%d\t%d\n", name, n, marks
      }
      open = 0; n = 0; marks = 0
    }
    {
      isfence = ($0 ~ /^```/)
      if (mode == "log" && !fence && !isfence && $0 ~ /^## /) {
        flush()
        if ($0 ~ /^## \[/) { open = 1; name = label ": " $0 }
      }
      if (mode == "file" && NR == 1) { open = 1; name = label }
      if (open) {
        n++
        blank[n] = ($0 ~ /^[[:space:]]*$/)
        if (!fence && !isfence && $0 ~ /^[[:space:]]*(- )?\[(PROMOTE|STALE-CHECK)\]/) marks++
      }
      if (isfence) fence = !fence
    }
    END { flush(); if (fence) exit 2 }
  '
}

: > "$tmp/entries"
measure "$log" log "LEARNINGS.md" >> "$tmp/entries" || fence_fail "$log"
if [ -d "$current/learnings" ]; then
  for f in "$current"/learnings/*.md; do
    [ -e "$f" ] || continue
    measure "$f" file "learnings/$(basename "$f")" >> "$tmp/entries" || fence_fail "$f"
  done
fi

rows="$(cat "$tmp/rows")"
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
  echo "learnings inbox: due -- run /generate-knowledge all"
  exit 1
fi
echo "learnings inbox: ok"
exit 0
