#!/usr/bin/env bash
# Repo-only test of checks/verify-knowledge-shape.sh and of the unclassified
# sweep of checks/verify-knowledge-integrity.sh for the entries the manifest
# names rulesDir, proposalsDir and baselineFile. The fixtures hold authored
# lines the runtime check must find, so this test never ships.
#
#   verify-shape-check.sh
#
# Exit 0 = every case behaved as expected. Exit 1 = a case failed.
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/verify-knowledge-shape.sh"
INTEGRITY="$HERE/verify-knowledge-integrity.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/shape-check.XXXXXX")" || exit 1
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

mk() { rm -rf "$WORK/k"; mkdir -p "$WORK/k/rules"; }

mk_rule() {
  printf '%s\n' '# Keep the gateway thin' '- Kind: rule' '- Rule: Keep the gateway free of business logic.' \
    '- Source: user' '- Added: 2026-11-11' > "$WORK/k/rules/$1.md"
}

rm -rf "$WORK/k"; mkdir -p "$WORK/k"; printf '%s\n' '# A' > "$WORK/k/A.md"
run_case "no rules dir" 0 "knowledge shape: ok" "$WORK/k"

mk; mk_rule a
printf '%s\n' '# Payments' '- Kind: critical-zone' '- Zone: src/pay/** — money movement' '- Source: user' '- Added: 2026-11-11' > "$WORK/k/rules/b.md"
printf '%s\n' '# One exception' '- Kind: exception' '- Exception: src/x.ext · "call()" · rule:a — accepted 2026-11-11: "legacy" (run F-1)' '- Source: proposal x.md' '- Added: 2026-11-11' > "$WORK/k/rules/c.md"
run_case "one of each kind" 0 "knowledge shape: ok" "$WORK/k"

mk
printf '%s\r\n' '# Keep the gateway thin' '- Kind: rule' '- Rule: Keep it thin.' '- Source: user' '- Added: 2026-11-11' > "$WORK/k/rules/a.md"
run_case "crlf rule" 0 "knowledge shape: ok" "$WORK/k"

mk; printf '%s' '# Last line has no newline' > /dev/null
printf '%s\n' '# T' '- Kind: rule' '- Rule: R.' '- Source: user' > "$WORK/k/rules/a.md"; printf '%s' '- Added: 2026-11-11' >> "$WORK/k/rules/a.md"
run_case "final line without newline" 0 "" "$WORK/k"

mk; printf '%s\n' '# T' '- Rule: R.' '- Source: user' '- Added: 2026-11-11' > "$WORK/k/rules/nokind.md"
run_case "no kind" 1 "rules/nokind.md" "$WORK/k"

mk; printf '%s\n' '# T' '- Kind: other' '- Rule: R.' '- Source: user' '- Added: 2026-11-11' > "$WORK/k/rules/other.md"
run_case "kind other" 1 "rules/other.md" "$WORK/k"

mk; printf '%s\n' '# T' '- Kind: rule' '- Kind: rule' '- Rule: R.' '- Source: user' '- Added: 2026-11-11' > "$WORK/k/rules/twice.md"
run_case "kind twice" 1 "rules/twice.md" "$WORK/k"

mk; printf '%s\n' '# T' '- Kind: critical-zone' '- Rule: R.' '- Source: user' '- Added: 2026-11-11' > "$WORK/k/rules/zone.md"
run_case "zone without Zone" 1 "rules/zone.md" "$WORK/k"

mk; printf '%s\n' 'T' '- Kind: rule' '- Rule: R.' '- Source: user' '- Added: 2026-11-11' > "$WORK/k/rules/notitle.md"
run_case "first line not a title" 1 "rules/notitle.md" "$WORK/k"

mk; printf '%s\n' '# T' '- Kind: rule' '- Rule: R.' '- Added: 2026-11-11' > "$WORK/k/rules/nosource.md"
run_case "no source" 1 "rules/nosource.md" "$WORK/k"

