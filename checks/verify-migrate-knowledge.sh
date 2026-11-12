#!/usr/bin/env bash
# Tests tools/migrate-knowledge.sh against throwaway projects, each a fresh git
# repository with the real team tree copied to .claude/: the operative files
# moving out, the project files waiting or moving to the committed directory,
# authored lines of a private copy kept as inbox entries, the refusals and
# that a refusal changes nothing, dry run, reruns, dropping the private copy,
# what the resolver prints afterwards, and the inbox moving into the profile
# (DREAM_TEAM_PROFILE in the temporary directory, never the real one): entries
# lifted out of an old LEARNINGS.md, two copies of one repository, the
# fallbacks that keep the inbox per copy.
#
#   bash checks/verify-migrate-knowledge.sh    (run from anywhere)
#
# Exit 0 = every case passed. 1 = a case failed; each failure is named.
# Repo-only: it never ships to the Copilot edition, so fixtures spell team
# paths literally.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/migrate-knowledge.sh"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
# Never the real profile.
export DREAM_TEAM_PROFILE="$tmp/profile"
status=0
case=""
fail() { echo "FAIL [$case]: $*" >&2; status=1; }

OLD=".claude/knowledge"
NEW=".dream-team/knowledge"
OPS=".dream-team-tracking/operative"
CAPS=".dream-team-tracking/operative/claude"
OTHER=".github/dream-team/knowledge"
TODAY="$(date +%Y-%m-%d)"
EM="$(printf '\342\200\224')"   # the em dash, as bytes

# The real team tree, copied once; every fixture copies it to .claude/.
TEAM="$tmp/team"
mkdir -p "$TEAM"
for d in agents skills templates tools checks hooks team-manifest.json; do
  [ -e "$ROOT/$d" ] && cp -R "$ROOT/$d" "$TEAM/"
done

# old_index <file>: a LEARNINGS.md as deployments before the derived index
# kept it; the migration still moves one, byte for byte, and never writes it.
old_index() {
  printf '# Dream Team Learnings Inbox\n\n## Index\n\n| Date | Title | Tags |\n|------|-------|------|\n| 2026-10-01 | A | a |\n' > "$1"
}

git_commit() { git -c user.name=t -c user.email=t@example.invalid -c core.autocrlf=false commit -qm "$1" >/dev/null; }

# new_project <name> [operative]: a git repository with the team at .claude/
# and a legacy knowledge directory holding project files (top-level and a
# topic subdirectory); with "operative", also LEARNINGS.md, learnings/a.md and
# CAPABILITIES.md.
new_project() {
  P="$tmp/$1"
  mkdir -p "$P"
  (cd "$P" && git init -q)
  cp -R "$TEAM" "$P/.claude"
  mkdir -p "$P/$OLD/REVIEW-CHECKLIST"
  printf '# Overview\n\nA project.\n' > "$P/$OLD/PROJECT-OVERVIEW.md"
  printf '# Project Rules\n\n- Keep the build green.\n' > "$P/$OLD/PROJECT-RULES.md"
  printf '# Review checklist\n\nSee REVIEW-CHECKLIST/.\n' > "$P/$OLD/REVIEW-CHECKLIST.md"
  printf '# Security\n\n- Check every input.\n' > "$P/$OLD/REVIEW-CHECKLIST/security.md"
  if [ "${2:-}" = operative ]; then
    mkdir -p "$P/$OLD/learnings"
    old_index "$P/$OLD/LEARNINGS.md"
    printf '## [2026-10-01] A\n- **Tags:** a\n' > "$P/$OLD/learnings/a.md"
    printf '# Capabilities\n\n- shell: bash\n' > "$P/$OLD/CAPABILITIES.md"
  fi
  rm -rf "$tmp/$1.orig"; cp -R "$P/$OLD" "$tmp/$1.orig"
}
# commit_knowledge: the committed copy, tracked in this branch.
commit_knowledge() {
  (cd "$P" && git -c core.autocrlf=false add -- "$NEW" && git_commit "knowledge")
}

# Every path and every file's hash under a directory, .git excluded.
snap() {
  (cd "$1" && { find . -path ./.git -prune -o -print | LC_ALL=C sort
    find . -path ./.git -prune -o -type f -exec sha1sum {} + | LC_ALL=C sort -k2; })
}
run() { # [args]: run the migration in $P
  (cd "$P" && bash .claude/tools/migrate-knowledge.sh "$@") > "$tmp/out" 2> "$tmp/err"; rc=$?
}
has() { grep -qF -- "$2" "$1" || fail "$(basename "$1") lacks '$2': $(head -c 600 "$1")"; }
lacks() { ! grep -qF -- "$2" "$1" || fail "$(basename "$1") has '$2': $(head -c 600 "$1")"; }
same() { cmp -s "$1" "$2" || fail "$2 differs from $1"; }
expect_rc() { [ "$rc" = "$1" ] || fail "expected exit $1, got $rc: $(head -c 600 "$tmp/err")"; }
# the slug templates/learnings-entry.md derives from an entry's title
slug() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//' | cut -c1-60 | sed 's/-$//'
}

[ -f "$SCRIPT" ] || fail "tools/migrate-knowledge.sh is missing"

# --- (a) default mode, nothing tracked -------------------------------------
case="a: default, nothing tracked"
new_project a operative
run
expect_rc 0
same "$tmp/a.orig/LEARNINGS.md" "$P/$OPS/LEARNINGS.md"
same "$tmp/a.orig/learnings/a.md" "$P/$OPS/learnings/a.md"
same "$tmp/a.orig/CAPABILITIES.md" "$P/$CAPS/CAPABILITIES.md"
for f in LEARNINGS.md learnings CAPABILITIES.md; do [ ! -e "$P/$OLD/$f" ] || fail "$f still in $OLD"; done
for f in PROJECT-OVERVIEW.md PROJECT-RULES.md REVIEW-CHECKLIST.md REVIEW-CHECKLIST/security.md; do
  same "$tmp/a.orig/$f" "$P/$OLD/$f"
done
[ ! -e "$P/$NEW" ] || fail "$NEW was created"
has "$tmp/out" "operative: moved 3 entries to $OPS"
has "$tmp/out" "project: waiting for $NEW in the repository; the first knowledge commit is made with --first-commit"
has "$tmp/out" "operative: per-copy $OPS (no remote)"
[ ! -e "$P/$CAPS/.legacy-rules-imported" ] || fail "stamp written while nothing is tracked"

