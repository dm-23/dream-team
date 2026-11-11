#!/usr/bin/env bash
# Reports project knowledge whose shape is wrong.
#
#   verify-knowledge-shape.sh <knowledge-dir>
#
# Rules a person authored live one per file under <knowledge-dir>/rules/ (the
# format is templates/rule.md). This check holds three things:
#
#   - Each rules/*.md, read directly inside rules/ and never deeper, starts
#     with a "# " title line; holds exactly one "- Kind:" line whose value is
#     rule, critical-zone or exception; holds the field its kind requires
#     ("- Rule:", "- Zone:" or "- Exception:"); holds "- Source:" and
#     "- Added:"; and has at most ruleMaxLines lines. Lines are counted after
#     a trailing CR is stripped, and a last line without a newline counts.
#   - rules/ holds at most rulesMaxFiles files.
#   - No *.md outside rules/ and proposals/, topic directories included, holds
#     an authored line in a generated file: a line that contains
#     "— source: learnings " or ends "— source: user". Authored text belongs in
#     rules/; a generated file is rewritten and must not carry it.
#   - Only when <knowledge-dir>/BASELINE exists (knowledge.baselineFile: a
#     refresh wrote it, so the knowledge claims to be verified against a
#     commit): BASELINE holds a "commit=" line of 40 hex digits, a "date=" line
#     of the form YYYY-MM-DD and a non-empty "branch=" line; every *.md outside
#     rules/ and proposals/ has a "Covers:" line within its first five lines
#     (after the scaffold banner, when it has one); and every pattern such a
#     line lists, unless it reads "conventions" or "topics", matches at least
#     one path git tracks in the repository that holds <knowledge-dir>
#     (git ls-files -- ':(top,glob)<pattern>'), and holds no backslash: a
#     pattern names paths with "/", and a backslash is an escape to git, a
#     Windows separator to whoever wrote it. tools/knowledge-drift.sh reads
#     the same lines.
#
# The budgets rulesMaxFiles and ruleMaxLines are read from knowledge.budgets of
# the manifest beside the checks directory ("$(dirname "$0")/../team-manifest.json"),
# structurally, never with a JSON parser, with the scoping and ambiguity rules
# checks/verify-manifest-budgets.sh explains. They are read only when rules/
# exists. A knowledge directory without rules/ passes that part.
#
# A trailing CR is ignored, because an editor on Windows adds one.
#
# A defect is reported as
#   <path>: <what is wrong>
#   <path>:<line>: authored line in a generated file
#   rules: <N> files, the budget is <M>
#   <path>/BASELINE: no "commit=" line of 40 hex digits   (and date=, branch=)
#   <path>: no "Covers:" line in its first five lines
#   <path>: pattern matches nothing: <pattern>
#   <path>: pattern has a backslash: <pattern>
#   <knowledge-dir>: not inside a git repository, so no Covers pattern can be checked
#
# Exit 0 = in shape (prints "knowledge shape: ok"). Exit 1 = defects listed.
# Exit 2 = the directory, the manifest or a budget cannot be read. Writes
# nothing.
set -uo pipefail
export LC_ALL=C

DIR="${1:-}"
if [ -z "$DIR" ] || [ ! -d "$DIR" ] || [ ! -r "$DIR" ]; then
  echo "verify-knowledge-shape: cannot read directory: ${DIR:-<none>}" >&2
  exit 2
fi
DIR="${DIR%/}"

FOUND=0
tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT

# --- rules/ --------------------------------------------------------------------
if [ -d "$DIR/rules" ]; then
  manifest="$(cd "$(dirname "$0")/.." && pwd)/team-manifest.json"
  [ -f "$manifest" ] || { echo "FAIL: manifest not found at $manifest (needed to read knowledge.budgets)" >&2; exit 2; }
  tr -d '\r' < "$manifest" > "$tmp/manifest"

  count_key_blocks() {
    awk -v key="$1" '
      { n = gsub("\"" key "\"[[:space:]]*:[[:space:]]*\\{", "&"); total += n }
      END { print total + 0 }
    ' "$2"
  }
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

  n="$(count_key_blocks knowledge "$tmp/manifest")"
  [ "$n" -eq 1 ] || { echo "FAIL: $manifest defines $n \"knowledge\" blocks, expected exactly 1" >&2; exit 2; }
  extract_key_block knowledge "$tmp/manifest" > "$tmp/knowledge-block"
  n="$(count_key_blocks budgets "$tmp/manifest")"
  [ "$n" -eq 1 ] || { echo "FAIL: $manifest defines $n \"budgets\" blocks; refusing to guess which one is knowledge.budgets" >&2; exit 2; }
  n="$(count_key_blocks budgets "$tmp/knowledge-block")"
  [ "$n" -eq 1 ] || { echo "FAIL: no \"budgets\" block nested under \"knowledge\" in $manifest" >&2; exit 2; }
  extract_key_block budgets "$tmp/knowledge-block" > "$tmp/budgets-block"

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
  max_files="$(read_budget rulesMaxFiles)" || exit 2
  max_lines="$(read_budget ruleMaxLines)" || exit 2

  files="$(find "$DIR/rules" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)" || exit 2
  count=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    count=$((count + 1))
    out="$(awk -v path="$f" -v maxlines="$max_lines" '
      { sub(/\r$/, "") }
      NR == 1 { first = $0 }
      /^- Kind:/ { kinds++; kind = $0; sub(/^- Kind:[ \t]*/, "", kind); sub(/[ \t]+$/, "", kind) }
      /^- Rule:/ { has["rule"] = 1 }
      /^- Zone:/ { has["critical-zone"] = 1 }
      /^- Exception:/ { has["exception"] = 1 }
      /^- Source:/ { source = 1 }
      /^- Added:/ { added = 1 }
      END {
        if (substr(first, 1, 2) != "# ") print path ": the first line is not a title starting with \"# \""
        if (kinds != 1) print path ": \"- Kind:\" must appear exactly once, found " kinds + 0
        else if (kind != "rule" && kind != "critical-zone" && kind != "exception") print path ": \"- Kind:\" is not rule, critical-zone or exception: " kind
        else if (!(kind in has)) {
          field = (kind == "rule") ? "- Rule:" : (kind == "critical-zone") ? "- Zone:" : "- Exception:"
          print path ": kind " kind " requires \"" field "\""
        }
        if (!source) print path ": no \"- Source:\" line"
        if (!added) print path ": no \"- Added:\" line"
        if (NR > maxlines) print path ": " NR " lines, the budget is " maxlines
      }
    ' "$f")"
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
      FOUND=1
    fi
  done <<EOF
