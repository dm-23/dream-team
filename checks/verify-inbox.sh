#!/usr/bin/env bash
# Tests tools/inbox.sh, the one way into the operative dir (the learnings
# inbox), against throwaway git repositories with an origin remote and a
# temporary profile root whose path holds a space.
#
#   bash checks/verify-inbox.sh    (run from anywhere)
#
# Exit 0 = every case passed. 1 = a case failed; each failure is named.
# Repo-only: it never ships to the Copilot edition.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/tools/inbox.sh"
RESOLVER="$ROOT/tools/knowledge-dir.sh"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
status=0
case=""
fail() { echo "FAIL [$case]: $*" >&2; status=1; }

[ -f "$TOOL" ] || { echo "FAIL: $TOOL is missing" >&2; exit 1; }

export DREAM_TEAM_PROFILE="$tmp/my profile"
absolute() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# repo <dir> <origin-url>: a fresh git repository with an origin remote.
repo() {
  mkdir -p "$1"
  git init -q "$1" || fail "git init $1"
  git -C "$1" remote add origin "$2" || fail "git remote add in $1"
}
key_of() { (cd "$1" && bash "$RESOLVER" key); }

# run <args...>: the tool in $P, stdout to $tmp/out, stderr to $tmp/err, exit in RC.
run() {
  (cd "$P" && bash "$TOOL" "$@") > "$tmp/out" 2> "$tmp/err"; RC=$?
}
# run_in <stdin-file> <args...>
run_in() {
  local in="$1"; shift
  (cd "$P" && bash "$TOOL" "$@") < "$in" > "$tmp/out" 2> "$tmp/err"; RC=$?
}
expect_rc() { [ "$RC" -eq "$1" ] || fail "exit $RC, expected $1 (stderr: $(cat "$tmp/err"))"; }
line() { sed -n "${1}p" "$tmp/out" | tr -d '\r'; }
# snapshot <dir>: every path below it with its checksum, for "nothing written".
snapshot() { (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r f; do
  if [ -f "$f" ]; then printf '%s %s\n' "$f" "$(cksum < "$f")"; else printf '%s\n' "$f"; fi
done); }

# --- the main project: the profile directory for its key exists ------------------
P="$tmp/proj"
repo "$P" "https://github.com/Org/Inbox-Repo.git"
KEY="$(key_of "$P")"
[ -n "$KEY" ] || fail "no key for the fixture repository"
OPD="$DREAM_TEAM_PROFILE/$KEY"
mkdir -p "$OPD"
OPD_SHOWN="$(absolute "$OPD")"

case="where, profile"
run where
expect_rc 0
[ "$(line 1)" = "$OPD_SHOWN" ] || fail "line 1 '$(line 1)', expected '$OPD_SHOWN'"
[ "$(line 2)" = "profile (key $KEY)" ] || fail "line 2 '$(line 2)', expected 'profile (key $KEY)'"
[ "$(wc -l < "$tmp/out" | tr -d ' ')" -eq 2 ] || fail "expected 2 lines, got $(wc -l < "$tmp/out")"

case="where, per-copy (profile not created)"
P2="$tmp/proj2"
repo "$P2" "https://github.com/Org/Other-Repo.git"
mkdir -p "$P2/.dream-team-tracking/operative"
P="$P2"
run where
expect_rc 0
[ "$(line 1)" = ".dream-team-tracking/operative" ] || fail "line 1 '$(line 1)'"
[ "$(line 2)" = "per-copy (profile not created)" ] || fail "line 2 '$(line 2)'"
[ "$(wc -l < "$tmp/out" | tr -d ' ')" -eq 2 ] || fail "expected 2 lines"
echo x > "$P2/.dream-team-tracking/operative/LEARNINGS.md"
run where
[ "$(line 3)" = "note: LEARNINGS.md is still here; /team-setup moves the inbox" ] || fail "line 3 '$(line 3)'"

case="where, per-copy (no remote)"
P3="$tmp/proj3"
mkdir -p "$P3"; git init -q "$P3"
P="$P3"
run where
expect_rc 0
[ "$(line 2)" = "per-copy (no remote)" ] || fail "line 2 '$(line 2)'"

P="$tmp/proj"
SRC_DIR="$P/.dream-team-tracking/run/learnings"
mkdir -p "$SRC_DIR"
# A CRLF entry without a final newline.
printf '## [2026-11-02] Foo trap\r\n\r\n- **Tags:** alpha, beta\r\n- **Seen:** twice' > "$SRC_DIR/2026-11-02-foo.md"
cp "$SRC_DIR/2026-11-02-foo.md" "$tmp/foo.orig"