# --- (i) dry run on (a) -----------------------------------------------------
case="i: dry run"
new_project i operative
before="$(snap "$P")"; run --dry-run
expect_rc 0
has "$tmp/out" "would: operative: moved 3 entries to $OPS"
has "$tmp/out" "would: project: waiting for $NEW"
[ "$before" = "$(snap "$P")" ] || fail "a dry run changed files"
run --first-commit --dry-run
expect_rc 0
has "$tmp/out" "would: project: moved to $NEW: run /generate-knowledge"
[ "$before" = "$(snap "$P")" ] || fail "a first-commit dry run changed files"

# --- (b) --first-commit -----------------------------------------------------
case="b: first commit"
new_project b operative
run --first-commit
expect_rc 0
for f in PROJECT-OVERVIEW.md PROJECT-RULES.md REVIEW-CHECKLIST.md REVIEW-CHECKLIST/security.md; do
  same "$tmp/b.orig/$f" "$P/$NEW/$f"
done
[ ! -e "$P/$OLD" ] || fail "$OLD still there"
for f in LEARNINGS.md learnings CAPABILITIES.md; do [ ! -e "$P/$NEW/$f" ] || fail "$f moved into the committed directory"; done
same "$tmp/b.orig/LEARNINGS.md" "$P/$OPS/LEARNINGS.md"
same "$tmp/b.orig/CAPABILITIES.md" "$P/$CAPS/CAPABILITIES.md"
has "$tmp/out" "operative: moved 3 entries to $OPS"
has "$tmp/out" "project: moved to $NEW: run /generate-knowledge, then commit it alone, one commit and one pull request, no other file"

# --- (j) a second run right after (b) ----------------------------------------
case="j: rerun after first commit"
# The move is done and nothing is committed yet: the report says to commit
# the directory, never "nothing to move" or "made with --first-commit".
before="$(snap "$P")"; run
expect_rc 0
has "$tmp/out" "operative: nothing to move"
has "$tmp/out" "project: moved to $NEW: run /generate-knowledge, then commit it alone, one commit and one pull request, no other file"
lacks "$tmp/out" "nothing to move ("
lacks "$tmp/out" "made with --first-commit"
[ "$before" = "$(snap "$P")" ] || fail "a second run changed files"
run --first-commit
expect_rc 1
has "$tmp/err" "commit $NEW/ alone"
[ "$before" = "$(snap "$P")" ] || fail "a refused first commit changed files"
commit_knowledge
run
expect_rc 0
has "$tmp/out" "project: in place ($NEW)"

# --- (c) a tracked committed copy, authored lines in the private copy -----------
case="c: authored lines"
new_project c
mkdir -p "$P/$NEW"
printf '# Project Rules\n\n- Keep the build green.\n' > "$P/$NEW/PROJECT-RULES.md"
commit_knowledge
{ printf '# Project Rules\n\n- Keep the build green.\n'
  printf -- '- Always X %s source: user\n' "$EM"
  printf -- '- Never Y %s source: learnings 2026-10-01 Foo\n' "$EM"; } > "$P/$OLD/PROJECT-RULES.md"
rm -rf "$tmp/c.orig"; cp -R "$P/$OLD" "$tmp/c.orig"
kbefore="$(snap "$P/$OLD")"
run
expect_rc 0
has "$tmp/out" "operative: nothing to move"
has "$tmp/out" "project: in place ($NEW); private copy kept for branches without knowledge (2 authored lines kept as inbox entries)"
[ "$kbefore" = "$(snap "$P/$OLD")" ] || fail "$OLD changed"
E1="$P/$OPS/learnings/$TODAY-migrated-rule-1.md"; E2="$P/$OPS/learnings/$TODAY-migrated-rule-2.md"
[ -f "$E1" ] && [ -f "$E2" ] || fail "entries missing: $(ls "$P/$OPS/learnings" 2>&1)"
[ ! -e "$P/$OPS/learnings/$TODAY-migrated-rule-3.md" ] || fail "a third entry"
if [ -f "$E1" ] && [ -f "$E2" ]; then
  head -1 "$E1" | tr -d '\r' | grep -qxF "## [$TODAY] Migrated rule 1" || fail "entry 1 heading: $(head -1 "$E1")"
  tr -d '\r' < "$E1" | grep -qxF "[PROMOTE] PROJECT-RULES.md $EM Always X" || fail "entry 1 mark: $(cat "$E1")"
  tr -d '\r' < "$E2" | grep -qxF "[PROMOTE] PROJECT-RULES.md $EM Never Y" || fail "entry 2 mark: $(cat "$E2")"
  has "$E1" "- Always X $EM source: user"
  has "$E2" "- Never Y $EM source: learnings 2026-10-01 Foo"
  has "$E1" "- **Tags:** migration"
  # Submitted as a remark, the entry lands in committed knowledge: it names
  # no team path, and the rule's new home is a rule file.
  has "$E1" "the private copy's PROJECT-RULES.md holds an authored line"
  has "$E1" "a rule file in $NEW/rules/"
  lacks "$E1" "$OLD"
  mkdir -p "$tmp/c.neutral"; cp "$E1" "$E2" "$tmp/c.neutral/"
  bash "$ROOT/checks/verify-knowledge-neutral.sh" "$tmp/c.neutral" > "$tmp/c.neutral.out" 2>&1 \
    || fail "an imported entry names a team path: $(cat "$tmp/c.neutral.out")"
fi
[ ! -e "$P/$OPS/LEARNINGS.md" ] || fail "an index file was written"
# The derived index lists both, and each row's title names its entry file
# through the slug rule.
(cd "$P" && bash .claude/tools/learnings-index.sh "$OPS/learnings") > "$tmp/index" 2>&1
has "$tmp/index" "| $TODAY | Migrated rule 1 | migration | $OPS/learnings/$TODAY-migrated-rule-1.md |"
has "$tmp/index" "| $TODAY | Migrated rule 2 | migration | $OPS/learnings/$TODAY-migrated-rule-2.md |"
sed -n 's/^| \([0-9-]*\) | \(Migrated rule [0-9]*\) | migration | .*\/\([^/]*\) |$/\1\t\2\t\3/p' "$tmp/index" > "$tmp/rows"
[ "$(wc -l < "$tmp/rows" | tr -d ' ')" = 2 ] || fail "expected 2 migrated rows: $(cat "$tmp/index")"
while IFS="$(printf '\t')" read -r d t f; do
  [ "$f" = "$d-$(slug "$t").md" ] || fail "row '$t' names $f, not its slug"
done < "$tmp/rows"
[ -f "$P/$CAPS/.legacy-rules-imported" ] || fail "no stamp"
has "$P/$CAPS/.legacy-rules-imported" "$TODAY"
has "$P/$CAPS/.legacy-rules-imported" "lines=2"
(cd "$P" && bash .claude/checks/verify-learnings-inbox.sh "$OPS/learnings") > "$tmp/inbox" 2>&1; irc=$?
[ "$irc" = 1 ] || fail "inbox check exit $irc, expected 1 (pending marks): $(cat "$tmp/inbox")"
has "$tmp/inbox" "2 pending marks"
lacks "$tmp/inbox" "longer than"

