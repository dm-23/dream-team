#!/usr/bin/env bash
# Exercises tools/normalize-status.sh against throwaway tracking directories.
#
#   verify-normalize-status.sh     (run from anywhere; it locates the team root from its own path)
#
# Each case builds a tracking dir with one or more run directories, runs the
# normaliser, and compares the first line, the rest of the file and the exit
# code with what the tool promises. Exit 0 = every case passed, 1 = at least
# one failed; each failure names its case.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/tools/normalize-status.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

fails=0
fail() { echo "FAIL [$1] $2" >&2; fails=$((fails + 1)); }

[ -f "$TOOL" ] || { fail done-em-dash "tools/normalize-status.sh not found"; echo "normalize-status: FAILED" >&2; exit 1; }

tracking() { local t="$TMP/$1/.dream-team-tracking"; mkdir -p "$t"; printf '%s' "$t"; }
run_tool() { # tracking-dir [flags] -> OUT, RC; run from the project root like setup does
  OUT="$(cd "$1/.." && bash "$TOOL" "${@:2}" 2>&1)"; RC=$?
}
first() { head -1 "$1" | tr -d '\r'; }
rest() { tail -n +2 "$1"; }

# done-em-dash: **[DONE — date]** prose closing, date in the line
t="$(tracking done-em-dash)"; mkdir -p "$t/bugfix_a_2026-08-14"
printf '**[DONE — 2026-08-14]** shipped the thing\n\n**Workflow:** Bug Fix\n**Closed:** 2026-08-14\n' > "$t/bugfix_a_2026-08-14/status.md"
before_rest="$(rest "$t/bugfix_a_2026-08-14/status.md")"
run_tool "$t"
[ "$RC" = 0 ] || fail done-em-dash "exit $RC: $OUT"
[ "$(first "$t/bugfix_a_2026-08-14/status.md")" = "[DONE] 2026-08-14 — shipped the thing" ] || fail done-em-dash "first line: $(first "$t/bugfix_a_2026-08-14/status.md")"
[ "$(rest "$t/bugfix_a_2026-08-14/status.md")" = "$before_rest" ] || fail done-em-dash "the rest of the file changed"
case "$OUT" in *"normalized "*bugfix_a_2026-08-14*) ;; *) fail done-em-dash "no 'normalized' line: $OUT" ;; esac

# analyze-complete: "Complete —" closing, date from the Closed field
t="$(tracking analyze-complete)"; mkdir -p "$t/analyze_b_2026-08-11"
printf '# [Analyze] Complete — report written\n\n**Closed:** 2026-08-11\n' > "$t/analyze_b_2026-08-11/status.md"
run_tool "$t"
[ "$(first "$t/analyze_b_2026-08-11/status.md")" = "[DONE] 2026-08-11 — [Analyze] report written" ] || fail analyze-complete "first line: $(first "$t/analyze_b_2026-08-11/status.md")"

# complete-no-closed: no date anywhere -> the file's modification date
t="$(tracking complete-no-closed)"; mkdir -p "$t/x"
printf '# Complete — done\n\nbody\n' > "$t/x/status.md"
run_tool "$t"
l="$(first "$t/x/status.md")"
case "$l" in '[DONE] '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' — done') ;; *) fail complete-no-closed "first line: $l" ;; esac

# already-normal: byte-identical
t="$(tracking already-normal)"; mkdir -p "$t/y"
printf '[DONE] 2026-10-26 — BUILT: fixed\n\n**Closed:** 2026-10-26\n' > "$t/y/status.md"; cp "$t/y/status.md" "$TMP/already.orig"
run_tool "$t"
cmp -s "$t/y/status.md" "$TMP/already.orig" || fail already-normal "file changed"
case "$OUT" in *normalized*) fail already-normal "reported a change: $OUT" ;; esac

# open-run: "Complete" without the dash stays open, byte-identical
t="$(tracking open-run)"; mkdir -p "$t/z"
printf '# Status: Complete the import flow\n\n**Closed:** —\n' > "$t/z/status.md"; cp "$t/z/status.md" "$TMP/open.orig"
run_tool "$t"
cmp -s "$t/z/status.md" "$TMP/open.orig" || fail open-run "file changed"

# crlf: the first line keeps its CR, the rest is byte-identical
t="$(tracking crlf)"; mkdir -p "$t/c"
printf '**[DONE — 2026-08-14]** shipped\r\n**Closed:** 2026-08-14\r\nbody\r\n' > "$t/c/status.md"
before_rest="$(rest "$t/c/status.md" | od -c)"
run_tool "$t"
IFS= read -r l < "$t/c/status.md"   # read, not $(head -1): command substitution drops a trailing CR here
case "$l" in *$'\r') ;; *) fail crlf "first line lost its CR" ;; esac
[ "$(first "$t/c/status.md")" = "[DONE] 2026-08-14 — shipped" ] || fail crlf "first line: $(first "$t/c/status.md")"
[ "$(rest "$t/c/status.md" | od -c)" = "$before_rest" ] || fail crlf "the rest of the file changed"

# dry-run: prints the plan, writes nothing
t="$(tracking dry-run)"; mkdir -p "$t/d"
printf '**[DONE — 2026-08-14]** shipped\n' > "$t/d/status.md"; cp "$t/d/status.md" "$TMP/dry.orig"
run_tool "$t" --dry-run
[ "$RC" = 0 ] || fail dry-run "exit $RC: $OUT"
case "$OUT" in *"would normalize "*"[DONE] 2026-08-14 — shipped"*) ;; *) fail dry-run "no plan line: $OUT" ;; esac
cmp -s "$t/d/status.md" "$TMP/dry.orig" || fail dry-run "dry run wrote"

# no-status: a run directory without status.md and a stray file at the root are ignored
t="$(tracking no-status)"; mkdir -p "$t/e"; printf 'context_id=e\n' > "$t/.team-mode"; printf 'x\n' > "$t/stray.md"
run_tool "$t"
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail no-status "expected silence and exit 0, got exit $RC: $OUT"

# explicit-dir: the tracking directory given as an argument, from elsewhere
t="$(tracking explicit-dir)"; mkdir -p "$t/f"
printf '**[DONE — 2026-09-01]** moved\n' > "$t/f/status.md"
OUT="$(cd "$TMP" && bash "$TOOL" "$t" 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ "$(first "$t/f/status.md")" = "[DONE] 2026-09-01 — moved" ] || fail explicit-dir "exit $RC, first line: $(first "$t/f/status.md")"

[ "$fails" -eq 0 ] && echo "normalize-status: ok"
exit $(( fails > 0 ))
