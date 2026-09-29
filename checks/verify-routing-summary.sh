#!/usr/bin/env bash
# Fixture test for checks/summarize-routing.sh: four runs whose expected
# numbers are worked out by hand.
#
#   A  closed; service bug_fix @0.91 = team = final; difficulty low, 2 files
#   B  closed; service and team small_change @0.62, user overrode to bug_fix;
#      difficulty high but 1 file and no rework (a high inversion); CRLF log
#   C  open (no outcome line); service and team full_feature @0.85
#   D  closed; service unavailable
#
#   verify-routing-summary.sh     (run from anywhere; it locates the team
#                                  root from its own path)
set -uo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.." || exit 1
tool="$(pwd)/checks/summarize-routing.sh"
[ -f "$tool" ] || { echo "FAIL: checks/summarize-routing.sh not found" >&2; exit 1; }

t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
T=$'\t'
mkdir -p "$t/a" "$t/b" "$t/c" "$t/d"
printf '%s\n' \
  "2026-10-01${T}workflow${T}jev=bug_fix${T}conf=0.91${T}team=bug_fix" \
  "2026-10-01${T}difficulty${T}jev=low${T}conf=0.80" \
  "2026-10-01${T}outcome${T}workflow=bug_fix${T}override=no${T}files=2${T}rework=0" > "$t/a/routing.log"
printf '%s\r\n' \
  "2026-10-02${T}workflow${T}jev=small_change${T}conf=0.62${T}team=small_change" \
  "2026-10-02${T}difficulty${T}jev=high${T}conf=0.70" \
  "2026-10-02${T}outcome${T}workflow=bug_fix${T}override=yes${T}files=1${T}rework=0" > "$t/b/routing.log"
printf '%s\n' \
  "2026-10-03${T}workflow${T}jev=full_feature${T}conf=0.85${T}team=full_feature" > "$t/c/routing.log"
printf '%s\n' \
  "2026-10-04${T}workflow${T}jev=unavailable${T}conf=-${T}team=docs" \
  "2026-10-04${T}outcome${T}workflow=docs${T}override=no${T}files=1${T}rework=0" > "$t/d/routing.log"

status=0
fail() { echo "FAIL: $*" >&2; status=1; }

out="$(bash "$tool" "$t")"; code=$?
[ "$code" = 0 ] || fail "exit $code"
for want in \
  "Routing logs: 4 runs, 3 closed" \
  "Workflow: 4 decisions, 1 unavailable" \
  ">=0.80  2  100%  100%" \
  "0.50-0.79  1  0%  100%" \
  "<0.50  0  -  -" \
  "User overrides: 1; the service had named the final workflow in 0" \
  "low  1  2.0  0%" \
  "medium  0  -  -" \
  "high  1  1.0  0%" \
  "Inversions: low with files>=6 or rework>=2: 0; high with files<=1 and rework=0: 1" \
  "Phase 2 exit: 3/150 answered workflow decisions; high-confidence agreement 100% over 1 closed (need >=95% over >=50) -> not met"
do
  printf '%s\n' "$out" | grep -qF -- "$want" || fail "missing line: $want"
done

# The gate: outages never count as decisions ...
g="$t/gate"; mkdir -p "$g"
for i in $(seq 1 149); do
  mkdir -p "$g/u$i"
  printf '%s\n' "2026-10-05${T}workflow${T}jev=unavailable${T}conf=-${T}team=bug_fix" \
    "2026-10-05${T}outcome${T}workflow=bug_fix${T}override=no${T}files=1${T}rework=0" > "$g/u$i/routing.log"
done
mkdir -p "$g/ok"
printf '%s\n' "2026-10-05${T}workflow${T}jev=bug_fix${T}conf=0.95${T}team=bug_fix" \
  "2026-10-05${T}outcome${T}workflow=bug_fix${T}override=no${T}files=1${T}rework=0" > "$g/ok/routing.log"
bash "$tool" "$g" | grep -qF -- "-> not met" || fail "gate: outages counted as decisions"

# ... and 150 confident, closed, agreeing decisions pass it.
m="$t/met"; mkdir -p "$m"
for i in $(seq 1 150); do
  mkdir -p "$m/r$i"
  printf '%s\n' "2026-10-05${T}workflow${T}jev=bug_fix${T}conf=0.95${T}team=bug_fix" \
    "2026-10-05${T}outcome${T}workflow=bug_fix${T}override=no${T}files=1${T}rework=0" > "$m/r$i/routing.log"
done
bash "$tool" "$m" | grep -qF -- "150/150 answered workflow decisions; high-confidence agreement 100% over 150 closed (need >=95% over >=50) -> met" \
  || fail "gate: 150 agreeing decisions did not pass"

out="$(bash "$tool" "$t/nonexistent")"; code=$?
[ "$code" = 0 ] || fail "missing dir: exit $code"
printf '%s\n' "$out" | grep -qF "Routing logs: 0 runs, 0 closed" || fail "missing dir: $out"

[ "$status" -eq 0 ] && echo "routing summary: ok"
exit "$status"
