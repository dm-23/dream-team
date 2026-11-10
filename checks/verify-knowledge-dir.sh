#!/usr/bin/env bash
# Tests tools/knowledge-dir.sh against throwaway projects: which directory the
# project knowledge and the operative files resolve to, in a fresh project, a
# legacy one, a half-migrated one, a bad argument, a manifest without a key,
# and a CRLF copy of the manifest.
#
#   bash checks/verify-knowledge-dir.sh    (run from anywhere)
#
# Exit 0 = every case passed. 1 = a case failed; each failure is named.
# Repo-only: it never ships to the Copilot edition, so fixtures spell team
# paths literally.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/knowledge-dir.sh"
MANIFEST="$ROOT/team-manifest.json"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
status=0
case=""
fail() { echo "FAIL [$case]: $*" >&2; status=1; }

[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT is missing" >&2; exit 1; }

n=0
# make_project <manifest-file>: a fresh project with the team under team/.
make_project() {
  n=$((n + 1))
  P="$tmp/p$n"
  mkdir -p "$P/team/tools" "$P/proj"
  cp "$SCRIPT" "$P/team/tools/knowledge-dir.sh"
  cp "${1:-$MANIFEST}" "$P/team/team-manifest.json"
}

# expect <which> <expected-stdout>: run in the project, compare stdout.
expect() {
  local out rc
  out="$(cd "$P/proj" && bash "$P/team/tools/knowledge-dir.sh" "$1" 2>"$tmp/err")"; rc=$?
  [ "$rc" -eq 0 ] || fail "$1: exit $rc, expected 0 ($(cat "$tmp/err"))"
  [ "$out" = "$2" ] || fail "$1: got '$out', expected '$2'"
}
expect_exit2() {
  local rc
  (cd "$P/proj" && bash "$P/team/tools/knowledge-dir.sh" "$1" >/dev/null 2>"$tmp/err"); rc=$?
  [ "$rc" -eq 2 ] || fail "$1: exit $rc, expected 2"
  [ -s "$tmp/err" ] || fail "$1: nothing written to stderr"
}

NEW=".dream-team/knowledge"
OLD=".claude/knowledge"
OPS=".dream-team-tracking/operative"

case="nothing"
make_project
expect project "$NEW"
expect operative "$OPS"

case="legacy with project files and learnings"
make_project
mkdir -p "$P/proj/$OLD"
echo x > "$P/proj/$OLD/PROJECT-OVERVIEW.md"; echo x > "$P/proj/$OLD/LEARNINGS.md"
expect project "$OLD"
expect operative "$OLD"

case="legacy with only LEARNINGS.md"
make_project
mkdir -p "$P/proj/$OLD"
echo x > "$P/proj/$OLD/LEARNINGS.md"; echo x > "$P/proj/$OLD/CAPABILITIES.md"
expect project "$NEW"
expect operative "$OLD"

case="legacy with project files plus the new directory"
make_project
mkdir -p "$P/proj/$OLD" "$P/proj/$NEW"
echo x > "$P/proj/$OLD/PROJECT-OVERVIEW.md"; echo x > "$P/proj/$OLD/LEARNINGS.md"
expect project "$NEW"
expect operative "$OLD"

case="legacy learnings plus the operative directory"
make_project
mkdir -p "$P/proj/$OLD" "$P/proj/$OPS"
echo x > "$P/proj/$OLD/LEARNINGS.md"
expect operative "$OPS"

case="legacy project files without LEARNINGS.md"
make_project
mkdir -p "$P/proj/$OLD"
echo x > "$P/proj/$OLD/TOOLCHAIN.md"
expect project "$OLD"
expect operative "$OPS"

case="bad argument"
make_project
expect_exit2 bogus
expect_exit2 ""

case="manifest without operativeDir"
grep -v '"operativeDir"' "$MANIFEST" > "$tmp/no-operative.json"
make_project "$tmp/no-operative.json"
expect_exit2 operative

case="missing manifest"
make_project
rm "$P/team/team-manifest.json"
expect_exit2 project

case="CRLF manifest"
sed 's/$/\r/' "$MANIFEST" > "$tmp/crlf.json"
make_project "$tmp/crlf.json"
expect project "$NEW"
expect operative "$OPS"
mkdir -p "$P/proj/$OLD"
echo x > "$P/proj/$OLD/PROJECT-OVERVIEW.md"; echo x > "$P/proj/$OLD/LEARNINGS.md"
expect project "$OLD"
expect operative "$OLD"

[ "$status" -eq 0 ] && echo "knowledge dir: ok"
exit "$status"
