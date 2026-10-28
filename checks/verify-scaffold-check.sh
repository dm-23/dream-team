#!/usr/bin/env bash
# Exercises checks/verify-knowledge-scaffold.sh against scratch project
# directories, and a hand-built scaffold knowledge base against
# checks/verify-knowledge-integrity.sh.
#
#   verify-scaffold-check.sh     (run from anywhere; it locates the team root from its own path)
#
# Each case builds a throwaway project and asserts on the two lines the
# scaffold check prints and on its exit code. Exit 0 = every case passed,
# 1 = at least one failed; each failure names its case.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/checks/verify-knowledge-scaffold.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

BANNER='> SCAFFOLD — written on an empty project on 2026-10-28; nothing here is verified against code. Run /generate-knowledge when the code exists.'

fails=0
fail() { echo "FAIL [$1] $2" >&2; fails=$((fails + 1)); }

project() { local p="$TMP/$1"; mkdir -p "$p/.claude"; printf '%s' "$p"; }
scaffold() { mkdir -p "$1/.claude/knowledge"; printf '%s\n' "$BANNER" > "$1/.claude/knowledge/PROJECT-OVERVIEW.md"; }
generated() { mkdir -p "$1/.claude/knowledge"; printf '# X\n' > "$1/.claude/knowledge/PROJECT-OVERVIEW.md"; }

# run CASE PROJECT -> sets OUT and RC
run() { OUT="$(bash "$CHECK" "$2" "$2/.claude/knowledge" 2>/dev/null)"; RC=$?; }
expect() { # CASE RC LINE1 LINE2
  [ "$RC" = "$2" ] || fail "$1" "exit $RC, expected $2: $OUT"
  [ "$(printf '%s\n' "$OUT" | sed -n 1p)" = "$3" ] || fail "$1" "line 1: $(printf '%s\n' "$OUT" | sed -n 1p), expected: $3"
  [ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "$4" ] || fail "$1" "line 2: $(printf '%s\n' "$OUT" | sed -n 2p), expected: $4"
}

p="$(project empty-absent)"
run empty-absent "$p"; expect empty-absent 0 "project: empty" "knowledge: absent"

p="$(project empty-generated)"; generated "$p"
run empty-generated "$p"; expect empty-generated 0 "project: empty" "knowledge: generated"

p="$(project empty-scaffold)"; scaffold "$p"
run empty-scaffold "$p"; expect empty-scaffold 3 "project: empty" "knowledge: scaffold 2026-10-28"

p="$(project dots-only)"; scaffold "$p"; mkdir -p "$p/.git" "$p/.github/workflows" "$p/.vscode"; : > "$p/.gitignore"
run dots-only "$p"; expect dots-only 3 "project: empty" "knowledge: scaffold 2026-10-28"

p="$(project content-scaffold)"; scaffold "$p"; echo hi > "$p/README.md"
run content-scaffold "$p"; expect content-scaffold 1 "project: has content" "knowledge: scaffold 2026-10-28"

p="$(project empty-dir-content)"; scaffold "$p"; mkdir "$p/src"
run empty-dir-content "$p"; expect empty-dir-content 1 "project: has content" "knowledge: scaffold 2026-10-28"

p="$(project content-generated)"; generated "$p"; echo hi > "$p/README.md"
run content-generated "$p"; expect content-generated 0 "project: has content" "knowledge: generated"

p="$(project crlf-banner)"; scaffold "$p"; printf '%s\r\n# more\r\n' "$BANNER" > "$p/.claude/knowledge/PROJECT-OVERVIEW.md"
run crlf-banner "$p"; expect crlf-banner 3 "project: empty" "knowledge: scaffold 2026-10-28"

p="$(project bom-banner)"; scaffold "$p"; printf '\xEF\xBB\xBF%s\n' "$BANNER" > "$p/.claude/knowledge/PROJECT-OVERVIEW.md"
run bom-banner "$p"; expect bom-banner 3 "project: empty" "knowledge: scaffold 2026-10-28"

run missing-project "$TMP/does-not-exist"
[ "$RC" = 2 ] || fail missing-project "exit $RC, expected 2: $OUT"

if [ "$fails" -eq 0 ]; then echo "verify-scaffold-check: all cases passed"; exit 0; fi
echo "verify-scaffold-check: $fails failure(s)" >&2; exit 1
