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

# --- runtime checks: they find the manifest beside themselves --------------------
# The team lives at <proj>/.claude/ and the knowledge at <proj>/.dream-team/
# knowledge, so no manifest sits beside the knowledge directory.
INBOX="$ROOT/checks/verify-learnings-inbox.sh"
INTEGRITY="$ROOT/checks/verify-knowledge-integrity.sh"

make_runtime() {
  n=$((n + 1))
  P="$tmp/r$n"
  mkdir -p "$P/proj/.claude/checks" "$P/proj/.dream-team/knowledge" "$P/proj/.dream-team-tracking/operative/learnings"
  cp "$INBOX" "$INTEGRITY" "$P/proj/.claude/checks/"
  cp "$MANIFEST" "$P/proj/.claude/team-manifest.json"
  OPD="$P/proj/.dream-team-tracking/operative"
}
# write_index <dir> <rows>: a LEARNINGS.md with that many index rows.
write_index() {
  { printf '# Inbox\n\n## Index\n\n| Date | Title | Tags |\n|------|-------|------|\n'
    local i=1
    while [ "$i" -le "$2" ]; do printf '| 2026-01-01 | t%s | x |\n' "$i"; i=$((i + 1)); done
  } > "$1/LEARNINGS.md"
}
rt_expect() { # <label> <expected-rc> <args...>: run a runtime check from the team dir
  local label="$1" want="$2" script="$3" rc; shift 3
  (cd "$P/proj" && bash ".claude/checks/$script" "$@" >"$tmp/out" 2>"$tmp/err"); rc=$?
  [ "$rc" -eq "$want" ] || fail "$label: exit $rc, expected $want ($(head -c 300 "$tmp/err"))"
}

case="runtime inbox over the row budget"
make_runtime
write_index "$OPD" 31
rt_expect "31 rows" 1 verify-learnings-inbox.sh "$OPD"

case="runtime inbox within budget"
make_runtime
write_index "$OPD" 3
rt_expect "3 rows" 0 verify-learnings-inbox.sh "$OPD"

case="runtime integrity on an operative pair"
make_runtime
write_index "$OPD" 3
cp -r "$OPD" "$P/backup"
rt_expect "operative pair" 0 verify-knowledge-integrity.sh "$P/backup" "$OPD"

case="runtime integrity on project files without LEARNINGS.md"
make_runtime
K="$P/proj/.dream-team/knowledge"
for f in PROJECT-OVERVIEW TESTING-CONVENTIONS SEARCH-PLAYBOOK TOOLCHAIN REVIEW-CHECKLIST PROJECT-RULES \
         BACKEND-ARCHITECTURE FRONTEND-ARCHITECTURE DI-AND-STARTUP CODING-STANDARDS; do
  printf '# %s\n' "$f" > "$K/$f.md"
done
cp -r "$K" "$P/backup"
rt_expect "project pair" 0 verify-knowledge-integrity.sh "$P/backup" "$K"

case="runtime integrity still fails a file missing from the current dir"
make_runtime
K="$P/proj/.dream-team/knowledge"
printf '# x\n' > "$K/BACKEND-ARCHITECTURE.md"
cp -r "$K" "$P/backup"
rm "$K/BACKEND-ARCHITECTURE.md"
rt_expect "missing file" 1 verify-knowledge-integrity.sh "$P/backup" "$K"

case="runtime integrity still fails an unclassified file"
make_runtime
K="$P/proj/.dream-team/knowledge"
cp -r "$K" "$P/backup"
printf '# x\n' > "$K/STRAY.md"
rt_expect "unclassified" 1 verify-knowledge-integrity.sh "$P/backup" "$K"

# make_operative_state: an inbox with one entry file, beside the machine state
# an operative dir also holds (an edition's capabilities, a legacy backup).
make_operative_state() {
  write_index "$OPD" 1
  printf '## [2026-01-01] t1\n- Fix pattern: x\n' > "$OPD/learnings/2026-01-01-t1.md"
  mkdir -p "$OPD/claude" "$OPD/legacy-knowledge-x"
  printf '# Capabilities\n' > "$OPD/claude/CAPABILITIES.md"
  printf '# old\n' > "$OPD/legacy-knowledge-x/PROJECT-OVERVIEW.md"
}

case="runtime integrity with inbox ignores the operative dir's other entries"
make_runtime
make_operative_state
cp -r "$OPD" "$P/backup"
rt_expect "inbox, capabilities and legacy backup" 0 verify-knowledge-integrity.sh "$P/backup" "$OPD" inbox

case="runtime integrity with inbox fails a lost learnings entry"
make_runtime
make_operative_state
cp -r "$OPD" "$P/backup"
rm "$OPD/learnings/2026-01-01-t1.md"
rt_expect "inbox, entry lost" 1 verify-knowledge-integrity.sh "$P/backup" "$OPD" inbox

case="runtime integrity with inbox passes when both directories are absent"
make_runtime
rt_expect "inbox, both absent" 0 verify-knowledge-integrity.sh "$P/no-backup" "$P/no-operative" inbox

case="runtime integrity without inbox still fails the operative dir's other entries"
make_runtime
make_operative_state
cp -r "$OPD" "$P/backup"
rt_expect "no inbox, capabilities" 1 verify-knowledge-integrity.sh "$P/backup" "$OPD"

[ "$status" -eq 0 ] && echo "knowledge dir: ok"
exit "$status"