case="c: second run"
before="$(snap "$P")"; run
expect_rc 0
has "$tmp/out" "project: in place ($NEW)"
lacks "$tmp/out" "private copy kept"
[ "$before" = "$(snap "$P")" ] || fail "a second run changed files"

# --- (k) --drop-legacy ----------------------------------------------------------
case="k: drop legacy after (c)"
# The stamp is present; a line authored since must still reach the inbox,
# once, and the two already there must not come again.
printf -- '- Third Z %s source: user\n' "$EM" >> "$P/$OLD/PROJECT-RULES.md"
rm -rf "$tmp/c.drop"; cp -R "$P/$OLD" "$tmp/c.drop"
run --drop-legacy --dry-run
expect_rc 0
has "$tmp/out" "would: project: private copy removed (backup $OPS/legacy-knowledge-"
has "$tmp/out" "; 1 authored lines kept as inbox entries)"
[ -d "$P/$OLD" ] || fail "a dry run removed $OLD"
run --drop-legacy
expect_rc 0
[ ! -e "$P/$OLD" ] || fail "$OLD still there"
bk="$(ls -d "$P/$OPS"/legacy-knowledge-* 2>/dev/null | head -1)"
[ -n "$bk" ] || fail "no backup"
[ -n "$bk" ] && { diff -r "$tmp/c.drop" "$bk" > "$tmp/diff" 2>&1 || fail "backup differs: $(head -c 400 "$tmp/diff")"; }
has "$tmp/out" "project: private copy removed (backup $OPS/legacy-knowledge-"
has "$tmp/out" "; 1 authored lines kept as inbox entries)"
[ -f "$P/$OPS/learnings/$TODAY-migrated-rule-1.md" ] || fail "an entry was lost"
E3="$P/$OPS/learnings/$TODAY-migrated-rule-3.md"
[ -f "$E3" ] && { tr -d '\r' < "$E3" | grep -qxF "[PROMOTE] PROJECT-RULES.md $EM Third Z" || fail "entry 3 mark: $(cat "$E3")"; } \
  || fail "the line authored after the stamp was not kept: $(ls "$P/$OPS/learnings")"
[ "$(ls "$P/$OPS/learnings" | grep -c -e '-migrated-rule-')" = 3 ] || fail "expected exactly 3 entries: $(ls "$P/$OPS/learnings")"
for r in "Always X" "Never Y" "Third Z"; do
  [ "$(cat "$P/$OPS/learnings"/*.md | tr -d '\r' | grep -cxF "[PROMOTE] PROJECT-RULES.md $EM $r")" = 1 ] || fail "'$r' is not in the inbox exactly once"
done
[ ! -e "$P/$OPS/LEARNINGS.md" ] || fail "an index file was written"
(cd "$P" && bash .claude/tools/learnings-index.sh "$OPS/learnings") > "$tmp/index" 2>&1
[ "$(grep -c '| Migrated rule ' "$tmp/index")" = 3 ] || fail "expected 3 derived index rows: $(cat "$tmp/index")"

case="k: drop legacy, nothing tracked"
new_project k operative
before="$(snap "$P")"; run --drop-legacy
expect_rc 1
[ "$before" = "$(snap "$P")" ] || fail "a refused drop changed files"
run --drop-legacy --dry-run
expect_rc 1

# --- (d) one line already committed, CRLF private copy, existing entries ---------
case="d: one line already committed"
new_project d
mkdir -p "$P/$NEW" "$P/$OLD/learnings"
{ printf '# Project Rules\n\n- Keep the build green.\n'; printf -- '- Always X %s source: user\n' "$EM"; } > "$P/$NEW/PROJECT-RULES.md"
commit_knowledge
{ printf '# Project Rules\r\n\r\n- Keep the build green.\r\n'
  printf -- '- Always X %s source: user\r\n' "$EM"
  printf -- '- Never Y %s source: learnings 2026-10-01 Foo\r\n' "$EM"; } > "$P/$OLD/PROJECT-RULES.md"
# an index from an earlier migration, CRLF, holding Migrated rule 4
printf '# Dream Team Learnings Inbox\r\n\r\n## Index\r\n\r\n| Date | Title | Tags |\r\n|------|-------|------|\r\n| 2026-10-01 | Migrated rule 4 | migration |\r\n' > "$P/$OLD/LEARNINGS.md"
cp "$P/$OLD/LEARNINGS.md" "$tmp/d.index"
printf '## [2026-10-01] Migrated rule 4\r\n- **Tags:** migration\r\n' > "$P/$OLD/learnings/2026-10-01-migrated-rule-4.md"
run
expect_rc 0
has "$tmp/out" "operative: moved 2 entries to $OPS"
has "$tmp/out" "(1 authored lines kept as inbox entries)"
E5="$P/$OPS/learnings/$TODAY-migrated-rule-5.md"
[ -f "$E5" ] || fail "entry not numbered after the highest: $(ls "$P/$OPS/learnings")"
[ -f "$E5" ] && { tr -d '\r' < "$E5" | grep -qxF "[PROMOTE] PROJECT-RULES.md $EM Never Y" || fail "entry 5 mark: $(cat "$E5")"; }
[ -z "$(ls "$P/$OPS/learnings" | grep -e '-migrated-rule-[1-36]\.md$')" ] || fail "unexpected entry: $(ls "$P/$OPS/learnings")"
# the older index moves byte for byte and gains no row
same "$tmp/d.index" "$P/$OPS/LEARNINGS.md"
has "$P/$CAPS/.legacy-rules-imported" "lines=1"

