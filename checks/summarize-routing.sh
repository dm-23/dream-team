#!/usr/bin/env bash
# Summarises the decision-routing shadow logs, one routing.log per run under
# the tracking directory, into the numbers the go/no-go decision on letting
# the service act needs: how often it agreed with the workflow a run finished
# as, by confidence band, and how its difficulty guesses compared with the
# files a run touched and the rework it needed. Read-only; always exits 0.
#
#   bash .claude/checks/summarize-routing.sh [tracking-dir]
#   (run from the project root; the default is .claude-tracking)
#
# The log shapes are defined in skills/team/SKILL.md → Decision routing.
set -uo pipefail
export LC_ALL=C
dir="${1:-.claude-tracking}"

{
  if [ -d "$dir" ]; then
    find "$dir" -mindepth 2 -maxdepth 2 -name routing.log 2>/dev/null | sort \
      | while IFS= read -r f; do printf 'FILE\t%s\n' "$f"; tr -d '\r' < "$f"; echo; done
  fi
} | awk -F'\t' '
function val(s) { sub(/^[a-z]+=/, "", s); return s }
function pct(a, b) { return b ? sprintf("%d%%", (100 * a / b) + 0.5) : "-" }
function flush(   b) {
  if (!run) return
  runs++
  if (fin != "") closed++
  if (wj != "") {
    wn++
    if (wj == "unavailable") wu++
    else {
      b = (wc >= 0.80) ? 1 : (wc >= 0.50 ? 2 : 3)
      bn[b]++; if (wj == wt) bt[b]++
      if (fin != "") { bfn[b]++; if (wj == fin) bf[b]++ }
    }
  }
  if (ov == "yes") { ovn++; if (wj == fin) ovj++ }
  if (dj != "" && dj != "unavailable" && fin != "") {
    dn[dj]++; df[dj] += files; if (rw > 0) dr[dj]++
    if (dj == "low" && (files >= 6 || rw >= 2)) invl++
    if (dj == "high" && files <= 1 && rw == 0) invh++
  }
}
$1 == "FILE"       { flush(); run = 1; wj = wt = dj = fin = ov = ""; wc = 0; files = rw = 0; next }
$2 == "workflow"   { wj = val($3); wc = val($4) + 0; wt = val($5) }
$2 == "difficulty" { dj = val($3) }
$2 == "outcome"    { fin = val($3); ov = val($4); files = val($5) + 0; rw = val($6) + 0 }
END {
  flush()
  printf "Routing logs: %d runs, %d closed\n", runs, closed
  printf "Workflow: %d decisions, %d unavailable\n", wn, wu
  print  "  band       n  agrees-final  agrees-team"
  split(">=0.80|0.50-0.79|<0.50", name, "|")
  for (b = 1; b <= 3; b++)
    printf "  %s  %d  %s  %s\n", name[b], bn[b], pct(bf[b], bfn[b]), pct(bt[b], bn[b])
  printf "  User overrides: %d; the service had named the final workflow in %d\n", ovn, ovj
  print  "Difficulty (Bug Fix / Small Change, closed runs):"
  print  "  jev  n  mean-files  with-rework"
  split("low|medium|high", lv, "|")
  for (i = 1; i <= 3; i++) {
    k = lv[i]
    printf "  %s  %d  %s  %s\n", k, dn[k], dn[k] ? sprintf("%.1f", df[k] / dn[k]) : "-", pct(dr[k], dn[k])
  }
  printf "  Inversions: low with files>=6 or rework>=2: %d; high with files<=1 and rework=0: %d\n", invl, invh
  # Outages are not decisions, and a percentage over a handful of runs is not
  # evidence: the gate needs 150 answered decisions and 50 closed confident ones.
  answered = wn - wu
  met = (answered >= 150 && bfn[1] >= 50 && 100 * bf[1] / bfn[1] >= 95) ? "met" : "not met"
  printf "Phase 2 exit: %d/150 answered workflow decisions; high-confidence agreement %s over %d closed (need >=95%% over >=50) -> %s\n", answered, pct(bf[1], bfn[1]), bfn[1], met
}'
exit 0
