#!/usr/bin/env bash
# Repo-only test of checks/verify-knowledge-neutral.sh. It may name team paths
# of both editions in its fixtures; the runtime check it tests may not ship
# them literally, so this test never ships.
#
#   verify-neutral-check.sh
#
# Exit 0 = every case behaved as expected. Exit 1 = a case failed.
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/verify-knowledge-neutral.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/neutral-check.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

FAILS=0
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# run_case <name> <expected-exit> <expected-output-fragment or ""> <dir>
run_case() {
  local name="$1" want="$2" frag="$3" dir="$4" out rc
  out="$(bash "$CHECK" "$dir" 2>&1)"; rc=$?
  [ "$rc" = "$want" ] || fail "$name: exit $rc, wanted $want ($out)"
  if [ -n "$frag" ]; then
    case "$out" in *"$frag"*) ;; *) fail "$name: output lacks '$frag' ($out)";; esac
  fi
}

mk() { rm -rf "$WORK/k"; mkdir -p "$WORK/k"; }

mk; printf '%s\n' '- source: .claude/PROJECT.md:12' > "$WORK/k/a.md"
run_case "project document" 0 "knowledge neutral: ok" "$WORK/k"

mk; printf '%s\n' '- see .claude/docs/guide.md' > "$WORK/k/a.md"
run_case "docs dir" 0 "" "$WORK/k"

mk; printf '%s\n' 'CI: .github/workflows/build.yml and .github/copilot-instructions.md' > "$WORK/k/a.md"
run_case "workflows" 0 "" "$WORK/k"

mk; printf '%s\n' 'see .claude/knowledge/TOOLCHAIN.md' > "$WORK/k/a.md"
run_case "claude knowledge" 1 "a.md:1: names a team path: .claude/knowledge/" "$WORK/k"

mk; mkdir -p "$WORK/k/backend-architecture"
printf '%s\n' 'ok line' 'read .github/dream-team/templates/x.md' > "$WORK/k/backend-architecture/a.md"
run_case "topic file" 1 "backend-architecture/a.md:2: names a team path: .github/dream-team/" "$WORK/k"

mk; printf '%s\r\n' '.claude/skills/x' > "$WORK/k/a.md"
run_case "crlf" 1 "names a team path" "$WORK/k"

mk; printf '%s\n' 'see .claude/team-manifest.json' > "$WORK/k/a.md"
run_case "manifest" 1 "" "$WORK/k"

mk; printf '%s\n' 'see .github/agents/x.agent.md' > "$WORK/k/a.md"
run_case "github agents" 1 "" "$WORK/k"

mk; printf '%s\n' 'see .claude/tools/x.sh and .github/skills/y' > "$WORK/k/a.md"
run_case "two on a line, the first is named" 1 "a.md:1: names a team path: .claude/tools/" "$WORK/k"
out="$(bash "$CHECK" "$WORK/k" 2>&1)"
[ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] || fail "two on a line: more than one report line ($out)"

mk; printf 'ok line\nsee .claude/hooks/x' > "$WORK/k/a.md"
run_case "last line without a newline" 1 "a.md:2: names a team path: .claude/hooks/" "$WORK/k"

mk; printf '%s\n' 'ok' 'see .claude/checks/x' > "$WORK/k/b file.md"
printf '%s\n' 'see .claude/agents/x' 'ok' 'see .github/dream-team/tools/y' > "$WORK/k/a.md"
out="$(bash "$CHECK" "$WORK/k" 2>&1)"; rc=$?
want="$WORK/k/a.md:1: names a team path: .claude/agents/
$WORK/k/a.md:3: names a team path: .github/dream-team/
$WORK/k/b file.md:2: names a team path: .claude/checks/"
[ "$rc" = 1 ] && [ "$out" = "$want" ] || fail "several files, in order, a space in a name: exit $rc ($out)"

mk; printf 'a\000b .claude/skills/x\n' > "$WORK/k/a.md"
run_case "a NUL byte in the file" 1 "a.md:1: names a team path: .claude/skills/" "$WORK/k"

# Size: one search per file, never a process per line. 4000 lines took minutes
# on Git Bash when every line started its own pipeline.
mk; i=0; while [ "$i" -lt 4000 ]; do echo "- line $i of an ordinary knowledge file"; i=$((i + 1)); done > "$WORK/k/a.md"
echo 'see .claude/templates/x' >> "$WORK/k/a.md"
start="$(date +%s)"
run_case "4000 lines" 1 "a.md:4001: names a team path: .claude/templates/" "$WORK/k"
took=$(( $(date +%s) - start ))
[ "$took" -le 20 ] || fail "4000 lines took ${took}s, wanted 20s at most"

run_case "missing dir" 2 "" "$WORK/does-not-exist"

if [ "$FAILS" -gt 0 ]; then exit 1; fi
echo "neutral check: ok"
