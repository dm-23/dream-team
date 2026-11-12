#!/usr/bin/env bash
# Tests tools/learnings-index.sh, which prints the learnings index from the
# entry files, and the two runtime checks that read an inbox without an index
# file: checks/verify-learnings-inbox.sh and checks/verify-knowledge-integrity.sh
# with its third argument "inbox".
#
#   bash checks/verify-learnings-index.sh    (run from anywhere)
#
# Exit 0 = every case passed. 1 = a case failed; each failure is named.
# Repo-only: it never ships to the Copilot edition.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/tools/learnings-index.sh"
INBOX="$ROOT/checks/verify-learnings-inbox.sh"
INTEGRITY="$ROOT/checks/verify-knowledge-integrity.sh"
MANIFEST="$ROOT/team-manifest.json"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
status=0
case=""
fail() { echo "FAIL [$case]: $*" >&2; status=1; }

case="tool present"
[ -f "$TOOL" ] || fail "$TOOL is missing"

budget() { tr -d '\r' < "$MANIFEST" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" | head -1; }
TITLE_CHARS="$(budget learningsIndexRowTitleChars)"
MAX_TAGS="$(budget learningsIndexRowMaxTags)"
[ -n "$TITLE_CHARS" ] && [ -n "$MAX_TAGS" ] || { echo "FAIL: the manifest has no row limits" >&2; exit 1; }

# run <dir>... : the tool from $tmp, so relative arguments resolve there.
run() { (cd "$tmp" && bash "$TOOL" "$@") > "$tmp/out" 2> "$tmp/err"; rc=$?; }
expect_rc() { [ "$rc" = "$1" ] || fail "expected exit $1, got $rc: $(head -c 400 "$tmp/err")"; }
has_line() { grep -qxF -- "$1" "$tmp/out" || fail "no line '$1' in: $(cat "$tmp/out")"; }
lacks() { ! grep -qF -- "$1" "$tmp/out" || fail "'$1' in: $(cat "$tmp/out")"; }
rows() { grep -c '^| [0-9u]' "$tmp/out"; }
entry() { # <file> <date> <title> <tags>
  mkdir -p "$(dirname "$1")"
  printf '## [%s] %s\n- **Workflow:** Bug Fix\n- **Symptom:** s\n- **Tags:** %s\n' "$2" "$3" "$4" > "$1"
}
HEADER="| Date | Title | Tags | File |"
SEP="|------|-------|------|------|"

# --- the tool -------------------------------------------------------------------
case="two entries, older first"
entry "$tmp/two/2026-11-02-newer.md" 2026-11-02 "Newer trap" "alpha, beta"
entry "$tmp/two/2026-10-30-older.md" 2026-10-30 "Older trap" "gamma"
run two
expect_rc 0
[ "$(sed -n 1p "$tmp/out")" = "$HEADER" ] || fail "line 1: $(sed -n 1p "$tmp/out")"
[ "$(sed -n 2p "$tmp/out")" = "$SEP" ] || fail "line 2: $(sed -n 2p "$tmp/out")"
[ "$(sed -n 3p "$tmp/out")" = "| 2026-10-30 | Older trap | gamma | two/2026-10-30-older.md |" ] || fail "line 3: $(sed -n 3p "$tmp/out")"
[ "$(sed -n 4p "$tmp/out")" = "| 2026-11-02 | Newer trap | alpha, beta | two/2026-11-02-newer.md |" ] || fail "line 4: $(sed -n 4p "$tmp/out")"
[ "$(sed -n 5p "$tmp/out")" = "entries: 2" ] || fail "line 5: $(sed -n 5p "$tmp/out")"
[ "$(wc -l < "$tmp/out" | tr -d ' ')" = 5 ] || fail "expected 5 lines: $(cat "$tmp/out")"

case="long title and too many tags"
long="$(printf 'Abcdefghij%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)"
entry "$tmp/long/2026-11-01-long.md" 2026-11-01 "$long" "t1, t2, t3, t4, t5, t6, t7, t8"
run long
expect_rc 0
want_tags="$(printf 't%s, ' $(seq 1 "$MAX_TAGS"))"; want_tags="${want_tags%, }"
has_line "| 2026-11-01 | $(printf '%s' "$long" | cut -c1-"$TITLE_CHARS") | $want_tags | long/2026-11-01-long.md |"
has_line "entries: 1"

case="CRLF entry"
entry "$tmp/lf/2026-11-04-twin.md" 2026-11-04 "Twin" "a, b"
mkdir -p "$tmp/crlf"
awk -v BINMODE=3 '{ printf "%s\r\n", $0 }' "$tmp/lf/2026-11-04-twin.md" > "$tmp/crlf/2026-11-04-twin.md"
[ "$(tr -cd '\r' < "$tmp/crlf/2026-11-04-twin.md" | wc -c | tr -d ' ')" = 4 ] || fail "fixture is not CRLF"
(cd "$tmp/lf" && bash "$TOOL" .) > "$tmp/out-lf" 2>&1
(cd "$tmp/crlf" && bash "$TOOL" .) > "$tmp/out-crlf" 2>&1
cmp -s "$tmp/out-lf" "$tmp/out-crlf" || fail "CRLF output differs: $(cat "$tmp/out-crlf")"
[ "$(tr -cd '\r' < "$tmp/out-crlf" | wc -c | tr -d ' ')" = 0 ] || fail "a CR in the output"
grep -qxF "| 2026-11-04 | Twin | a, b | ./2026-11-04-twin.md |" "$tmp/out-crlf" || fail "row: $(cat "$tmp/out-crlf")"

case="unreadable heading"
mkdir -p "$tmp/broken"
printf 'Some prose, not a heading.\n- **Tags:** x\n' > "$tmp/broken/2026-11-03-broken.md"
printf '# Wrong\n' > "$tmp/broken/nodate.md"
run broken
expect_rc 0
has_line "| 2026-11-03 | (unreadable heading) | x | broken/2026-11-03-broken.md |"
has_line "| unknown | (unreadable heading) |  | broken/nodate.md |"
has_line "entries: 2"

case="same file name in two directories"
entry "$tmp/a/2026-11-05-dup.md" 2026-11-05 "From a" "a"
entry "$tmp/b/2026-11-05-dup.md" 2026-11-05 "From b" "b"
run a b
expect_rc 0
has_line "| 2026-11-05 | From b | b | b/2026-11-05-dup.md |"
lacks "From a"
has_line "entries: 1"

case="directory path with a space"
entry "$tmp/with space/2026-11-06-sp.md" 2026-11-06 "Spaced" "s"
run "with space"
expect_rc 0
has_line "| 2026-11-06 | Spaced | s | with space/2026-11-06-sp.md |"
has_line "entries: 1"

case="a missing directory beside a real one"
run no-such-dir two
expect_rc 0
[ "$(rows)" = 2 ] || fail "expected 2 rows: $(cat "$tmp/out")"
has_line "entries: 2"

case="no argument"
run
expect_rc 2

case="unreadable manifest"
mkdir -p "$tmp/team/tools"; cp "$TOOL" "$tmp/team/tools/"
(cd "$tmp" && bash team/tools/learnings-index.sh two) > "$tmp/out" 2> "$tmp/err"; rc=$?
expect_rc 2

# --- the due check on the remarks dir ----------------------------------------
inbox() { bash "$INBOX" "$1" > "$tmp/out" 2> "$tmp/err"; rc=$?; }

case="inbox: 31 entry files"
for i in $(seq 1 31); do entry "$tmp/ops31/2026-10-$(printf '%02d' $(( (i - 1) % 28 + 1 )))-e$i.md" 2026-10-01 "E$i" x; done
inbox "$tmp/ops31"
expect_rc 1
grep -qF "over: the index has 31 rows" "$tmp/out" || fail "$(cat "$tmp/out")"

case="inbox: 3 entries, no mark"
for i in 1 2 3; do entry "$tmp/ops3/2026-10-0$i-e$i.md" "2026-10-0$i" "E$i" x; done
inbox "$tmp/ops3"
expect_rc 0
grep -qxF "learnings inbox: 3 index rows (max $(budget learningsIndexMaxRows)), 3 entries, 0 pending marks" "$tmp/out" || fail "$(cat "$tmp/out")"

case="inbox: one entry with a mark"
entry "$tmp/opsm/2026-10-01-m.md" 2026-10-01 M x
printf '[PROMOTE] PROJECT-RULES.md — Always X\n' >> "$tmp/opsm/2026-10-01-m.md"
inbox "$tmp/opsm"
expect_rc 1
grep -qF "1 pending marks" "$tmp/out" || fail "$(cat "$tmp/out")"

case="inbox: a SUBMITTED line no longer exempts the marks"
entry "$tmp/opss/2026-10-01-s.md" 2026-10-01 S x
printf '[PROMOTE] PROJECT-RULES.md — Always X\n[SUBMITTED 2026-10-02] knowledge/proposals-20261002-101010 as 2026-10-01-s.md\n' >> "$tmp/opss/2026-10-01-s.md"
inbox "$tmp/opss"
expect_rc 1
grep -qF "1 pending marks" "$tmp/out" || fail "$(cat "$tmp/out")"

case="inbox: an [EXCEPTION] entry alone"
mkdir -p "$tmp/opsx"
printf '## [2026-10-01] exception src/a.ts\n[EXCEPTION] - src/a.ts:12 · a reason\n' > "$tmp/opsx/2026-10-01-exception-1.md"
inbox "$tmp/opsx"
expect_rc 0
grep -qxF "learnings inbox: 1 index rows (max $(budget learningsIndexMaxRows)), 1 entries, 0 pending marks" "$tmp/out" || fail "$(cat "$tmp/out")"

case="inbox: empty directory"
mkdir -p "$tmp/opse"
inbox "$tmp/opse"
expect_rc 0
grep -qxF "learnings inbox: ok (no entries yet)" "$tmp/out" || fail "$(cat "$tmp/out")"

case="inbox: a missing directory"
inbox "$tmp/no-such-remarks"
expect_rc 0

case="inbox: a learnings/ level is not read"
entry "$tmp/opsn/learnings/2026-10-01-n.md" 2026-10-01 N x
printf '[PROMOTE] PROJECT-RULES.md — Always X\n' >> "$tmp/opsn/learnings/2026-10-01-n.md"
inbox "$tmp/opsn"
expect_rc 0

# --- the integrity check on an inbox without an index file -------------------------
case="integrity: learnings/ only, inbox"
for d in bk cur; do
  entry "$tmp/int/$d/learnings/2026-10-01-a.md" 2026-10-01 A x
  entry "$tmp/int/$d/learnings/2026-10-02-b.md" 2026-10-02 B y
done
bash "$INTEGRITY" "$tmp/int/bk" "$tmp/int/cur" inbox > "$tmp/out" 2> "$tmp/err"; rc=$?
expect_rc 0

[ "$status" -eq 0 ] && echo "learnings index: ok"
exit "$status"
