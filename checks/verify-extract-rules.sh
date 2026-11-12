#!/usr/bin/env bash
# Repo-only test of tools/extract-rules.sh against throwaway knowledge
# directories: learnings-sourced lines grouped by their suffix into one rule
# file, user critical zones, user rules, accepted exceptions and their
# heading, CRLF files kept byte for byte, slugs taken twice, a second run, a
# dry run and a topic file. The fixtures hold authored lines, so this test
# never ships.
#
#   bash checks/verify-extract-rules.sh    (run from anywhere)
#
# Exit 0 = every case passed (prints "verify-extract-rules: ok"). 1 = a case
# failed; each failure is named.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/tools/extract-rules.sh"
SHAPE="$ROOT/checks/verify-knowledge-shape.sh"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
status=0
case=""
fail() { echo "FAIL [$case]: $*"; status=1; }

TODAY="$(date +%Y-%m-%d)"
EM="$(printf '\342\200\224')"   # the em dash, as bytes
K="$tmp/k"

[ -f "$TOOL" ] || { echo "FAIL: tools/extract-rules.sh is missing"; exit 1; }

mk() { rm -rf "$K"; mkdir -p "$K"; }
run() { bash "$TOOL" "$@" > "$tmp/out" 2> "$tmp/err"; rc=$?; }
expect_rc() { [ "$rc" = "$1" ] || fail "expected exit $1, got $rc: $(head -c 600 "$tmp/out" "$tmp/err")"; }
out_is() { [ "$(cat "$tmp/out")" = "$1" ] || fail "output '$(cat "$tmp/out")', expected '$1'"; }
# file_is <file> <expected bytes, as a printf format with no arguments>
file_is() {
  printf "$2" > "$tmp/expected"
  cmp -s "$tmp/expected" "$1" || fail "$1 differs: $(od -c "$1" | head -20)"
}
shape_ok() {
  bash "$SHAPE" "$K" > "$tmp/shape" 2>&1 || fail "shape check failed: $(cat "$tmp/shape")"
}
snap() {
  (cd "$1" && { find . -print | LC_ALL=C sort; find . -type f -exec sha1sum {} + | LC_ALL=C sort -k2; })
}
# the slug templates/learnings-entry.md derives from a title
slug() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//' | cut -c1-60 | sed 's/-$//'
}

# --- (a) one suffix in a rules file and in the checklist --------------------------
case="a: rule and check"
mk
printf '# Project Rules\n\n- Keep the build green.\n- Build cache keys with the helper %s source: learnings 2026-10-01 Cache key\n- Last obligation.\n' "$EM" > "$K/PROJECT-RULES.md"
printf '# Review checklist\n\n6. Check inputs.\n7. A cache key is built by the helper %s source: learnings 2026-10-01 Cache key\n8. Last item.\n' "$EM" > "$K/REVIEW-CHECKLIST.md"
rm -rf "$tmp/a.copy"; cp -R "$K" "$tmp/a.copy"
run "$K"
expect_rc 0
out_is "rules: extracted 1 (1 rules, 0 critical zones, 0 exceptions) into $K/rules"
file_is "$K/rules/cache-key.md" "# Cache key\n- Kind: rule\n- Rule: Build cache keys with the helper\n- Check: A cache key is built by the helper\n- Belongs with: PROJECT-RULES.md\n- Source: learnings 2026-10-01 Cache key\n- Added: $TODAY\n"
file_is "$K/PROJECT-RULES.md" "# Project Rules\n\n- Keep the build green.\n- Last obligation.\n"
file_is "$K/REVIEW-CHECKLIST.md" "# Review checklist\n\n6. Check inputs.\n8. Last item.\n"
[ "$(ls "$K/rules" | wc -l | tr -d ' ')" = 1 ] || fail "expected one rule file: $(ls "$K/rules")"
shape_ok

# --- (g) a second run ----------------------------------------------------------------
case="g: second run"
before="$(snap "$K")"
run "$K"
expect_rc 0
out_is "rules: nothing to extract"
[ "$before" = "$(snap "$K")" ] || fail "a second run changed files"

# --- (h) dry run -------------------------------------------------------------------------
case="h: dry run"
rm -rf "$K"; cp -R "$tmp/a.copy" "$K"
before="$(snap "$K")"
run --dry-run "$K"
expect_rc 0
out_is "would: rules: extracted 1 (1 rules, 0 critical zones, 0 exceptions) into $K/rules"
[ "$before" = "$(snap "$K")" ] || fail "a dry run changed files"
[ ! -e "$K/rules" ] || fail "a dry run created rules/"
mk; printf '# Project Rules\n\n- Plain.\n' > "$K/PROJECT-RULES.md"
run --dry-run "$K"
expect_rc 0
out_is "would: rules: nothing to extract"