# --- (e) an open run ----------------------------------------------------------
case="e: open run"
new_project e operative
mkdir -p "$P/.dream-team-tracking"; printf 'context_id=bugfix_x_2026-10-01\nstate=open\n' > "$P/.dream-team-tracking/.team-mode"
before="$(snap "$P")"; run
expect_rc 1
has "$tmp/err" "bugfix_x_2026-10-01"
[ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"

case="e: closed run is not refused"
new_project e2 operative
mkdir -p "$P/.dream-team-tracking"; printf 'context_id=bugfix_x_2026-10-01\nstate=closed\n' > "$P/.dream-team-tracking/.team-mode"
run
expect_rc 0

case="e: legacy run state"
new_project e3 operative
mkdir -p "$P/.claude-tracking/x"   # the legacy tracking directory
before="$(snap "$P")"; run
expect_rc 1
has "$tmp/err" "run state is still in the legacy directory"
[ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"

# --- (f) a symbolic link ---------------------------------------------------------
case="f: symbolic link"
new_project f
mkdir -p "$tmp/outside"; printf '# Outside\n' > "$tmp/outside/PROJECT-OVERVIEW.md"
rm -rf "$P/$OLD"
if MSYS=winsymlinks:nativestrict ln -s "$tmp/outside" "$P/$OLD" 2>/dev/null && [ -L "$P/$OLD" ]; then
  obefore="$(snap "$tmp/outside")"; before="$(snap "$P")"; run --first-commit
  expect_rc 2
  has "$tmp/err" "symbolic link"
  [ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"
  [ "$obefore" = "$(snap "$tmp/outside")" ] || fail "a file outside the project changed"
else
  echo "skip [f: symbolic link] ln -s cannot make a link here"
fi

# --- (g) a name on both sides --------------------------------------------------
case="g: conflict"
new_project g operative
mkdir -p "$P/$OPS/learnings"; printf 'other a\n' > "$P/$OPS/learnings/a.md"
before="$(snap "$P")"; run
expect_rc 1
has "$tmp/err" "learnings/a.md"
[ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"

# --- (h) two candidates for the first commit ------------------------------------
case="h: two candidates"
new_project h
mkdir -p "$P/$OTHER"
printf '# Overview\n\nThe other edition.\n' > "$P/$OTHER/PROJECT-OVERVIEW.md"
printf '# Other topics\n' > "$P/$OTHER/TOOLCHAIN.md"
old_index "$P/$OTHER/LEARNINGS.md"
before="$(snap "$P")"; run --first-commit
expect_rc 1
has "$tmp/err" "$OLD"
has "$tmp/err" "$OTHER"
[ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"
kbefore="$(snap "$P/$OLD")"
NOTE="note: $OTHER/ keeps its operative files for that edition's own migration"
run --first-commit --from "$OTHER" --dry-run
expect_rc 0
has "$tmp/out" "would: $NOTE"
[ "$before" = "$(snap "$P")" ] || fail "a dry run changed files"
run --first-commit --from "$OTHER"
expect_rc 0
has "$tmp/out" "project: moved to $NEW"
has "$tmp/out" "$NOTE"
[ ! -e "$P/$NEW.migrating" ] || fail "the staging directory is left"
[ ! -e "$P/$NEW/.migrate-source" ] || fail "the source record moved into the committed directory"
[ "$(cat "$P/$NEW/PROJECT-OVERVIEW.md")" = "$(printf '# Overview\n\nThe other edition.')" ] || fail "not moved from $OTHER"
[ -f "$P/$NEW/TOOLCHAIN.md" ] || fail "TOOLCHAIN.md not moved"
[ ! -e "$P/$NEW/LEARNINGS.md" ] || fail "the other edition's LEARNINGS.md moved into the committed directory"
[ -f "$P/$OTHER/LEARNINGS.md" ] || fail "the other edition's LEARNINGS.md was not left for its own migration"
[ "$kbefore" = "$(snap "$P/$OLD")" ] || fail "$OLD changed"

case="h: --from not a candidate"
new_project h2
before="$(snap "$P")"; run --first-commit --from "$OTHER"
expect_rc 1
[ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"

# --- (l) the resolver after (c) --------------------------------------------------
case="l: resolver"
new_project l
mkdir -p "$P/$NEW"
printf '# Project Rules\n\n- Keep the build green.\n' > "$P/$NEW/PROJECT-RULES.md"
commit_knowledge
printf -- '- Always X %s source: user\n' "$EM" >> "$P/$OLD/PROJECT-RULES.md"
run
expect_rc 0
out="$(cd "$P" && bash .claude/tools/knowledge-dir.sh project)"
[ "$out" = "$NEW" ] || fail "resolver printed '$out' with the committed copy, expected $NEW"
(cd "$P" && git rm -r -q --cached -- "$NEW" && rm -rf "$NEW")
out="$(cd "$P" && bash .claude/tools/knowledge-dir.sh project)"
[ "$out" = "$OLD" ] || fail "resolver printed '$out' on a branch without knowledge, expected $OLD"
run
expect_rc 0
has "$tmp/out" "project: waiting for $NEW"

# --- (m) an interrupted import: the entry files without the stamp ---------------
case="m: interrupted import"
new_project m
mkdir -p "$P/$NEW"
printf '# Project Rules\n\n- Keep the build green.\n' > "$P/$NEW/PROJECT-RULES.md"
commit_knowledge
{ printf -- '- Always X %s source: user\n' "$EM"; printf -- '- Never Y %s source: user\n' "$EM"; } >> "$P/$OLD/PROJECT-RULES.md"
run
expect_rc 0
has "$tmp/out" "(2 authored lines kept as inbox entries)"
# What an interrupt after the entry files and before the stamp leaves.
rm -f "$P/$CAPS/.legacy-rules-imported"
run
expect_rc 0
has "$tmp/out" "(0 authored lines kept as inbox entries)"
[ "$(ls "$P/$OPS/learnings" | grep -c -e '-migrated-rule-')" = 2 ] || fail "an entry was written twice: $(ls "$P/$OPS/learnings")"
[ ! -e "$P/$OPS/LEARNINGS.md" ] || fail "an index file was written"
has "$P/$CAPS/.legacy-rules-imported" "lines=0"

# --- (rx) the first commit moves authored lines into rule files ----------------------
case="rx: first commit extracts rules"
new_project rx
printf -- '- Never Y %s source: learnings 2026-10-01 Foo\n' "$EM" >> "$P/$OLD/PROJECT-RULES.md"
before="$(snap "$P")"; run --first-commit --dry-run
expect_rc 0
has "$tmp/out" "would: rules: extracted 1 (1 rules, 0 critical zones, 0 exceptions) into $NEW/rules"
[ "$before" = "$(snap "$P")" ] || fail "a first-commit dry run changed files"
run --first-commit
expect_rc 0
has "$tmp/out" "project: moved to $NEW"
has "$tmp/out" "rules: extracted 1 (1 rules, 0 critical zones, 0 exceptions) into $NEW/rules"
same "$tmp/rx.orig/PROJECT-OVERVIEW.md" "$P/$NEW/PROJECT-OVERVIEW.md"
[ "$(cat "$P/$NEW/PROJECT-RULES.md")" = "$(printf '# Project Rules\n\n- Keep the build green.')" ] \
  || fail "the line is still in the moved file: $(cat "$P/$NEW/PROJECT-RULES.md")"
[ -f "$P/$NEW/rules/foo.md" ] && grep -qxF -- "- Rule: Never Y" "$P/$NEW/rules/foo.md" \
  || fail "the line is not in $NEW/rules/: $(ls "$P/$NEW/rules" 2>&1)"
(cd "$P" && bash .claude/checks/verify-knowledge-shape.sh "$NEW") > "$tmp/shape" 2>&1 || fail "shape check: $(cat "$tmp/shape")"

# --- (ry) the committed rules/ holds the private copy's rule text ------------------
case="ry: rule text held in rules/"
new_project ry
mkdir -p "$P/$NEW/rules"
printf '# Project Rules\n\n- Keep the build green.\n' > "$P/$NEW/PROJECT-RULES.md"
printf '# Foo\n- Kind: rule\n- Rule: Never Y\n- Belongs with: PROJECT-RULES.md\n- Source: learnings 2026-10-01 Foo\n- Added: 2026-10-02\n' > "$P/$NEW/rules/foo.md"
printf '# src/pay/**\n- Kind: critical-zone\n- Zone: src/pay/** %s money\n- Source: user\n- Added: 2026-10-02\n' "$EM" > "$P/$NEW/rules/src-pay.md"
commit_knowledge
{ printf -- '- Never Y %s source: learnings 2026-10-01 Foo\r\n' "$EM"
  printf '\r\n## Critical zones\r\n\r\n- src/pay/** %s money %s source: user\r\n' "$EM" "$EM"; } >> "$P/$OLD/PROJECT-RULES.md"
run
expect_rc 0
has "$tmp/out" "(0 authored lines kept as inbox entries)"
[ -z "$(ls "$P/$OPS/learnings" 2>/dev/null | grep -e '-migrated-rule-')" ] || fail "an entry was written: $(ls "$P/$OPS/learnings")"
printf -- '- Other W %s source: user\n' "$EM" >> "$P/$OLD/PROJECT-RULES.md"
run --drop-legacy
expect_rc 0
has "$tmp/out" "; 1 authored lines kept as inbox entries)"

# --- (n) an interrupted first commit ------------------------------------------------
# A stub mv that fails for one path, the way a file held open fails on Windows.
mkdir -p "$tmp/stub"
cat > "$tmp/stub/mv" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in *"$FAIL_ON") exit 1 ;; esac; done
exec /usr/bin/env -i PATH="$REAL_PATH" mv "$@"
STUB
chmod +x "$tmp/stub/mv"
run_failing() { # <suffix> [args]
  local f="$1"; shift
  (cd "$P" && REAL_PATH="$PATH" FAIL_ON="$f" PATH="$tmp/stub:$PATH" bash .claude/tools/migrate-knowledge.sh "$@") > "$tmp/out" 2> "$tmp/err"; rc=$?
}

case="n: interrupted rename of this edition's directory"
new_project n1 operative
run_failing "/knowledge" --first-commit
expect_rc 2
[ ! -e "$P/$NEW" ] && [ ! -e "$P/$NEW.migrating" ] || fail "a partial committed directory was left"
for f in PROJECT-OVERVIEW.md PROJECT-RULES.md REVIEW-CHECKLIST.md REVIEW-CHECKLIST/security.md; do
  same "$tmp/n1.orig/$f" "$P/$OLD/$f"
done
same "$tmp/n1.orig/LEARNINGS.md" "$P/$OPS/LEARNINGS.md"
run
expect_rc 0
has "$tmp/out" "project: waiting for $NEW in the repository; the first knowledge commit is made with --first-commit"
run --first-commit
expect_rc 0
has "$tmp/out" "project: moved to $NEW"
for f in PROJECT-OVERVIEW.md PROJECT-RULES.md REVIEW-CHECKLIST.md REVIEW-CHECKLIST/security.md; do
  same "$tmp/n1.orig/$f" "$P/$NEW/$f"
done
[ ! -e "$P/$OLD" ] || fail "$OLD still there"

case="n: interrupted move from another edition, a topic directory left"
new_project n2
mkdir -p "$P/$OTHER/TOPIC"
printf '# Overview\n\nThe other edition.\n' > "$P/$OTHER/PROJECT-OVERVIEW.md"
printf '# Topic\n' > "$P/$OTHER/TOPIC/x.md"
old_index "$P/$OTHER/LEARNINGS.md"
kbefore="$(snap "$P/$OLD")"
run_failing "/TOPIC" --first-commit --from "$OTHER"
expect_rc 2
[ ! -e "$P/$NEW" ] || fail "$NEW appeared before the move was complete"
[ -f "$P/$NEW.migrating/PROJECT-OVERVIEW.md" ] || fail "the staged entry is missing"
[ -d "$P/$OTHER/TOPIC" ] || fail "the stub did not stop the move"
run
expect_rc 0
has "$tmp/out" "an interrupted --first-commit left $NEW.migrating/: run --first-commit again to finish the move"
lacks "$tmp/out" "nothing to move ("
before="$(snap "$P")"
run --first-commit --dry-run
expect_rc 0
has "$tmp/out" "would: project: moved to $NEW"
has "$tmp/out" "would: note: $OTHER/ keeps its operative files"
[ "$before" = "$(snap "$P")" ] || fail "a dry run changed files"
# No --from: the interrupted run recorded its source, though both directories
# hold project files now.
run --first-commit
expect_rc 0
has "$tmp/out" "project: moved to $NEW"
has "$tmp/out" "note: $OTHER/ keeps its operative files"
[ -f "$P/$NEW/PROJECT-OVERVIEW.md" ] && [ -f "$P/$NEW/TOPIC/x.md" ] || fail "the resumed move is incomplete: $(cd "$P" && find "$NEW" 2>&1)"
[ ! -e "$P/$NEW.migrating" ] && [ ! -e "$P/$NEW/.migrate-source" ] || fail "staging left behind"
[ ! -e "$P/$OTHER/TOPIC" ] && [ -f "$P/$OTHER/LEARNINGS.md" ] || fail "the other edition's directory is not as expected"
[ "$kbefore" = "$(snap "$P/$OLD")" ] || fail "$OLD changed"
run
expect_rc 0
has "$tmp/out" "project: moved to $NEW: run /generate-knowledge, then commit it alone"

case="n: the final rename fails"
new_project n4
mkdir -p "$P/$OTHER"
printf '# Overview\n\nThe other edition.\n' > "$P/$OTHER/PROJECT-OVERVIEW.md"
printf '# Toolchain\n' > "$P/$OTHER/TOOLCHAIN.md"
old_index "$P/$OTHER/LEARNINGS.md"
kbefore="$(snap "$P/$OLD")"
# Only the rename of the staging directory ends in ".migrating".
run_failing ".migrating" --first-commit --from "$OTHER"
expect_rc 2
[ ! -e "$P/$NEW" ] || fail "$NEW appeared though the rename failed"
[ -f "$P/$NEW.migrating/PROJECT-OVERVIEW.md" ] && [ -f "$P/$NEW.migrating/TOOLCHAIN.md" ] || fail "the staged entries are missing"
[ "$(cat "$P/$NEW.migrating/.migrate-source" 2>/dev/null)" = "$OTHER" ] || fail "the source record did not survive the failed rename"
[ "$kbefore" = "$(snap "$P/$OLD")" ] || fail "$OLD changed"
run
expect_rc 0
has "$tmp/out" "an interrupted --first-commit left $NEW.migrating/: run --first-commit again to finish the move"
[ "$kbefore" = "$(snap "$P/$OLD")" ] || fail "$OLD changed"
# No --from: legacyDir is now the only directory with project files, and must
# still not be taken for the source.
run --first-commit
expect_rc 0
has "$tmp/out" "project: moved to $NEW"
[ "$(cat "$P/$NEW/PROJECT-OVERVIEW.md")" = "$(printf '# Overview\n\nThe other edition.')" ] && [ -f "$P/$NEW/TOOLCHAIN.md" ] \
  || fail "not resumed from the recorded source: $(cd "$P" && find "$NEW" 2>&1)"
[ ! -e "$P/$NEW/PROJECT-RULES.md" ] || fail "this edition's private copy was merged into the committed directory"
[ ! -e "$P/$NEW/.migrate-source" ] && [ ! -e "$P/$NEW.migrating" ] || fail "staging or its record left behind"
[ "$kbefore" = "$(snap "$P/$OLD")" ] || fail "$OLD changed"

case="n: staging without a record"
new_project n5
# Every project file of the other edition is staged and the record is gone:
# legacyDir is the only directory with project files, and no name overlaps,
# so a guess would merge it in silently.
mkdir -p "$P/$OTHER" "$P/$NEW.migrating"
printf '# Toolchain\n' > "$P/$NEW.migrating/TOOLCHAIN.md"
old_index "$P/$OTHER/LEARNINGS.md"
kbefore="$(snap "$P/$OLD")"
before="$(snap "$P")"; run --first-commit
expect_rc 1
has "$tmp/err" "--from"
has "$tmp/err" "without a record"
[ "$before" = "$(snap "$P")" ] || fail "a refused resume changed files"
run --first-commit --from "$OTHER"
expect_rc 0
[ -f "$P/$NEW/TOOLCHAIN.md" ] || fail "the resume with --from is incomplete"
[ ! -e "$P/$NEW/PROJECT-RULES.md" ] || fail "this edition's private copy was merged in"
has "$tmp/out" "note: $OTHER/ keeps its operative files"
[ "$kbefore" = "$(snap "$P/$OLD")" ] || fail "$OLD changed"

case="n: staging beside a committed copy"
new_project n6
mkdir -p "$P/$NEW" "$P/$NEW.migrating"
printf '# Project Rules\n\n- Keep the build green.\n' > "$P/$NEW/PROJECT-RULES.md"
commit_knowledge
printf '# Overview\n' > "$P/$NEW.migrating/PROJECT-OVERVIEW.md"
run
expect_rc 0
has "$tmp/out" "project: in place ($NEW)"
has "$tmp/out" "an interrupted move left $NEW.migrating/"

case="n: resume refuses a name on both sides"
new_project n3
mkdir -p "$P/$OTHER" "$P/$NEW.migrating"
printf '# A\n' > "$P/$OTHER/PROJECT-OVERVIEW.md"; printf '# B\n' > "$P/$NEW.migrating/PROJECT-OVERVIEW.md"
printf '%s\n' "$OTHER" > "$P/$NEW.migrating/.migrate-source"
before="$(snap "$P")"; run --first-commit
expect_rc 1
has "$tmp/err" "PROJECT-OVERVIEW.md"
[ "$before" = "$(snap "$P")" ] || fail "a refused resume changed files"

# --- the profile: the inbox moves to <profile root>/<key>/ -------------------------
# The fixtures above have no remote, so their inbox stays per copy; these set one.
PROOT="$DREAM_TEAM_PROFILE"
with_remote() { (cd "$P" && git remote add origin "$1"); }
key_of() { (cd "$P" && bash .claude/tools/knowledge-dir.sh key); }
# ops_inbox <name>: a per-copy operative dir as phase 1 left it: an old index
# of two rows, two entry files, the capabilities file; a copy in $tmp/<name>.ops.
ops_inbox() {
  mkdir -p "$P/$OPS/learnings" "$P/$CAPS"
  printf '# Dream Team Learnings Inbox\n\n## Index\n\n| Date | Title | Tags |\n|------|-------|------|\n| 2026-10-01 | A | a |\n| 2026-10-02 | B | b |\n' > "$P/$OPS/LEARNINGS.md"
  printf '## [2026-10-01] A\n- **Tags:** a\n' > "$P/$OPS/learnings/a.md"
  printf '## [2026-10-02] B\n- **Tags:** b\n' > "$P/$OPS/learnings/b.md"
  printf '# Capabilities\n\n- shell: bash\n' > "$P/$CAPS/CAPABILITIES.md"
  rm -rf "$tmp/$1.ops"; cp -R "$P/$OPS" "$tmp/$1.ops"
}
inbox_backup() { ls -d "$P/$OPS"/inbox-backup-* 2>/dev/null | head -1; }

case="pm: the inbox moves to the profile"
new_project pm
with_remote "https://example.invalid/team/shared.git"
ops_inbox pm
K="$(key_of)"; PD="$PROOT/$K"
[ -n "$K" ] || fail "no key"
run
expect_rc 0
same "$tmp/pm.ops/learnings/a.md" "$PD/learnings/a.md"
same "$tmp/pm.ops/learnings/b.md" "$PD/learnings/b.md"
[ ! -e "$P/$OPS/LEARNINGS.md" ] || fail "LEARNINGS.md is still per copy"
di="$(ls "$P/$OPS"/dropped-index-*.md 2>/dev/null | head -1)"
if [ -n "$di" ]; then same "$tmp/pm.ops/LEARNINGS.md" "$di"; else fail "no dropped-index file: $(ls "$P/$OPS")"; fi
same "$tmp/pm.ops/claude/CAPABILITIES.md" "$P/$CAPS/CAPABILITIES.md"
[ -z "$(ls -A "$P/$OPS/learnings" 2>/dev/null)" ] || fail "entries left per copy: $(ls "$P/$OPS/learnings")"
[ ! -e "$PD/LEARNINGS.md" ] || fail "an index file in the profile"
has "$tmp/out" "(key $K): moved 2 entries, 0 already there, 0 renamed, 0 lifted from LEARNINGS.md"
bk="$(inbox_backup)"
[ -n "$bk" ] && [ -f "$bk/learnings/a.md" ] && [ -f "$bk/LEARNINGS.md" ] || fail "no inbox backup: $(ls "$P/$OPS")"
out="$(cd "$P" && bash .claude/tools/knowledge-dir.sh operative)"
case "$out" in *"/$K") ;; *) fail "resolver printed '$out', expected the profile directory" ;; esac

case="pn: a second copy of the same repository"
new_project pn
with_remote "https://example.invalid/team/shared.git"
mkdir -p "$P/$OPS/learnings"
printf '## [2026-10-01] A\n- **Tags:** other\n' > "$P/$OPS/learnings/a.md"
printf '## [2026-10-02] B\n- **Tags:** b\n' > "$P/$OPS/learnings/b.md"
cp "$P/$OPS/learnings/a.md" "$tmp/pn.a"
[ "$(key_of)" = "$K" ] || fail "the second copy has another key"
run
expect_rc 0
same "$tmp/pm.ops/learnings/a.md" "$PD/learnings/a.md"
same "$tmp/pn.a" "$PD/learnings/a-2.md"
[ "$(ls "$PD/learnings" | LC_ALL=C sort | tr '\n' ' ')" = "a-2.md a.md b.md " ] || fail "the profile holds: $(ls "$PD/learnings")"
has "$tmp/out" "(key $K): moved 0 entries, 1 already there, 1 renamed, 0 lifted from LEARNINGS.md"
case="pn: second run"
before="$(snap "$P")$(snap "$PD")"; run
expect_rc 0
has "$tmp/out" "(key $K): in place"
[ "$before" = "$(snap "$P")$(snap "$PD")" ] || fail "a second run changed files"

case="po: no remote"
new_project po
ops_inbox po
before="$(snap "$P/$OPS")"; pbefore="$(ls -A "$PROOT" 2>/dev/null)"
run
expect_rc 0
has "$tmp/out" "operative: per-copy $OPS (no remote)"
[ "$before" = "$(snap "$P/$OPS")" ] || fail "per-copy files changed"
[ "$pbefore" = "$(ls -A "$PROOT" 2>/dev/null)" ] || fail "the profile root changed"

case="pp: the profile cannot be created"
new_project pp
with_remote "https://example.invalid/team/pp.git"
ops_inbox pp
printf 'a file\n' > "$tmp/pfile"
before="$(snap "$P/$OPS")"
(cd "$P" && DREAM_TEAM_PROFILE="$tmp/pfile/profile" bash .claude/tools/migrate-knowledge.sh) > "$tmp/out" 2> "$tmp/err"; rc=$?
expect_rc 0
has "$tmp/out" "operative: per-copy $OPS (profile not writable)"
[ "$before" = "$(snap "$P/$OPS")" ] || fail "per-copy files changed"

case="pp: the directories are made, then the step fails"
# A stub mkdir that makes the directories and then reports failure: the step
# removes what it created, and only that.
mkdir -p "$tmp/stub2" "$tmp/proot2"
cat > "$tmp/stub2/mkdir" <<'STUB'
#!/usr/bin/env bash
/usr/bin/env -i PATH="$REAL_PATH" mkdir "$@" || exit $?
for a in "$@"; do case "$a" in *"$FAIL_ON") exit 1 ;; esac; done
exit 0
STUB
chmod +x "$tmp/stub2/mkdir"
(cd "$P" && DREAM_TEAM_PROFILE="$tmp/proot2/deep" REAL_PATH="$PATH" FAIL_ON="/learnings" PATH="$tmp/stub2:$PATH" \
  bash .claude/tools/migrate-knowledge.sh) > "$tmp/out" 2> "$tmp/err"; rc=$?
expect_rc 0
has "$tmp/out" "operative: per-copy $OPS (profile not writable)"
[ -d "$tmp/proot2" ] || fail "a directory the step did not create was removed"
[ ! -e "$tmp/proot2/deep" ] || fail "the step left what it created: $(find "$tmp/proot2" 2>&1)"
[ "$before" = "$(snap "$P/$OPS")" ] || fail "per-copy files changed"

case="pq: inline entries are lifted"
new_project pq
with_remote "https://example.invalid/team/pq.git"
mkdir -p "$P/$OPS"
{ printf '# Dream Team Learnings Inbox\n\n## Index\n\n| Date | Title | Tags |\n|------|-------|------|\n| 2026-10-02 | Lifted One | x |\n| 2026-10-03 | Lifted: Two! | y |\n\n'
  printf '## [2026-10-02] Lifted One\n- **Tags:** x\n\n'
  printf '## [2026-10-03] Lifted: Two!\r\n- **Tags:** y\r\n\r\n'
  printf '## [2026-10-02] Lifted One\n- **Tags:** z\n\n'
  printf '## [2026-10-04] \320\237\321\200\320\270\n- **Tags:** w\n'; } > "$P/$OPS/LEARNINGS.md"
cp "$P/$OPS/LEARNINGS.md" "$tmp/pq.index"
K="$(key_of)"; PD="$PROOT/$K"
run
expect_rc 0
has "$tmp/out" "(key $K): moved 4 entries, 0 already there, 0 renamed, 4 lifted from LEARNINGS.md"
printf '## [2026-10-02] Lifted One\n- **Tags:** x\n\n' > "$tmp/pq.1"
printf '## [2026-10-03] Lifted: Two!\r\n- **Tags:** y\r\n\r\n' > "$tmp/pq.2"
printf '## [2026-10-02] Lifted One\n- **Tags:** z\n\n' > "$tmp/pq.3"
# A title with no ASCII letter or digit has an empty slug: the name says "entry".
printf '## [2026-10-04] \320\237\321\200\320\270\n- **Tags:** w\n' > "$tmp/pq.4"
same "$tmp/pq.1" "$PD/learnings/2026-10-02-lifted-one.md"
same "$tmp/pq.2" "$PD/learnings/2026-10-03-lifted-two.md"
same "$tmp/pq.3" "$PD/learnings/2026-10-02-lifted-one-2.md"
same "$tmp/pq.4" "$PD/learnings/2026-10-04-entry.md"
di="$(ls "$P/$OPS"/dropped-index-*.md 2>/dev/null | head -1)"
if [ -n "$di" ]; then same "$tmp/pq.index" "$di"; else fail "no dropped-index file: $(ls "$P/$OPS")"; fi
bk="$(inbox_backup)"
if [ -n "$bk" ]; then
  (cd "$P" && bash .claude/checks/verify-knowledge-integrity.sh "$bk" "$PD" inbox) > "$tmp/integ" 2>&1 \
    || fail "integrity check: $(head -c 600 "$tmp/integ")"
else
  fail "no inbox backup: $(ls "$P/$OPS")"
fi

case="pr: review exceptions on both sides"
new_project pr
with_remote "https://example.invalid/team/pr.git"
K="$(key_of)"; PD="$PROOT/$K"
mkdir -p "$P/$OPS" "$PD"
printf -- '- only in the profile\n- in both\n' > "$PD/review-exceptions.md"
printf -- '- in both\r\n- only per copy\r\n' > "$P/$OPS/review-exceptions.md"
run
expect_rc 0
[ ! -e "$P/$OPS/review-exceptions.md" ] || fail "the per-copy file is still there"
tr -d '\r' < "$PD/review-exceptions.md" | LC_ALL=C sort > "$tmp/exc"
printf -- '- in both\n- only in the profile\n- only per copy\n' > "$tmp/exc.want"
same "$tmp/exc.want" "$tmp/exc"

case="ps: dry run on (pm)"
new_project ps
with_remote "https://example.invalid/team/ps.git"
ops_inbox ps
K="$(key_of)"; PD="$PROOT/$K"
before="$(snap "$P")"; run --dry-run
expect_rc 0
has "$tmp/out" "would: operative: "
has "$tmp/out" "(key $K): moved 2 entries, 0 already there, 0 renamed, 0 lifted from LEARNINGS.md"
[ ! -e "$PD" ] || fail "a dry run created the profile directory"
[ "$before" = "$(snap "$P")" ] || fail "a dry run changed files"

case="ps: dry run with the legacy operative files still to move"
new_project ps2 operative
with_remote "https://example.invalid/team/ps2.git"
K="$(key_of)"; PD="$PROOT/$K"
run --dry-run
expect_rc 0
grep '^would: operative: .*(key ' "$tmp/out" | sed 's/^would: //' > "$tmp/ps2.dry"
[ ! -e "$PD" ] || fail "a dry run created the profile directory"
run
expect_rc 0
grep '^operative: .*(key ' "$tmp/out" > "$tmp/ps2.real"
same "$tmp/ps2.dry" "$tmp/ps2.real"
has "$tmp/ps2.real" "(key $K): moved 1 entries, 0 already there, 0 renamed, 0 lifted from LEARNINGS.md"
same "$tmp/ps2.orig/learnings/a.md" "$PD/learnings/a.md"

case="pt: authored lines land in the profile"
new_project pt
with_remote "https://example.invalid/team/pt.git"
mkdir -p "$P/$NEW"
printf '# Project Rules\n\n- Keep the build green.\n' > "$P/$NEW/PROJECT-RULES.md"
commit_knowledge
{ printf '# Project Rules\n\n- Keep the build green.\n'
  printf -- '- Always X %s source: user\n' "$EM"
  printf -- '- Never Y %s source: learnings 2026-10-01 Foo\n' "$EM"; } > "$P/$OLD/PROJECT-RULES.md"
K="$(key_of)"; PD="$PROOT/$K"
run
expect_rc 0
has "$tmp/out" "(2 authored lines kept as inbox entries)"
[ -f "$PD/learnings/$TODAY-migrated-rule-1.md" ] && [ -f "$PD/learnings/$TODAY-migrated-rule-2.md" ] \
  || fail "entries not in the profile: $(ls "$PD/learnings" 2>&1)"
[ -z "$(ls -A "$P/$OPS/learnings" 2>/dev/null)" ] || fail "entries left per copy: $(ls "$P/$OPS/learnings")"
[ -z "$(find "$P/$OPS" "$P/$OLD" "$P/$NEW" "$PD" -name LEARNINGS.md 2>/dev/null)" ] || fail "a LEARNINGS.md was created"
case="pt: drop legacy, the marks are in the profile"
printf -- '- Third Z %s source: user\n' "$EM" >> "$P/$OLD/PROJECT-RULES.md"
run --drop-legacy
expect_rc 0
has "$tmp/out" "; 1 authored lines kept as inbox entries)"
[ "$(ls "$PD/learnings" | grep -c -e '-migrated-rule-')" = 3 ] || fail "expected exactly 3 entries: $(ls "$PD/learnings")"
[ -f "$PD/learnings/$TODAY-migrated-rule-3.md" ] || fail "the third entry is not numbered 3: $(ls "$PD/learnings")"

case="pu: an open run"
new_project pu
with_remote "https://example.invalid/team/pu.git"
ops_inbox pu
K="$(key_of)"; PD="$PROOT/$K"
mkdir -p "$P/.dream-team-tracking"; printf 'context_id=bugfix_x_2026-10-01\nstate=open\n' > "$P/.dream-team-tracking/.team-mode"
before="$(snap "$P")"; run
expect_rc 1
[ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"
[ ! -e "$PD" ] || fail "a refused run created the profile directory"

case="pv: profile disabled"
new_project pv
with_remote "https://example.invalid/team/pv.git"
ops_inbox pv
sed -i 's|"profileDir": "~/.dream-team"|"profileDir": ""|' "$P/.claude/team-manifest.json"
grep -qF '"profileDir": ""' "$P/.claude/team-manifest.json" || fail "the fixture did not empty profileDir"
before="$(snap "$P/$OPS")"; run
expect_rc 0
has "$tmp/out" "operative: per-copy $OPS (profile disabled)"
[ "$before" = "$(snap "$P/$OPS")" ] || fail "per-copy files changed"

# --- arguments, outside git, source guards -----------------------------------------
case="usage"
new_project u
before="$(snap "$P")"
for a in "--bogus" "--from $OTHER" "--first-commit --drop-legacy" "--first-commit --from"; do
  # shellcheck disable=SC2086
  run $a
  expect_rc 2
done
[ "$before" = "$(snap "$P")" ] || fail "a usage error changed files"

case="outside a git work tree"
new_project n operative
rm -rf "$P/.git"
run
expect_rc 0
has "$tmp/out" "project: waiting for $NEW"
run --drop-legacy
expect_rc 1

case="source"
if [ -f "$SCRIPT" ]; then
  ! grep -nE '\.claude/|\.claude-tracking|Claude Code' "$SCRIPT" || fail "a literal team path, legacy name or edition name in the script"
  if grep -nE '\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^)|declare -A|mapfile|readarray' "$SCRIPT"; then fail "bash-4-only construct"; fi
  [ "$(tr -cd '\r' < "$SCRIPT" | wc -c | tr -d ' ')" = 0 ] || fail "the script has CR line endings"
fi
grep -qxF 'tools/migrate-knowledge.sh text eol=lf' "$ROOT/.gitattributes" || fail ".gitattributes lacks the LF pin"
tr -d '\r' < "$ROOT/team-manifest.json" | grep -qF '"migration": "tools/migrate-knowledge.sh"' || fail "manifest lacks knowledge.migration"
tr -d '\r' < "$ROOT/team-manifest.json" | grep -qF '"migrateKnowledge": "bash checks/verify-migrate-knowledge.sh",' || fail "manifest lacks checks.migrateKnowledge"

[ "$status" = 0 ] && echo "verify-migrate-knowledge: all cases passed"
exit "$status"