case="add twice"
run add .dream-team-tracking/run/learnings/2026-11-02-foo.md
expect_rc 0
[ "$(cat "$tmp/out")" = "learnings/2026-11-02-foo.md" ] || fail "first add printed '$(cat "$tmp/out")'"
run add .dream-team-tracking/run/learnings/2026-11-02-foo.md
expect_rc 0
[ "$(cat "$tmp/out")" = "learnings/2026-11-02-foo-2.md" ] || fail "second add printed '$(cat "$tmp/out")'"
cmp -s "$tmp/foo.orig" "$OPD/learnings/2026-11-02-foo.md" || fail "first copy differs from the source"
cmp -s "$tmp/foo.orig" "$OPD/learnings/2026-11-02-foo-2.md" || fail "second copy differs from the source"
cmp -s "$tmp/foo.orig" "$SRC_DIR/2026-11-02-foo.md" || fail "the source changed"

case="index with an extra dir"
mkdir -p "$P/.dream-team/knowledge/proposals"
printf '## [2026-11-01] Bar proposal\n\n- **Tags:** gamma\n' > "$P/.dream-team/knowledge/proposals/2026-11-01-bar.md"
run index .dream-team/knowledge/proposals
expect_rc 0
rows="$(grep -c '^| 2026-' "$tmp/out")"
[ "$rows" -eq 3 ] || fail "$rows rows, expected 3"
grep -q '| learnings/2026-11-02-foo.md |$' "$tmp/out" || fail "no inbox row for foo.md"
grep -q '| learnings/2026-11-02-foo-2.md |$' "$tmp/out" || fail "no inbox row for foo-2.md"
grep -q '| \.dream-team/knowledge/proposals/2026-11-01-bar.md |$' "$tmp/out" || fail "no row for the proposal"
grep -q '^entries: 3$' "$tmp/out" || fail "no 'entries: 3' line"
for p in "$OPD_SHOWN" "$DREAM_TEAM_PROFILE" "my profile"; do
  grep -qF "$p" "$tmp/out" "$tmp/err" && fail "the profile path '$p' appears in the output"
done

case="show, one missing"
run show learnings/2026-11-02-foo.md learnings/nope.md
expect_rc 1
{ printf '==> learnings/2026-11-02-foo.md <==\n'; cat "$tmp/foo.orig"; printf '\n==> learnings/nope.md <== (missing)\n'; } > "$tmp/show.want"
cmp -s "$tmp/show.want" "$tmp/out" || fail "show output differs: $(od -c "$tmp/out" | head -5)"

case="append from stdin to a CRLF entry without a final newline"
printf -- '- [PROMOTE] keep the rule\n' > "$tmp/promote"
run_in "$tmp/promote" append learnings/2026-11-02-foo.md -
expect_rc 0
{ cat "$tmp/foo.orig"; printf '\r\n'; cat "$tmp/promote"; } > "$tmp/append.want"
cmp -s "$tmp/append.want" "$OPD/learnings/2026-11-02-foo.md" || fail "appended entry differs: $(od -c "$OPD/learnings/2026-11-02-foo.md" | tail -4)"

case="append to a missing entry"
run_in "$tmp/promote" append learnings/nope.md -
expect_rc 1
[ -e "$OPD/learnings/nope.md" ] && fail "the missing entry was created"

case="append creates review-exceptions.md"
printf -- '- accepted: one exception\n' > "$P/.dream-team-tracking/run/exc.md"
run append review-exceptions.md .dream-team-tracking/run/exc.md
expect_rc 0
cmp -s "$P/.dream-team-tracking/run/exc.md" "$OPD/review-exceptions.md" || fail "review-exceptions.md differs from the source"

case="list"
run list
expect_rc 0
printf 'learnings/2026-11-02-foo-2.md\nlearnings/2026-11-02-foo.md\nreview-exceptions.md\n' > "$tmp/list.want"
cmp -s "$tmp/list.want" "$tmp/out" || fail "list printed: $(cat "$tmp/out")"

case="check with one [PROMOTE] entry"
run check
expect_rc 1
grep -q 'pending: 1 unresolved' "$tmp/out" || fail "no pending line: $(cat "$tmp/out")"
grep -q 'learnings inbox: due' "$tmp/out" || fail "no due line"

case="backup and verify-backup"
run backup .dream-team-tracking/b1
expect_rc 0
[ "$(cat "$tmp/out")" = ".dream-team-tracking/b1" ] || fail "backup printed '$(cat "$tmp/out")'"
cmp -s "$OPD/learnings/2026-11-02-foo.md" "$P/.dream-team-tracking/b1/learnings/2026-11-02-foo.md" || fail "backup copy of foo.md differs"
cmp -s "$OPD/review-exceptions.md" "$P/.dream-team-tracking/b1/review-exceptions.md" || fail "backup copy of review-exceptions.md differs"
run verify-backup .dream-team-tracking/b1
expect_rc 0
grep -q '^knowledge integrity: ok (inbox: ' "$tmp/out" || fail "verify-backup printed: $(cat "$tmp/out" "$tmp/err")"
run backup .dream-team-tracking/b1
expect_rc 1

