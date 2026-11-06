#!/usr/bin/env bash
# Exercises tools/collect-amendments.sh against throwaway project directories.
#
#   verify-collect-amendments.sh     (run from anywhere; it locates the team root from its own path)
#
# Each case builds one or more projects with a collector at
# .dream-team-tracking/team-amendments.md, runs the tool over them and checks
# its report and exit code. The tool only reads: the last case proves no
# input byte changed. Exit 0 = every case passed, 1 = at least one failed;
# each failure names its case.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/tools/collect-amendments.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

fails=0
fail() { echo "FAIL [$1] $2" >&2; fails=$((fails + 1)); }

[ -f "$TOOL" ] || { fail setup "tools/collect-amendments.sh not found"; echo "collect amendments: FAILED" >&2; exit 1; }

run_tool() { OUT="$(bash "$TOOL" "$@" 2>&1)"; RC=$?; }

# project NAME -> prints the project dir, creates its tracking dir
project() { local p="$TMP/$1"; mkdir -p "$p/.dream-team-tracking"; printf '%s' "$p"; }

header() {
  printf '# Team amendments\n\nTeam version checked: 4.7.0\n\nInstruction paragraph.\n'
}

# entry ID RULE PROPOSAL-FILE SEEN
entry() {
  printf '\n## %s — title of %s\n' "$1" "$1"
  printf -- '- Roles: reviewer\n'
  printf -- '- Rule: %s\n' "$2"
  printf -- '- Proposal: %s — change the rule about %s\n' "$3" "$1"
  printf -- '- Why: why %s\n' "$1"
  printf -- '- Evidence: run_x → .dream-team-tracking/run_x/status.md:10\n'
  printf -- '- Seen: %s — run_x\n' "$4"
  printf -- '- Added: 2026-11-06, team 4.7.0, adopted at the close of run_x\n'
}

# 1. no arguments
run_tool
[ "$RC" = 2 ] || fail no-args "exit $RC, expected 2: $OUT"

# 2. a project without a collector
p="$(project nocollector)"
run_tool "$p"
[ "$RC" = 0 ] || fail no-collector "exit $RC: $OUT"
case "$OUT" in *"nocollector: no collector"*) ;; *) fail no-collector "no 'no collector' note: $OUT" ;; esac

# 3. the same rule in two projects is merged, Seen summed, both ids listed
a="$(project alpha)"; b="$(project beta)"
{ header; entry alpha-20261106-1 "Show a reachable sequence before adding a guard." agents/reviewer.md 2; } > "$a/.dream-team-tracking/team-amendments.md"
{ header; entry beta-20261105-1 "Show a reachable sequence before adding a guard." agents/reviewer.md 1; } > "$b/.dream-team-tracking/team-amendments.md"
run_tool "$a" "$b"
[ "$RC" = 0 ] || fail merge "exit $RC: $OUT"
[ "$(printf '%s\n' "$OUT" | grep -c '^- Show a reachable sequence')" = 1 ] || fail merge "expected one bullet: $OUT"
case "$OUT" in *"seen 3"*) ;; *) fail merge "Seen not summed to 3: $OUT" ;; esac
case "$OUT" in *alpha-20261106-1*beta-20261105-1*|*beta-20261105-1*alpha-20261106-1*) ;; *) fail merge "both ids not listed: $OUT" ;; esac
case "$OUT" in *"projects: alpha, beta"*) ;; *) fail merge "projects not listed: $OUT" ;; esac
case "$OUT" in *"## agents/reviewer.md"*) ;; *) fail merge "no section for agents/reviewer.md: $OUT" ;; esac
merged="$OUT"

# 4. two proposal files give two sections, sorted
c="$(project gamma)"
{ header; entry gamma-20261106-1 "Prefer the simpler proposal unless a shown problem needs more." skills/team/references/quorum.md 1;
  entry gamma-20261106-2 "Name do nothing as a proposal." agents/brainstorm.md 1; } > "$c/.dream-team-tracking/team-amendments.md"
run_tool "$c"
[ "$RC" = 0 ] || fail sections "exit $RC: $OUT"
secs="$(printf '%s\n' "$OUT" | grep '^## ' | tr '\n' '|')"
[ "$secs" = "## agents/brainstorm.md|## skills/team/references/quorum.md|" ] || fail sections "sections: $secs"

# 5. CRLF collectors read the same as LF ones
d="$(project alpha-crlf)"; e="$(project beta-crlf)"
sed 's/$/\r/' "$a/.dream-team-tracking/team-amendments.md" > "$d/.dream-team-tracking/team-amendments.md"
sed 's/$/\r/' "$b/.dream-team-tracking/team-amendments.md" > "$e/.dream-team-tracking/team-amendments.md"
run_tool "$d" "$e"
[ "$RC" = 0 ] || fail crlf "exit $RC: $OUT"
case "$OUT" in *$'\r'*) fail crlf "carriage return in the output" ;; esac
[ "$(printf '%s\n' "$OUT" | sed 's/-crlf//g')" = "$merged" ] || fail crlf "output differs from the LF case: $OUT"

# 6. a collector with a header only
f="$(project headeronly)"
header > "$f/.dream-team-tracking/team-amendments.md"
run_tool "$f"
[ "$RC" = 0 ] || fail header-only "exit $RC: $OUT"
[ "$(printf '%s\n' "$OUT" | grep -c '^- ')" = 0 ] || fail header-only "bullets from a header-only collector: $OUT"

# 7. the inputs are untouched
for p in "$a" "$b" "$c" "$d" "$e" "$f"; do cp "$p/.dream-team-tracking/team-amendments.md" "$p/copy"; done
run_tool "$a" "$b" "$c" "$d" "$e" "$f"
for p in "$a" "$b" "$c" "$d" "$e" "$f"; do
  cmp -s "$p/copy" "$p/.dream-team-tracking/team-amendments.md" || fail read-only "$p changed"
  [ "$(ls -A "$p/.dream-team-tracking")" = "team-amendments.md" ] || fail read-only "$p gained files: $(ls -A "$p/.dream-team-tracking")"
done

if [ "$fails" -eq 0 ]; then echo "collect amendments: ok"; exit 0; fi
echo "collect amendments: $fails failed" >&2
exit 1