# --- (b) a user critical zone and a user rule ----------------------------------------
case="b: critical zone and user rule"
mk
LONG="Always run the formatter on every changed file before the review starts"
printf '# Project Rules\n\n- Keep it.\n- %s %s source: user\n\n## Critical zones\n\n- src/pay/** %s money %s source: user\n- deploy/** %s release definitions\n' \
  "$LONG" "$EM" "$EM" "$EM" "$EM" > "$K/PROJECT-RULES.md"
run "$K"
expect_rc 0
out_is "rules: extracted 2 (1 rules, 1 critical zones, 0 exceptions) into $K/rules"
file_is "$K/rules/src-pay.md" "# src/pay/**\n- Kind: critical-zone\n- Zone: src/pay/** $EM money\n- Source: user\n- Added: $TODAY\n"
T60="$(printf '%s' "$LONG" | cut -c1-60)"
file_is "$K/rules/$(slug "$T60").md" "# $T60\n- Kind: rule\n- Rule: $LONG\n- Belongs with: PROJECT-RULES.md\n- Source: user\n- Added: $TODAY\n"
file_is "$K/PROJECT-RULES.md" "# Project Rules\n\n- Keep it.\n\n## Critical zones\n\n- deploy/** $EM release definitions\n"
shape_ok

# --- (c) a checklist-only line ----------------------------------------------------------
case="c: checklist only"
mk
printf '# Review checklist\n\n3. Every handler logs its errors %s source: learnings 2026-10-02 Logged errors\n' "$EM" > "$K/REVIEW-CHECKLIST.md"
run "$K"
expect_rc 0
out_is "rules: extracted 1 (1 rules, 0 critical zones, 0 exceptions) into $K/rules"
file_is "$K/rules/logged-errors.md" "# Logged errors\n- Kind: rule\n- Rule: Every handler logs its errors\n- Check: Every handler logs its errors\n- Belongs with: REVIEW-CHECKLIST.md\n- Source: learnings 2026-10-02 Logged errors\n- Added: $TODAY\n"
file_is "$K/REVIEW-CHECKLIST.md" "# Review checklist\n\n"
shape_ok

# --- (d) accepted exceptions ------------------------------------------------------------
case="d: accepted exceptions"
mk
X1="src/a.txt · \"x = 1\" · 1 $EM accepted 2026-10-01: \"fine\" (run1 F-1)"
X2="src/b.txt · \"y = 2\" · 1 $EM accepted 2026-10-02: \"ok\" (run2 F-3)"
printf '# Review checklist\n\n1. Item.\n\n## Accepted exceptions\n\n- %s\n- %s\n\n## After\n- tail\n' "$X1" "$X2" > "$K/REVIEW-CHECKLIST.md"
run "$K"
expect_rc 0
out_is "rules: extracted 2 (0 rules, 0 critical zones, 2 exceptions) into $K/rules"
file_is "$K/rules/exception-src-a-txt.md" "# exception src/a.txt\n- Kind: exception\n- Exception: $X1\n- Source: user\n- Added: $TODAY\n"
file_is "$K/rules/exception-src-b-txt.md" "# exception src/b.txt\n- Kind: exception\n- Exception: $X2\n- Source: user\n- Added: $TODAY\n"
file_is "$K/REVIEW-CHECKLIST.md" "# Review checklist\n\n1. Item.\n\n## After\n- tail\n"
shape_ok

case="d: accepted exceptions at the end of the file"
mk
printf '# Review checklist\n\n1. Item.\n\n## Accepted exceptions\n- %s\n' "$X1" > "$K/REVIEW-CHECKLIST.md"
run "$K"
expect_rc 0
out_is "rules: extracted 1 (0 rules, 0 critical zones, 1 exceptions) into $K/rules"
file_is "$K/REVIEW-CHECKLIST.md" "# Review checklist\n\n1. Item.\n\n"

case="d: none"
mk
printf '# Review checklist\n\n1. Item.\n\n## Accepted exceptions\n\n- none\n' > "$K/REVIEW-CHECKLIST.md"
before="$(snap "$K")"
run "$K"
expect_rc 0
out_is "rules: nothing to extract"
[ "$before" = "$(snap "$K")" ] || fail "a section holding - none changed"