case="put, then remove"
printf '## [2026-11-03] Replaced\n\n- **Tags:** delta\n' > "$P/.dream-team-tracking/run/new.md"
run put learnings/2026-11-02-foo.md .dream-team-tracking/run/new.md
expect_rc 0
cmp -s "$P/.dream-team-tracking/run/new.md" "$OPD/learnings/2026-11-02-foo.md" || fail "put did not replace byte for byte"
run remove learnings/2026-11-02-foo.md
expect_rc 0
[ -e "$OPD/learnings/2026-11-02-foo.md" ] && fail "remove left the entry"
run remove learnings/2026-11-02-foo-2.md learnings/nope.md
expect_rc 1
[ -e "$OPD/learnings/2026-11-02-foo-2.md" ] && fail "remove with a missing name left the other entry"

case="bad names and sources"
printf 'x\n' > "$tmp/x.md"
before="$(snapshot "$DREAM_TEAM_PROFILE")"
for args in "show ../x.md" "show /etc/passwd" "add $tmp/x.md" "put learnings/sub/x.md .dream-team-tracking/run/new.md" \
            "add .dream-team-tracking/../x.md" "put learnings/../x.md .dream-team-tracking/run/new.md" \
            "put learnings/x.txt .dream-team-tracking/run/new.md" "put LEARNINGS.md .dream-team-tracking/run/new.md" \
            "append review-exceptions.md ../outside.md" "backup ../b2" "bogus" ""; do
  # shellcheck disable=SC2086
  run $args
  [ "$RC" -eq 2 ] || fail "'$args': exit $RC, expected 2"
done
after="$(snapshot "$DREAM_TEAM_PROFILE")"
[ "$before" = "$after" ] || fail "a refused command wrote into the profile"

# no_path: the profile path appears in neither output stream.
no_path() {
  local p
  for p in "$OPD_SHOWN" "$DREAM_TEAM_PROFILE" "my profile"; do
    if grep -qF "$p" "$tmp/out" "$tmp/err"; then
      fail "the profile path appears in the output: $(cat "$tmp/err")"; return
    fi
  done
}

case="append to a read-only entry"
printf '## [2026-11-04] Read only\n' > "$OPD/learnings/2026-11-04-ro.md"
chmod a-w "$OPD/learnings/2026-11-04-ro.md"
if [ -w "$OPD/learnings/2026-11-04-ro.md" ]; then
  echo "skip [$case] the file stays writable here"
else
  run_in "$tmp/promote" append learnings/2026-11-04-ro.md -
  expect_rc 2
  no_path
fi
chmod u+w "$OPD/learnings/2026-11-04-ro.md"
rm -f "$OPD/learnings/2026-11-04-ro.md"

case="append to review-exceptions.md that is a directory"
mv "$OPD/review-exceptions.md" "$tmp/exc.saved"
mkdir "$OPD/review-exceptions.md"
run_in "$tmp/promote" append review-exceptions.md -
expect_rc 2
no_path
[ -z "$(ls -A "$OPD/review-exceptions.md")" ] || fail "something was written into the directory"
rmdir "$OPD/review-exceptions.md"; mv "$tmp/exc.saved" "$OPD/review-exceptions.md"

case="put onto a name that is a directory"
mkdir "$OPD/learnings/2026-11-05-dir.md"
run put learnings/2026-11-05-dir.md .dream-team-tracking/run/new.md
expect_rc 2
no_path
[ -z "$(ls -A "$OPD/learnings/2026-11-05-dir.md")" ] || fail "put wrote into the directory"
ls -A "$OPD/learnings" | grep -q '^\.inbox-put-' && fail "put left a staged file"
rmdir "$OPD/learnings/2026-11-05-dir.md"

case="learnings/ cannot be created"
P4="$tmp/proj4"
repo "$P4" "https://github.com/Org/Blocked-Repo.git"
K4="$(key_of "$P4")"
mkdir -p "$DREAM_TEAM_PROFILE/$K4"
echo "not a directory" > "$DREAM_TEAM_PROFILE/$K4/learnings"
mkdir -p "$P4/.dream-team-tracking/run"
cp "$tmp/foo.orig" "$P4/.dream-team-tracking/run/2026-11-02-foo.md"
P="$P4"
run add .dream-team-tracking/run/2026-11-02-foo.md
expect_rc 2
cmp -s "$tmp/foo.orig" "$P4/.dream-team-tracking/run/2026-11-02-foo.md" || fail "the source changed"
[ "$(cat "$DREAM_TEAM_PROFILE/$K4/learnings")" = "not a directory" ] || fail "the blocking file changed"

[ "$status" -eq 0 ] && echo "inbox: ok"
exit "$status"
