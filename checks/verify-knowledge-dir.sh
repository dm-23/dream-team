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
echo x > "$P/proj/$NEW/PROJECT-OVERVIEW.md"
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

# --- the project key and the profile directory ------------------------------------
export DREAM_TEAM_PROFILE="$tmp/my profile"

# make_repo [origin-url]: a fresh project whose proj/ is a git repository.
make_repo() {
  make_project "${2:-}"
  git init -q "$P/proj" || { fail "git init"; return; }
  [ -z "${1:-}" ] || git -C "$P/proj" remote add origin "$1"
}
# key_of: the key line for the current project; sets KEY_RC.
key_of() {
  KEY="$(cd "$P/proj" && bash "$P/team/tools/knowledge-dir.sh" key 2>"$tmp/err")"; KEY_RC=$?
}
absolute() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

case="key from an https address"
make_repo "https://github.com/Org/Repo.git"
key_of
[ "$KEY_RC" -eq 0 ] || fail "https: exit $KEY_RC"
printf '%s' "$KEY" | grep -Eq '^repo-[0-9a-f]{8}$' || fail "https: '$KEY' is not repo-<8 hex>"
KEY_HTTPS="$KEY"

case="key from an scp address"
make_repo "git@github.com:org/repo.git"
key_of
[ "$KEY_RC" -eq 0 ] && [ "$KEY" = "$KEY_HTTPS" ] || fail "scp: '$KEY' (exit $KEY_RC), expected '$KEY_HTTPS'"

case="key from an ssh address with a port"
make_repo "ssh://git@github.com:22/org/repo"
key_of
[ "$KEY_RC" -eq 0 ] && [ "$KEY" = "$KEY_HTTPS" ] || fail "ssh: '$KEY' (exit $KEY_RC), expected '$KEY_HTTPS'"

case="key from a user:password address"
make_repo "https://user:secret@github.com/org/repo/"
key_of
[ "$KEY_RC" -eq 0 ] && [ "$KEY" = "$KEY_HTTPS" ] || fail "user:password: '$KEY' (exit $KEY_RC), expected '$KEY_HTTPS'"

case="key differs for another repository"
make_repo "https://github.com/other/repo.git"
key_of
[ "$KEY_RC" -eq 0 ] && [ -n "$KEY" ] && [ "$KEY" != "$KEY_HTTPS" ] || fail "other: '$KEY' (exit $KEY_RC) should differ from '$KEY_HTTPS'"

case="key from the first remote by name"
make_repo ""
git -C "$P/proj" remote add zeta "https://example.com/z/zeta-repo.git"
git -C "$P/proj" remote add alpha "https://example.com/a/alpha-repo.git"
key_of
KEY_ALPHA="$KEY"
make_repo "https://example.com/a/alpha-repo.git"
key_of
[ "$KEY_RC" -eq 0 ] && [ -n "$KEY" ] && [ "$KEY" = "$KEY_ALPHA" ] || fail "alpha: '$KEY_ALPHA' vs origin-form '$KEY'"
case "$KEY_ALPHA" in alpha-repo-*) ;; *) fail "alpha: '$KEY_ALPHA' does not start with alpha-repo-" ;; esac

case="key without a remote"
make_repo ""
key_of
[ "$KEY_RC" -eq 1 ] && [ -z "$KEY" ] || fail "no remote: '$KEY' (exit $KEY_RC), expected nothing and exit 1"

case="key outside a repository"
make_project
key_of
[ "$KEY_RC" -eq 1 ] && [ -z "$KEY" ] || fail "no repository: '$KEY' (exit $KEY_RC), expected nothing and exit 1"

case="operative resolves to the profile directory"
make_repo "https://github.com/Org/Repo.git"
mkdir -p "$DREAM_TEAM_PROFILE/$KEY_HTTPS"
want="$(absolute "$DREAM_TEAM_PROFILE/$KEY_HTTPS")"
expect operative "$want"
case "$want" in *'\'*) fail "profile path has a backslash: $want" ;; esac

case="operative falls back when the profile directory is absent"
make_repo "https://github.com/other/repo.git"
mkdir -p "$P/proj/$OPS"
expect operative "$OPS"

case="operative ignores the profile when profileDir is empty"
sed 's|"profileDir": *"[^"]*"|"profileDir": ""|' "$MANIFEST" > "$tmp/no-profile.json"
make_repo "https://github.com/Org/Repo.git" "$tmp/no-profile.json"
mkdir -p "$P/proj/$OPS"
expect operative "$OPS"

case="project ignores an empty knowledge directory"
make_project
mkdir -p "$P/proj/$NEW" "$P/proj/$OLD"
echo x > "$P/proj/$OLD/PROJECT-OVERVIEW.md"
expect project "$OLD"