# --- (e) CRLF sources --------------------------------------------------------------------
case="e: CRLF"
mk
printf '# Rules\r\n\r\n- Keep.\r\n- Rule A text %s source: learnings 2026-10-03 Rule A\r\n- Middle.\r\n\r\n## Critical zones\r\n\r\n- infra/** %s secrets %s source: user\r\n- Tail line' "$EM" "$EM" "$EM" > "$K/PROJECT-RULES.md"
printf '# Checklist\r\n\r\n1. One.\r\n2. Rule A is checked %s source: learnings 2026-10-03 Rule A' "$EM" > "$K/REVIEW-CHECKLIST.md"
run "$K"
expect_rc 0
out_is "rules: extracted 2 (1 rules, 1 critical zones, 0 exceptions) into $K/rules"
file_is "$K/PROJECT-RULES.md" "# Rules\r\n\r\n- Keep.\r\n- Middle.\r\n\r\n## Critical zones\r\n\r\n- Tail line"
file_is "$K/REVIEW-CHECKLIST.md" "# Checklist\r\n\r\n1. One.\r\n"
od -c "$K/PROJECT-RULES.md" | grep -q '\\r  \\n' || fail "no CR left in PROJECT-RULES.md: $(od -c "$K/PROJECT-RULES.md" | head -5)"
file_is "$K/rules/rule-a.md" "# Rule A\n- Kind: rule\n- Rule: Rule A text\n- Check: Rule A is checked\n- Belongs with: PROJECT-RULES.md\n- Source: learnings 2026-10-03 Rule A\n- Added: $TODAY\n"
file_is "$K/rules/infra.md" "# infra/**\n- Kind: critical-zone\n- Zone: infra/** $EM secrets\n- Source: user\n- Added: $TODAY\n"
! grep -q "$(printf '\r')" "$K/rules/rule-a.md" "$K/rules/infra.md" || fail "a rule file carries a CR"
shape_ok

# --- (f) two titles, one slug --------------------------------------------------------
case="f: one slug twice"
mk
printf '# Project Rules\n\n- First %s source: learnings 2026-10-01 Same title\n- Second %s source: learnings 2026-10-02 Same Title!\n' "$EM" "$EM" > "$K/PROJECT-RULES.md"
run "$K"
expect_rc 0
out_is "rules: extracted 2 (2 rules, 0 critical zones, 0 exceptions) into $K/rules"
grep -qxF -- "- Rule: First" "$K/rules/same-title.md" 2>/dev/null || fail "same-title.md: $(ls "$K/rules")"
grep -qxF -- "- Rule: Second" "$K/rules/same-title-2.md" 2>/dev/null || fail "same-title-2.md: $(ls "$K/rules")"
shape_ok

case="f: the name exists already"
mk; mkdir -p "$K/rules"
printf '# Same title\n- Kind: rule\n- Rule: Older\n- Source: user\n- Added: 2026-01-01\n' > "$K/rules/same-title.md"
cp "$K/rules/same-title.md" "$tmp/older"
printf '# Project Rules\n\n- First %s source: learnings 2026-10-01 Same title\n- Second %s source: learnings 2026-10-02 Same Title!\n' "$EM" "$EM" > "$K/PROJECT-RULES.md"
run "$K"
expect_rc 0
cmp -s "$tmp/older" "$K/rules/same-title.md" || fail "an existing rule file was overwritten"
grep -qxF -- "- Rule: First" "$K/rules/same-title-2.md" 2>/dev/null || fail "same-title-2.md: $(ls "$K/rules")"
grep -qxF -- "- Rule: Second" "$K/rules/same-title-3.md" 2>/dev/null || fail "same-title-3.md: $(ls "$K/rules")"

# --- (i) a topic file ------------------------------------------------------------------------
case="i: topic file"
mk; mkdir -p "$K/coding-standards"
printf '# Coding standards\n\n- errors: coding-standards/errors.md\n' > "$K/CODING-STANDARDS.md"
printf '# Errors\n\n- Wrap every error %s source: learnings 2026-10-04 Wrapped errors\n- Keep.\n' "$EM" > "$K/coding-standards/errors.md"
run "$K"
expect_rc 0
out_is "rules: extracted 1 (1 rules, 0 critical zones, 0 exceptions) into $K/rules"
file_is "$K/rules/wrapped-errors.md" "# Wrapped errors\n- Kind: rule\n- Rule: Wrap every error\n- Belongs with: CODING-STANDARDS.md\n- Source: learnings 2026-10-04 Wrapped errors\n- Added: $TODAY\n"
file_is "$K/coding-standards/errors.md" "# Errors\n\n- Keep.\n"
shape_ok