mk; printf '%s\n' '# T' '- Kind: rule' '- Rule: R.' '- Source: user' > "$WORK/k/rules/noadded.md"
run_case "no added" 1 "rules/noadded.md" "$WORK/k"

mk; printf '%s\n' '# T' '- Kind: rule' '- Rule: R.' '- Source: user' '- Added: 2026-11-11' > "$WORK/k/rules/long.md"
for i in 1 2 3 4 5 6 7; do echo "note $i" >> "$WORK/k/rules/long.md"; done
run_case "twelve lines" 0 "" "$WORK/k"
echo "note 8" >> "$WORK/k/rules/long.md"
run_case "thirteen lines" 1 "rules/long.md" "$WORK/k"

mk; mk_rule a
printf '%s\n' '# Rules' '- keep it thin — source: user' > "$WORK/k/PROJECT-RULES.md"
run_case "authored user line" 1 "PROJECT-RULES.md:2: authored line in a generated file" "$WORK/k"

mk; printf '%s\n' '# Rules' '- keep it thin — source: user' | sed 's/$/\r/' > "$WORK/k/PROJECT-RULES.md"
run_case "authored user line, crlf" 1 "PROJECT-RULES.md:2:" "$WORK/k"

mk; mkdir -p "$WORK/k/backend-architecture"
printf '%s\n' '# A' 'x' '- a trap — source: learnings 2026-10-01 Foo' > "$WORK/k/backend-architecture/a.md"
run_case "authored learnings line in a topic" 1 "backend-architecture/a.md:3: authored line in a generated file" "$WORK/k"

mk; mkdir -p "$WORK/k/proposals"
printf '%s\n' '# T' '- Kind: rule' '- Rule: R. — source: learnings 2026-10-01 Foo' '- Source: user' '- Added: 2026-11-11' > "$WORK/k/rules/x.md"
printf '%s\n' '- a — source: learnings 2026-10-01 Foo' '- b — source: user' > "$WORK/k/proposals/y.md"
run_case "same text in rules and proposals" 0 "knowledge shape: ok" "$WORK/k"

mk
for i in $(seq 1 61); do mk_rule "r$i"; done
run_case "sixty-one rules" 1 "rules: 61 files, the budget is 60" "$WORK/k"
rm "$WORK/k/rules/r61.md"
run_case "sixty rules" 0 "" "$WORK/k"

run_case "missing dir" 2 "" "$WORK/does-not-exist"

# --- the integrity check's sweep ---------------------------------------------
# A fixture team root: the checks directory and a manifest, so the integrity
# check reads its classification and keys from there.
mkdir -p "$WORK/root/checks" "$WORK/b" "$WORK/c/rules" "$WORK/c/proposals"
cp "$INTEGRITY" "$WORK/root/checks/"
cp "$HERE/../team-manifest.json" "$WORK/root/"
for d in b c; do
  mkdir -p "$WORK/$d/rules" "$WORK/$d/proposals"
  echo x > "$WORK/$d/rules/a.md"; echo x > "$WORK/$d/proposals/b.md"; echo x > "$WORK/$d/BASELINE"
done
out="$(bash "$WORK/root/checks/verify-knowledge-integrity.sh" "$WORK/b" "$WORK/c" 2>&1)"; rc=$?
[ "$rc" = 0 ] || fail "integrity with rules, proposals, BASELINE: exit $rc ($out)"
case "$out" in *"not classified"*) fail "integrity: reported unclassified ($out)";; esac

mkdir -p "$WORK/c/stray"
out="$(bash "$WORK/root/checks/verify-knowledge-integrity.sh" "$WORK/b" "$WORK/c" 2>&1)"; rc=$?
[ "$rc" = 1 ] || fail "integrity with a stray dir: exit $rc, wanted 1 ($out)"

if [ "$FAILS" -gt 0 ]; then exit 1; fi
echo "shape check: ok"