case="project ignores a knowledge directory without Markdown"
make_project
mkdir -p "$P/proj/$NEW" "$P/proj/$OLD"
echo x > "$P/proj/$NEW/x.txt"; echo x > "$P/proj/$OLD/PROJECT-OVERVIEW.md"
expect project "$OLD"

case="project takes a knowledge directory with Markdown"
make_project
mkdir -p "$P/proj/$NEW" "$P/proj/$OLD"
echo x > "$P/proj/$NEW/PROJECT-OVERVIEW.md"; echo x > "$P/proj/$OLD/PROJECT-OVERVIEW.md"
expect project "$NEW"

# --- remarks: the proposals directory beside the knowledge in use ------------------
case="remarks beside knowledge.dir"
make_project
mkdir -p "$P/proj/$NEW" "$P/proj/$OLD"
echo x > "$P/proj/$NEW/PROJECT-OVERVIEW.md"; echo x > "$P/proj/$OLD/PROJECT-OVERVIEW.md"
expect remarks "$NEW/proposals"
rm "$P/proj/$NEW/PROJECT-OVERVIEW.md"
expect remarks "$OPS/proposals"

case="remarks beside the legacy directory's operative twin"
make_project
mkdir -p "$P/proj/$OLD"
echo x > "$P/proj/$OLD/PROJECT-OVERVIEW.md"
expect remarks "$OPS/proposals"

case="remarks in a fresh project"
make_project
expect remarks "$NEW/proposals"
[ ! -e "$P/proj/$NEW" ] || fail "remarks created $NEW"

case="usage names remarks"
make_project
(cd "$P/proj" && bash "$P/team/tools/knowledge-dir.sh" bogus >/dev/null 2>"$tmp/err")
grep -q 'project|operative|remarks|key' "$tmp/err" || fail "usage line is '$(cat "$tmp/err")'"

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
# write_index <dir> <rows>: that many entry files under learnings/, one index
# row each.
write_index() {
  local i=1
  mkdir -p "$1/learnings"
  while [ "$i" -le "$2" ]; do
    printf '## [2026-01-01] e%s\n- **Tags:** x\n' "$i" > "$1/learnings/2026-01-01-e$i.md"
    i=$((i + 1))
  done
}
rt_expect() { # <label> <expected-rc> <args...>: run a runtime check from the team dir
  local label="$1" want="$2" script="$3" rc; shift 3
  (cd "$P/proj" && bash ".claude/checks/$script" "$@" >"$tmp/out" 2>"$tmp/err"); rc=$?
  [ "$rc" -eq "$want" ] || fail "$label: exit $rc, expected $want ($(head -c 300 "$tmp/err"))"
}

case="runtime inbox over the row budget"
make_runtime
write_index "$OPD" 31
rt_expect "31 rows" 1 verify-learnings-inbox.sh "$OPD/learnings"

case="runtime inbox within budget"
make_runtime
write_index "$OPD" 3
rt_expect "3 rows" 0 verify-learnings-inbox.sh "$OPD/learnings"

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

# make_operative_state: entry files beside the machine state an operative dir
# also holds (an edition's capabilities, a legacy backup).
make_operative_state() {
  write_index "$OPD" 1
  printf '## [2026-01-01] t1\n- Fix pattern: x\n' > "$OPD/learnings/2026-01-01-t1.md"
  mkdir -p "$OPD/claude" "$OPD/legacy-knowledge-x"
  printf '# Capabilities\n' > "$OPD/claude/CAPABILITIES.md"
  printf '# old\n' > "$OPD/legacy-knowledge-x/PROJECT-OVERVIEW.md"
}

case="runtime integrity fails the operative dir's other entries"
make_runtime
make_operative_state
cp -r "$OPD" "$P/backup"
rt_expect "capabilities" 1 verify-knowledge-integrity.sh "$P/backup" "$OPD"

case="runtime integrity ignores a remark removed from proposals/"
make_runtime
K="$P/proj/.dream-team/knowledge"
printf '# x\n' > "$K/BACKEND-ARCHITECTURE.md"
mkdir -p "$K/proposals"
printf '## [2026-01-01] r1\n- **Tags:** x\n' > "$K/proposals/2026-01-01-r1-abc123.md"
printf '## [2026-01-01] r2\n- **Tags:** x\n' > "$K/proposals/2026-01-01-r2-def456.md"
cp -r "$K" "$P/backup"
rm "$K/proposals/2026-01-01-r1-abc123.md"
rt_expect "remark removed" 0 verify-knowledge-integrity.sh "$P/backup" "$K"

case="runtime integrity refuses a third argument"
make_runtime
K="$P/proj/.dream-team/knowledge"
cp -r "$K" "$P/backup"
rt_expect "three arguments" 2 verify-knowledge-integrity.sh "$P/backup" "$K" inbox

[ "$status" -eq 0 ] && echo "knowledge dir: ok"
exit "$status"