$files
EOF
  if [ "$count" -gt "$max_files" ]; then
    echo "rules: $count files, the budget is $max_files"
    FOUND=1
  fi
fi

# --- authored lines outside rules/ and proposals/ -------------------------------
FILES="$(find "$DIR" \( -path "$DIR/rules" -o -path "$DIR/proposals" \) -prune -o -type f -name '*.md' -print 2>/dev/null | sort)" || exit 2
while IFS= read -r f; do
  [ -n "$f" ] || continue
  out="$(awk -v path="$f" -v mid="— source: learnings " -v tail="— source: user" '
    { sub(/\r$/, "") }
    index($0, mid) > 0 || (length($0) >= length(tail) && substr($0, length($0) - length(tail) + 1) == tail) {
      print path ":" NR ": authored line in a generated file"
    }
  ' "$f")"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    FOUND=1
  fi
done <<EOF
$FILES
EOF

# --- BASELINE and the Covers lines ---------------------------------------------
if [ -f "$DIR/BASELINE" ]; then
  BOM="$(printf '\357\273\277')"
  out="$(awk -v path="$DIR/BASELINE" -v bom="$BOM" '
    { sub(/\r$/, "") }
    NR == 1 && index($0, bom) == 1 { $0 = substr($0, 4) }
    /^commit=[0-9a-fA-F]+$/ && length($0) == 47 { c = 1 }
    /^date=[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { d = 1 }
    /^branch=./ { b = 1 }
    END {
      if (!c) print path ": no \"commit=\" line of 40 hex digits"
      if (!d) print path ": no \"date=\" line of the form YYYY-MM-DD"
      if (!b) print path ": no \"branch=\" line"
    }
  ' "$DIR/BASELINE")"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    FOUND=1
  fi

  INREPO=0
  [ "$(git -C "$DIR" rev-parse --is-inside-work-tree 2>/dev/null | tr -d '\r')" = true ] && INREPO=1
  NOREPO_SAID=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # One line: the patterns, one per tab, "-" for no Covers: line, "=" for
    # conventions or topics.
    covers="$(awk -v bom="$BOM" -v banner="> SCAFFOLD — " '
      { sub(/\r$/, "") }
      NR == 1 {
        if (index($0, bom) == 1) $0 = substr($0, 4)
        start = (index($0, banner) == 1) ? 2 : 1
      }
      NR >= start && NR < start + 5 && index($0, "Covers:") == 1 {
        v = substr($0, 8); gsub(/^[ \t]+|[ \t]+$/, "", v)
        if (v == "conventions" || v == "topics") { print "="; found = 1; exit }
        n = split(v, parts, ","); s = ""
        for (i = 1; i <= n; i++) {
          q = parts[i]; gsub(/^[ \t]+|[ \t]+$/, "", q)
          if (q != "") s = s ((s == "") ? "" : "\t") q
        }
        print s; found = 1; exit
      }
      END { if (!found) print "-" }
    ' "$f")"
    case "$covers" in
      -) echo "$f: no \"Covers:\" line in its first five lines"; FOUND=1; continue ;;
      =) continue ;;
      "") echo "$f: \"Covers:\" lists no pattern"; FOUND=1; continue ;;
    esac
    if [ "$INREPO" -ne 1 ]; then
      if [ "$NOREPO_SAID" -eq 0 ]; then
        echo "$DIR: not inside a git repository, so no Covers pattern can be checked"
        NOREPO_SAID=1; FOUND=1
      fi
      continue
    fi
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      case "$p" in
        *'\'*) echo "$f: pattern has a backslash: $p"; FOUND=1; continue ;;
      esac
      if [ -z "$(git -C "$DIR" ls-files -- ":(top,glob)$p" 2>/dev/null | head -n 1)" ]; then
        echo "$f: pattern matches nothing: $p"
        FOUND=1
      fi
    done <<EOF
$(printf '%s\n' "$covers" | tr '\t' '\n')
EOF
  done <<EOF
$FILES
EOF
fi

if [ "$FOUND" -ne 0 ]; then exit 1; fi
echo "knowledge shape: ok"