# --- (j) one suffix in several non-checklist files ------------------------------------------
# The first found is Rule:; the same wording again goes silently; other
# wording gets a file of its own.
case="j: every wording kept"
mk
printf '# Project Rules\n\n- From rules %s source: learnings 2026-10-05 Twice\n' "$EM" > "$K/PROJECT-RULES.md"
printf '# Coding standards\n\n- From standards %s source: learnings 2026-10-05 Twice\n' "$EM" > "$K/CODING-STANDARDS.md"
printf '# DI and startup\n\n- From standards %s source: learnings 2026-10-05 Twice\n- Keep.\n' "$EM" > "$K/DI-AND-STARTUP.md"
run "$K"
expect_rc 0
out_is "rules: extracted 2 (2 rules, 0 critical zones, 0 exceptions) into $K/rules"
file_is "$K/rules/twice.md" "# Twice\n- Kind: rule\n- Rule: From standards\n- Belongs with: CODING-STANDARDS.md\n- Source: learnings 2026-10-05 Twice\n- Added: $TODAY\n"
file_is "$K/rules/twice-2.md" "# Twice\n- Kind: rule\n- Rule: From rules\n- Belongs with: PROJECT-RULES.md\n- Source: learnings 2026-10-05 Twice\n- Added: $TODAY\n"
file_is "$K/DI-AND-STARTUP.md" "# DI and startup\n\n- Keep.\n"
[ "$(ls "$K/rules" | wc -l | tr -d ' ')" = 2 ] || fail "expected two rule files: $(ls "$K/rules")"
shape_ok

# --- (k) two checklist lines on one suffix ------------------------------------------------
case="k: two checklist wordings"
mk
printf '# Project Rules\n\n- Never cache tokens on disk %s source: learnings 2026-10-05 Tokens\n' "$EM" > "$K/PROJECT-RULES.md"
printf '# Coding standards\n\n- Store tokens only in memory, and clear them on logout %s source: learnings 2026-10-05 Tokens\n' "$EM" > "$K/CODING-STANDARDS.md"
printf '# Review checklist\n\n1. Tokens are kept in memory only %s source: learnings 2026-10-05 Tokens\n2. Logout clears the token %s source: learnings 2026-10-05 Tokens\n3. Tokens are kept in memory only %s source: learnings 2026-10-05 Tokens\n4. Other.\n' "$EM" "$EM" "$EM" > "$K/REVIEW-CHECKLIST.md"
run "$K"
expect_rc 0
out_is "rules: extracted 3 (3 rules, 0 critical zones, 0 exceptions) into $K/rules"
file_is "$K/rules/tokens.md" "# Tokens\n- Kind: rule\n- Rule: Store tokens only in memory, and clear them on logout\n- Check: Tokens are kept in memory only\n- Belongs with: CODING-STANDARDS.md\n- Source: learnings 2026-10-05 Tokens\n- Added: $TODAY\n"
file_is "$K/rules/tokens-2.md" "# Tokens\n- Kind: rule\n- Rule: Never cache tokens on disk\n- Belongs with: PROJECT-RULES.md\n- Source: learnings 2026-10-05 Tokens\n- Added: $TODAY\n"
file_is "$K/rules/tokens-3.md" "# Tokens\n- Kind: rule\n- Rule: Logout clears the token\n- Check: Logout clears the token\n- Belongs with: REVIEW-CHECKLIST.md\n- Source: learnings 2026-10-05 Tokens\n- Added: $TODAY\n"
file_is "$K/REVIEW-CHECKLIST.md" "# Review checklist\n\n4. Other.\n"
[ "$(ls "$K/rules" | wc -l | tr -d ' ')" = 3 ] || fail "expected three rule files: $(ls "$K/rules")"
shape_ok

# --- (l) a line with no text stays -----------------------------------------------------------
case="l: empty text stays"
mk
printf '# Project Rules\n\n- %s source: user\n-  %s source: learnings 2026-10-06 Empty\n3. %s source: user\n- Real %s source: user\n' "$EM" "$EM" "$EM" "$EM" > "$K/PROJECT-RULES.md"
run "$K"
expect_rc 0
out_is "rules: extracted 1 (1 rules, 0 critical zones, 0 exceptions) into $K/rules"
file_is "$K/PROJECT-RULES.md" "# Project Rules\n\n- $EM source: user\n-  $EM source: learnings 2026-10-06 Empty\n3. $EM source: user\n"
grep -qxF -- "- Rule: Real" "$K/rules/real.md" 2>/dev/null || fail "real.md: $(ls "$K/rules")"
bash "$SHAPE" "$K" > "$tmp/shape" 2>&1; src=$?
[ "$src" = 1 ] || fail "shape check exit $src, expected 1: $(cat "$tmp/shape")"
[ "$(grep -c 'authored line in a generated file' "$tmp/shape")" = 3 ] || fail "shape check should list the three lines: $(cat "$tmp/shape")"

# --- unreadable directory, usage ------------------------------------------------------------
case="unreadable directory"
run "$tmp/missing"
expect_rc 2
run
expect_rc 2

[ "$status" = 0 ] && echo "verify-extract-rules: ok"
exit "$status"
