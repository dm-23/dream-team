#!/usr/bin/env bash
# Tests tools/migrate-knowledge.sh against throwaway projects, each a fresh git
# repository with the real team tree copied to .claude/: the operative files
# moving out, the project files waiting or moving to the committed directory,
# authored lines of a private copy kept as remarks, the refusals and that a
# refusal changes nothing, dry run, reruns, dropping the private copy, what
# the resolver prints afterwards, and the old inbox moving into the remarks
# dir: per-copy entries, entries lifted out of an old LEARNINGS.md, the lines
# of review-exceptions.md, a second run, the copy from the private copy's
# remarks dir into the committed one (first sight, --first-commit,
# --drop-legacy).
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
status=0
case=""
fail() { echo "FAIL [$case]: $*" >&2; status=1; }

OLD=".claude/knowledge"
NEW=".dream-team/knowledge"
OPS=".dream-team-tracking/operative"
CAPS=".dream-team-tracking/operative/claude"
OTHER=".github/dream-team/knowledge"
RL="$OPS/proposals"     # the remarks dir while the knowledge is the private copy
RC="$NEW/proposals"     # the remarks dir of the committed directory
TODAY="$(date +%Y-%m-%d)"
EM="$(printf '\342\200\224')"   # the em dash, as bytes
MD="$(printf '\302\267')"       # the middle dot, as bytes

# The real team tree, copied once; every fixture copies it to .claude/.
TEAM="$tmp/team"
mkdir -p "$TEAM"
for d in agents skills templates tools checks hooks team-manifest.json; do
  [ -e "$ROOT/$d" ] && cp -R "$ROOT/$d" "$TEAM/"
done

# old_index <file>: a LEARNINGS.md as deployments before the derived index
# kept it; the migration moves it aside, byte for byte, and never writes it.
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
# committed_copy: a tracked committed copy holding one file.
committed_copy() {
  mkdir -p "$P/$NEW"
  printf '# Project Rules\n\n- Keep the build green.\n' > "$P/$NEW/PROJECT-RULES.md"
  commit_knowledge
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
# rname <content file> <stem>: the name tools/remarks.sh gives that content
rname() { printf '%s-%s.md' "$2" "$(git hash-object --no-filters -- "$1" | tr -d '\r' | cut -c1-6)"; }
# nfiles <dir>: the number of *.md directly inside
nfiles() { ls "$1" 2>/dev/null | grep -c '\.md$'; }
# one_of <dir> <stem>: the one file <stem>-<hash6>.md in <dir>, or nothing
one_of() { ls "$1" 2>/dev/null | grep -E -- "^$2-[0-9a-f]{6}\.md$" | head -1 | sed "s|^|$1/|"; }
inbox_backup() { ls -d "$P/$OPS"/inbox-backup-* 2>/dev/null | head -1; }
dropped_index() { ls "$P/$OPS"/dropped-index-*.md 2>/dev/null | head -1; }
# untracked <dir>: every file under <dir> git reports, one "XY path" per line
untracked() { (cd "$P" && git status --porcelain -uall -- "$1"); }
UNOTE="new files under $RC are untracked: commit them with your next change, or delete them"

[ -f "$SCRIPT" ] || fail "tools/migrate-knowledge.sh is missing"

# --- (a) default mode, nothing tracked: the inbox goes to the legacy remarks dir --
case="a: default, nothing tracked"
new_project a operative
run
expect_rc 0
same "$tmp/a.orig/CAPABILITIES.md" "$P/$CAPS/CAPABILITIES.md"
for f in LEARNINGS.md learnings CAPABILITIES.md; do [ ! -e "$P/$OLD/$f" ] || fail "$f still in $OLD"; done
for f in PROJECT-OVERVIEW.md PROJECT-RULES.md REVIEW-CHECKLIST.md REVIEW-CHECKLIST/security.md; do
  same "$tmp/a.orig/$f" "$P/$OLD/$f"
done
[ ! -e "$P/$NEW" ] || fail "$NEW was created"
same "$tmp/a.orig/learnings/a.md" "$P/$RL/$(rname "$tmp/a.orig/learnings/a.md" a)"
[ "$(nfiles "$P/$RL")" = 1 ] || fail "the remarks dir holds: $(ls "$P/$RL" 2>&1)"
[ ! -e "$P/$OPS/learnings" ] || fail "the per-copy inbox is still there: $(ls "$P/$OPS/learnings")"
[ ! -e "$P/$OPS/LEARNINGS.md" ] || fail "LEARNINGS.md is still in $OPS"
di="$(dropped_index)"
if [ -n "$di" ]; then same "$tmp/a.orig/LEARNINGS.md" "$di"; else fail "no dropped-index file: $(ls "$P/$OPS")"; fi
bk="$(inbox_backup)"
[ -n "$bk" ] && [ -f "$bk/learnings/a.md" ] && [ -f "$bk/LEARNINGS.md" ] || fail "no inbox backup: $(ls "$P/$OPS")"
has "$tmp/out" "operative: moved 3 entries to $OPS"
has "$tmp/out" "remarks: $RL: 1 moved, 0 already there"
has "$tmp/out" "project: waiting for $NEW in the repository; the first knowledge commit is made with --first-commit"
lacks "$tmp/out" "note:"
lacks "$tmp/out" "operative: per-copy"
[ ! -e "$P/$CAPS/.legacy-rules-imported" ] || fail "stamp written while nothing is tracked"
out="$(cd "$P" && bash .claude/tools/knowledge-dir.sh remarks)"
[ "$out" = "$RL" ] || fail "the resolver prints '$out' as the remarks dir, expected $RL"

case="a: second run"
before="$(snap "$P")"; run
expect_rc 0
has "$tmp/out" "remarks: $RL: nothing to move"
[ "$before" = "$(snap "$P")" ] || fail "a second run changed files"

# --- (i) dry run on (a) -----------------------------------------------------
case="i: dry run"
new_project i operative
before="$(snap "$P")"; run --dry-run
expect_rc 0
has "$tmp/out" "would: operative: moved 3 entries to $OPS"
has "$tmp/out" "would: remarks: $RL: 1 moved, 0 already there"
has "$tmp/out" "would: project: waiting for $NEW"
[ "$before" = "$(snap "$P")" ] || fail "a dry run changed files"
run --first-commit --dry-run
expect_rc 0
has "$tmp/out" "would: project: moved to $NEW: run /generate-knowledge"
has "$tmp/out" "would: remarks: $RC: 1 moved, 0 already there"
[ "$before" = "$(snap "$P")" ] || fail "a first-commit dry run changed files"

# --- (b) --first-commit: the inbox goes to the new committed directory's remarks dir --
case="b: first commit"
new_project b operative
run --first-commit
expect_rc 0
for f in PROJECT-OVERVIEW.md PROJECT-RULES.md REVIEW-CHECKLIST.md REVIEW-CHECKLIST/security.md; do
  same "$tmp/b.orig/$f" "$P/$NEW/$f"
done
[ ! -e "$P/$OLD" ] || fail "$OLD still there"
for f in LEARNINGS.md learnings CAPABILITIES.md; do [ ! -e "$P/$NEW/$f" ] || fail "$f moved into the committed directory"; done
di="$(dropped_index)"
if [ -n "$di" ]; then same "$tmp/b.orig/LEARNINGS.md" "$di"; else fail "no dropped-index file: $(ls "$P/$OPS")"; fi
same "$tmp/b.orig/CAPABILITIES.md" "$P/$CAPS/CAPABILITIES.md"
same "$tmp/b.orig/learnings/a.md" "$P/$RC/$(rname "$tmp/b.orig/learnings/a.md" a)"
[ ! -e "$P/$RL" ] || fail "the inbox went to $RL: $(ls "$P/$RL")"
has "$tmp/out" "operative: moved 3 entries to $OPS"
has "$tmp/out" "project: moved to $NEW: run /generate-knowledge, then commit it alone, one commit and one pull request, no other file"
has "$tmp/out" "remarks: $RC: 1 moved, 0 already there"
lacks "$tmp/out" "note:"

# --- (j) a second run right after (b) ----------------------------------------
case="j: rerun after first commit"
# The move is done and nothing is committed yet: the report says to commit
# the directory, never "nothing to move" or "made with --first-commit".
before="$(snap "$P")"; run
expect_rc 0
has "$tmp/out" "operative: nothing to move"
has "$tmp/out" "remarks: $RC: nothing to move"
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
lacks "$tmp/out" "note:"

# --- (c) a tracked committed copy, authored lines in the private copy -----------
case="c: authored lines"
new_project c
committed_copy
{ printf '# Project Rules\n\n- Keep the build green.\n'
  printf -- '- Always X %s source: user\n' "$EM"
  printf -- '- Never Y %s source: learnings 2026-10-01 Foo\n' "$EM"; } > "$P/$OLD/PROJECT-RULES.md"
rm -rf "$tmp/c.orig"; cp -R "$P/$OLD" "$tmp/c.orig"
kbefore="$(snap "$P/$OLD")"
run
expect_rc 0
has "$tmp/out" "operative: nothing to move"
has "$tmp/out" "remarks: $RC: nothing to move"
has "$tmp/out" "project: in place ($NEW); private copy kept for branches without knowledge (2 authored lines kept as remarks)"
has "$tmp/out" "note: 2 $UNOTE"
[ "$kbefore" = "$(snap "$P/$OLD")" ] || fail "$OLD changed"
E1="$(one_of "$P/$RC" "$TODAY-migrated-rule-1")"; E2="$(one_of "$P/$RC" "$TODAY-migrated-rule-2")"
[ -n "$E1" ] && [ -n "$E2" ] || fail "entries missing: $(ls "$P/$RC" 2>&1)"
[ -z "$(one_of "$P/$RC" "$TODAY-migrated-rule-3")" ] || fail "a third entry"
[ ! -e "$P/$OPS/learnings" ] || fail "an entry was left in $OPS/learnings: $(ls "$P/$OPS/learnings")"
if [ -n "$E1" ] && [ -n "$E2" ]; then
  head -1 "$E1" | tr -d '\r' | grep -qxF "## [$TODAY] Migrated rule 1" || fail "entry 1 heading: $(head -1 "$E1")"
  tr -d '\r' < "$E1" | grep -qxF "[PROMOTE] PROJECT-RULES.md $EM Always X" || fail "entry 1 mark: $(cat "$E1")"
  tr -d '\r' < "$E2" | grep -qxF "[PROMOTE] PROJECT-RULES.md $EM Never Y" || fail "entry 2 mark: $(cat "$E2")"
  has "$E1" "- Always X $EM source: user"
  has "$E2" "- Never Y $EM source: learnings 2026-10-01 Foo"
  has "$E1" "- **Tags:** migration"
  # A remark lands in committed knowledge: it names no team path, and the
  # rule's new home is a rule file.
  has "$E1" "the private copy's PROJECT-RULES.md holds an authored line"
  has "$E1" "a rule file in $NEW/rules/"
  lacks "$E1" "$OLD"
  mkdir -p "$tmp/c.neutral"; cp "$E1" "$E2" "$tmp/c.neutral/"
  bash "$ROOT/checks/verify-knowledge-neutral.sh" "$tmp/c.neutral" > "$tmp/c.neutral.out" 2>&1 \
    || fail "an imported entry names a team path: $(cat "$tmp/c.neutral.out")"
fi
# Untracked, never staged.
untracked "$RC" > "$tmp/c.st"
[ "$(grep -c '^?? ' "$tmp/c.st")" = 2 ] && [ "$(wc -l < "$tmp/c.st" | tr -d ' ')" = 2 ] || fail "git status of $RC: $(cat "$tmp/c.st")"
[ ! -e "$P/$OPS/LEARNINGS.md" ] || fail "an index file was written"
# The derived index lists both, and each row's title names its entry file
# through the slug rule.
(cd "$P" && bash .claude/tools/learnings-index.sh "$RC") > "$tmp/index" 2>&1
has "$tmp/index" "| $TODAY | Migrated rule 1 | migration | $RC/$TODAY-migrated-rule-1-"
has "$tmp/index" "| $TODAY | Migrated rule 2 | migration | $RC/$TODAY-migrated-rule-2-"
sed -n 's/^| \([0-9-]*\) | \(Migrated rule [0-9]*\) | migration | .*\/\([^/]*\) |$/\1\t\2\t\3/p' "$tmp/index" > "$tmp/rows"
[ "$(wc -l < "$tmp/rows" | tr -d ' ')" = 2 ] || fail "expected 2 migrated rows: $(cat "$tmp/index")"
while IFS="$(printf '\t')" read -r d t f; do
  printf '%s\n' "$f" | grep -qE -- "^$d-$(slug "$t")-[0-9a-f]{6}\.md$" || fail "row '$t' names $f, not its slug"
done < "$tmp/rows"
[ -f "$P/$CAPS/.legacy-rules-imported" ] || fail "no stamp"
has "$P/$CAPS/.legacy-rules-imported" "$TODAY"
has "$P/$CAPS/.legacy-rules-imported" "lines=2"
(cd "$P" && bash .claude/checks/verify-learnings-inbox.sh "$RC") > "$tmp/inbox" 2>&1; irc=$?
[ "$irc" = 1 ] || fail "remarks check exit $irc, expected 1 (pending marks): $(cat "$tmp/inbox")"
has "$tmp/inbox" "2 pending marks"
lacks "$tmp/inbox" "longer than"

case="c: second run"
before="$(snap "$P")"; run
expect_rc 0
has "$tmp/out" "project: in place ($NEW)"
lacks "$tmp/out" "private copy kept"
lacks "$tmp/out" "note:"
[ "$before" = "$(snap "$P")" ] || fail "a second run changed files"

# --- (k) --drop-legacy ----------------------------------------------------------
case="k: drop legacy after (c)"
# The stamp is present; a line authored since must still reach the remarks
# dir, once, and the two already there must not come again.
printf -- '- Third Z %s source: user\n' "$EM" >> "$P/$OLD/PROJECT-RULES.md"
rm -rf "$tmp/c.drop"; cp -R "$P/$OLD" "$tmp/c.drop"
run --drop-legacy --dry-run
expect_rc 0
has "$tmp/out" "would: project: private copy removed (backup $OPS/legacy-knowledge-"
has "$tmp/out" "; 1 authored lines kept as remarks)"
[ -d "$P/$OLD" ] || fail "a dry run removed $OLD"
run --drop-legacy
expect_rc 0
[ ! -e "$P/$OLD" ] || fail "$OLD still there"
bk="$(ls -d "$P/$OPS"/legacy-knowledge-* 2>/dev/null | head -1)"
[ -n "$bk" ] || fail "no backup"
[ -n "$bk" ] && { diff -r "$tmp/c.drop" "$bk" > "$tmp/diff" 2>&1 || fail "backup differs: $(head -c 400 "$tmp/diff")"; }
has "$tmp/out" "project: private copy removed (backup $OPS/legacy-knowledge-"
has "$tmp/out" "; 1 authored lines kept as remarks)"
has "$tmp/out" "note: 1 $UNOTE"
[ -n "$(one_of "$P/$RC" "$TODAY-migrated-rule-1")" ] || fail "an entry was lost"
E3="$(one_of "$P/$RC" "$TODAY-migrated-rule-3")"
[ -n "$E3" ] && { tr -d '\r' < "$E3" | grep -qxF "[PROMOTE] PROJECT-RULES.md $EM Third Z" || fail "entry 3 mark: $(cat "$E3")"; } \
  || fail "the line authored after the stamp was not kept: $(ls "$P/$RC")"
[ "$(ls "$P/$RC" | grep -c -e '-migrated-rule-')" = 3 ] || fail "expected exactly 3 entries: $(ls "$P/$RC")"
for r in "Always X" "Never Y" "Third Z"; do
  [ "$(cat "$P/$RC"/*.md | tr -d '\r' | grep -cxF "[PROMOTE] PROJECT-RULES.md $EM $r")" = 1 ] || fail "'$r' is not in the remarks dir exactly once"
done
[ ! -e "$P/$OPS/LEARNINGS.md" ] || fail "an index file was written"
(cd "$P" && bash .claude/tools/learnings-index.sh "$RC") > "$tmp/index" 2>&1
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
cp "$P/$OLD/learnings/2026-10-01-migrated-rule-4.md" "$tmp/d.e4"
run
expect_rc 0
has "$tmp/out" "operative: moved 2 entries to $OPS"
has "$tmp/out" "remarks: $RC: 1 moved, 0 already there"
has "$tmp/out" "(1 authored lines kept as remarks)"
has "$tmp/out" "note: 2 $UNOTE"
same "$tmp/d.e4" "$P/$RC/$(rname "$tmp/d.e4" 2026-10-01-migrated-rule-4)"
E5="$(one_of "$P/$RC" "$TODAY-migrated-rule-5")"
[ -n "$E5" ] || fail "entry not numbered after the highest: $(ls "$P/$RC")"
[ -n "$E5" ] && { tr -d '\r' < "$E5" | grep -qxF "[PROMOTE] PROJECT-RULES.md $EM Never Y" || fail "entry 5 mark: $(cat "$E5")"; }
[ "$(ls "$P/$RC" | grep -c -e '-migrated-rule-')" = 2 ] || fail "unexpected entries: $(ls "$P/$RC")"
# the older index moves aside byte for byte and gains no row
di="$(dropped_index)"
if [ -n "$di" ]; then same "$tmp/d.index" "$di"; else fail "no dropped-index file: $(ls "$P/$OPS")"; fi
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
committed_copy
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

# --- (m) an interrupted import: the remarks without the stamp ---------------------
case="m: interrupted import"
new_project m
committed_copy
{ printf -- '- Always X %s source: user\n' "$EM"; printf -- '- Never Y %s source: user\n' "$EM"; } >> "$P/$OLD/PROJECT-RULES.md"
run
expect_rc 0
has "$tmp/out" "(2 authored lines kept as remarks)"
# What an interrupt after the remarks and before the stamp leaves.
rm -f "$P/$CAPS/.legacy-rules-imported"
run
expect_rc 0
has "$tmp/out" "(0 authored lines kept as remarks)"
lacks "$tmp/out" "note:"
[ "$(ls "$P/$RC" | grep -c -e '-migrated-rule-')" = 2 ] || fail "an entry was written twice: $(ls "$P/$RC")"
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
has "$tmp/out" "(0 authored lines kept as remarks)"
[ -z "$(ls "$P/$RC" 2>/dev/null | grep -e '-migrated-rule-')" ] || fail "an entry was written: $(ls "$P/$RC")"
printf -- '- Other W %s source: user\n' "$EM" >> "$P/$OLD/PROJECT-RULES.md"
run --drop-legacy
expect_rc 0
has "$tmp/out" "; 1 authored lines kept as remarks)"

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
same "$tmp/n1.orig/learnings/a.md" "$P/$OPS/learnings/a.md"
run
expect_rc 0
has "$tmp/out" "project: waiting for $NEW in the repository; the first knowledge commit is made with --first-commit"
has "$tmp/out" "remarks: $RL: 1 moved, 0 already there"
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

# --- the old inbox moves into the remarks dir ----------------------------------------
# ops_inbox <name>: a per-copy operative dir as 5.0.0 left it: an old index
# of two rows, two entry files, the capabilities file; a copy in $tmp/<name>.ops.
ops_inbox() {
  mkdir -p "$P/$OPS/learnings" "$P/$CAPS"
  printf '# Dream Team Learnings Inbox\n\n## Index\n\n| Date | Title | Tags |\n|------|-------|------|\n| 2026-10-01 | A | a |\n| 2026-10-02 | B | b |\n' > "$P/$OPS/LEARNINGS.md"
  printf '## [2026-10-01] A\n- **Tags:** a\n' > "$P/$OPS/learnings/a.md"
  printf '## [2026-10-02] B\r\n- **Tags:** b\r\n' > "$P/$OPS/learnings/b.md"
  printf '# Capabilities\n\n- shell: bash\n' > "$P/$CAPS/CAPABILITIES.md"
  rm -rf "$tmp/$1.ops"; cp -R "$P/$OPS" "$tmp/$1.ops"
}

case="ra: per-copy entries, the knowledge committed"
new_project ra
committed_copy
ops_inbox ra
run
expect_rc 0
same "$tmp/ra.ops/learnings/a.md" "$P/$RC/$(rname "$tmp/ra.ops/learnings/a.md" a)"
same "$tmp/ra.ops/learnings/b.md" "$P/$RC/$(rname "$tmp/ra.ops/learnings/b.md" b)"
[ "$(nfiles "$P/$RC")" = 2 ] || fail "the remarks dir holds: $(ls "$P/$RC")"
[ ! -e "$P/$OPS/learnings" ] || fail "entries left per copy: $(ls "$P/$OPS/learnings")"
same "$tmp/ra.ops/claude/CAPABILITIES.md" "$P/$CAPS/CAPABILITIES.md"
has "$tmp/out" "remarks: $RC: 2 moved, 0 already there"
has "$tmp/out" "note: 2 $UNOTE"
untracked "$RC" > "$tmp/ra.st"
[ "$(grep -c '^?? ' "$tmp/ra.st")" = 2 ] && [ "$(wc -l < "$tmp/ra.st" | tr -d ' ')" = 2 ] || fail "git status of $RC: $(cat "$tmp/ra.st")"
[ -z "$(cd "$P" && git diff --cached --name-only)" ] || fail "something was staged"
bk="$(inbox_backup)"
[ -n "$bk" ] && [ -f "$bk/learnings/a.md" ] && [ -f "$bk/learnings/b.md" ] && [ -f "$bk/LEARNINGS.md" ] || fail "no inbox backup: $(ls "$P/$OPS")"

case="ra: second run, then an entry already there"
before="$(snap "$P")"; run
expect_rc 0
has "$tmp/out" "remarks: $RC: nothing to move"
lacks "$tmp/out" "note:"
[ "$before" = "$(snap "$P")" ] || fail "a second run changed files"
# The same entry once more, per copy: it is already there; no duplicate.
mkdir -p "$P/$OPS/learnings"; cp "$tmp/ra.ops/learnings/a.md" "$P/$OPS/learnings/a.md"
run
expect_rc 0
has "$tmp/out" "remarks: $RC: 0 moved, 1 already there"
lacks "$tmp/out" "note:"
[ "$(nfiles "$P/$RC")" = 2 ] || fail "a duplicate: $(ls "$P/$RC")"
[ ! -e "$P/$OPS/learnings/a.md" ] || fail "the source of an entry already there was kept"

case="rb: inline entries are lifted, then moved"
new_project rb
mkdir -p "$P/$OPS"
{ printf '# Dream Team Learnings Inbox\n\n## Index\n\n| Date | Title | Tags |\n|------|-------|------|\n| 2026-10-02 | Lifted One | x |\n| 2026-10-03 | Lifted: Two! | y |\n\n'
  printf '## [2026-10-02] Lifted One\n- **Tags:** x\n\n'
  printf '## [2026-10-03] Lifted: Two!\r\n- **Tags:** y\r\n\r\n'
  printf '## [2026-10-02] Lifted One\n- **Tags:** z\n\n'
  printf '## [2026-10-04] \320\237\321\200\320\270\n- **Tags:** w\n'; } > "$P/$OPS/LEARNINGS.md"
cp "$P/$OPS/LEARNINGS.md" "$tmp/rb.index"
before="$(snap "$P")"; run --dry-run
expect_rc 0
has "$tmp/out" "would: remarks: $RL: 4 moved, 0 already there"
[ "$before" = "$(snap "$P")" ] || fail "a dry run changed files"
run
expect_rc 0
has "$tmp/out" "remarks: $RL: 4 moved, 0 already there"
printf '## [2026-10-02] Lifted One\n- **Tags:** x\n\n' > "$tmp/rb.1"
printf '## [2026-10-03] Lifted: Two!\r\n- **Tags:** y\r\n\r\n' > "$tmp/rb.2"
printf '## [2026-10-02] Lifted One\n- **Tags:** z\n\n' > "$tmp/rb.3"
# A title with no ASCII letter or digit has an empty slug: the name says "entry".
printf '## [2026-10-04] \320\237\321\200\320\270\n- **Tags:** w\n' > "$tmp/rb.4"
same "$tmp/rb.1" "$P/$RL/$(rname "$tmp/rb.1" 2026-10-02-lifted-one)"
same "$tmp/rb.2" "$P/$RL/$(rname "$tmp/rb.2" 2026-10-03-lifted-two)"
same "$tmp/rb.3" "$P/$RL/$(rname "$tmp/rb.3" 2026-10-02-lifted-one-2)"
same "$tmp/rb.4" "$P/$RL/$(rname "$tmp/rb.4" 2026-10-04-entry)"
[ "$(nfiles "$P/$RL")" = 4 ] || fail "the remarks dir holds: $(ls "$P/$RL")"
[ ! -e "$P/$OPS/learnings" ] || fail "lifted entries left per copy: $(ls "$P/$OPS/learnings")"
di="$(dropped_index)"
if [ -n "$di" ]; then same "$tmp/rb.index" "$di"; else fail "no dropped-index file: $(ls "$P/$OPS")"; fi
bk="$(inbox_backup)"
[ -n "$bk" ] && same "$tmp/rb.index" "$bk/LEARNINGS.md"

case="rb: an unclosed fence refuses"
new_project rb2
mkdir -p "$P/$OPS"
printf '## [2026-10-02] Fenced\n```\nnever closed\n' > "$P/$OPS/LEARNINGS.md"
before="$(snap "$P")"; run
expect_rc 1
has "$tmp/err" "fenced block"
[ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"

case="rc: review exceptions become entries"
new_project rc
mkdir -p "$P/$OPS"
X1="src/pay/a.cs $MD \"x = 1;\" $MD Security $EM accepted 2026-10-05: \"keep\" (bugfix_x F-1)"
X2="lib/b.ts $MD \"y()\" $MD Style $EM accepted 2026-10-06: \"fine\" (bugfix_y F-2)"
printf '# Accepted exceptions\n- %s\n- %s\r\n' "$X1" "$X2" > "$P/$OPS/review-exceptions.md"
cp "$P/$OPS/review-exceptions.md" "$tmp/rc.exc"
run
expect_rc 0
printf '## [2026-10-05] exception src/pay/a.cs\n[EXCEPTION] %s\n' "$X1" > "$tmp/rc.1"
printf '## [2026-10-06] exception lib/b.ts\n[EXCEPTION] %s\n' "$X2" > "$tmp/rc.2"
same "$tmp/rc.1" "$P/$RL/$(rname "$tmp/rc.1" 2026-10-05-exception-src-pay-a-cs)"
same "$tmp/rc.2" "$P/$RL/$(rname "$tmp/rc.2" 2026-10-06-exception-lib-b-ts)"
[ "$(nfiles "$P/$RL")" = 2 ] || fail "the remarks dir holds: $(ls "$P/$RL")"
[ ! -e "$P/$OPS/review-exceptions.md" ] || fail "review-exceptions.md is still there"
[ ! -e "$P/$OPS/learnings" ] || fail "exception entries left per copy: $(ls "$P/$OPS/learnings")"
has "$tmp/out" "remarks: $RL: 2 moved, 0 already there"
bk="$(inbox_backup)"
[ -n "$bk" ] && same "$tmp/rc.exc" "$bk/review-exceptions.md"
before="$(snap "$P")"; run
expect_rc 0
has "$tmp/out" "remarks: $RL: nothing to move"
[ "$before" = "$(snap "$P")" ] || fail "a second run changed files"

case="rd: the flip copies the private copy's remarks"
new_project rd operative
run
expect_rc 0
has "$tmp/out" "remarks: $RL: 1 moved, 0 already there"
printf '## [2026-10-07] Later\n- **Tags:** l\n' > "$tmp/rd.later"
cp "$tmp/rd.later" "$P/$RL/$(rname "$tmp/rd.later" 2026-10-07-later)"
rm -rf "$tmp/rd.rl"; cp -R "$P/$RL" "$tmp/rd.rl"
committed_copy
before="$(snap "$P")"; run --dry-run
expect_rc 0
grep -e '^would: remarks: ' -e '^would: note: ' "$tmp/out" | sed 's/^would: //' > "$tmp/rd.dry"
[ "$before" = "$(snap "$P")" ] || fail "a dry run changed files"
run
expect_rc 0
grep -e '^remarks: ' -e '^note: ' "$tmp/out" > "$tmp/rd.real"
same "$tmp/rd.dry" "$tmp/rd.real"
has "$tmp/out" "remarks: $RC: nothing to move"
has "$tmp/out" "remarks: $RC: 2 copied from $RL, 0 already there"
has "$tmp/out" "note: 2 $UNOTE"
diff -r "$tmp/rd.rl" "$P/$RL" > "$tmp/diff" 2>&1 || fail "the originals changed: $(head -c 400 "$tmp/diff")"
diff -r "$tmp/rd.rl" "$P/$RC" > "$tmp/diff" 2>&1 || fail "the copies differ: $(head -c 400 "$tmp/diff")"
case="rd: a third run copies nothing"
before="$(snap "$P")"; run
expect_rc 0
lacks "$tmp/out" "copied from"
lacks "$tmp/out" "note:"
[ "$before" = "$(snap "$P")" ] || fail "a third run changed files"
# A remark the refresh consumed does not come back.
rm -f "$P/$RC/$(rname "$tmp/rd.later" 2026-10-07-later)"
before="$(snap "$P")"; run
expect_rc 0
[ "$before" = "$(snap "$P")" ] || fail "a consumed remark came back"

case="re: --first-commit copies the private copy's remarks"
new_project re operative
run
expect_rc 0
rm -rf "$tmp/re.rl"; cp -R "$P/$RL" "$tmp/re.rl"
before="$(snap "$P")"; run --first-commit --dry-run
expect_rc 0
has "$tmp/out" "would: remarks: $RC: 1 copied from $RL, 0 already there"
[ "$before" = "$(snap "$P")" ] || fail "a dry run changed files"
run --first-commit
expect_rc 0
has "$tmp/out" "remarks: $RC: nothing to move"
has "$tmp/out" "remarks: $RC: 1 copied from $RL, 0 already there"
lacks "$tmp/out" "note:"
diff -r "$tmp/re.rl" "$P/$RL" > "$tmp/diff" 2>&1 || fail "the originals changed: $(head -c 400 "$tmp/diff")"
diff -r "$tmp/re.rl" "$P/$RC" > "$tmp/diff" 2>&1 || fail "the copies differ: $(head -c 400 "$tmp/diff")"
commit_knowledge
before="$(snap "$P")"; run
expect_rc 0
lacks "$tmp/out" "copied from"
[ "$before" = "$(snap "$P")" ] || fail "the run after the first commit changed files"

case="rf: --drop-legacy carries the private copy's remarks and removes them"
new_project rf operative
run
expect_rc 0
printf '## [2026-10-08] Old branch\n- **Tags:** o\n' > "$tmp/rf.old"
committed_copy
run
expect_rc 0
has "$tmp/out" "remarks: $RC: 1 copied from $RL, 0 already there"
# A remark accepted later on a branch without knowledge, in the legacy remarks dir.
cp "$tmp/rf.old" "$P/$RL/$(rname "$tmp/rf.old" 2026-10-08-old-branch)"
rm -rf "$tmp/rf.rl"; cp -R "$P/$RL" "$tmp/rf.rl"
before="$(snap "$P")"; run --drop-legacy --dry-run
expect_rc 0
has "$tmp/out" "would: remarks: $RC: 1 copied from $RL, 1 already there"
[ "$before" = "$(snap "$P")" ] || fail "a dry run changed files"
run --drop-legacy
expect_rc 0
has "$tmp/out" "remarks: $RC: 1 copied from $RL, 1 already there"
has "$tmp/out" "note: 1 $UNOTE"
[ ! -e "$P/$RL" ] || fail "$RL is still there: $(ls "$P/$RL")"
[ ! -e "$P/$OLD" ] || fail "$OLD is still there"
diff -r "$tmp/rf.rl" "$P/$RC" > "$tmp/diff" 2>&1 || fail "not carried: $(head -c 400 "$tmp/diff")"
pbk="$(ls -d "$P/$OPS"/legacy-knowledge-*-proposals 2>/dev/null | head -1)"
if [ -n "$pbk" ]; then diff -r "$tmp/rf.rl" "$pbk" > "$tmp/diff" 2>&1 || fail "the backup of $RL differs: $(head -c 400 "$tmp/diff")"
else fail "no backup of $RL: $(ls "$P/$OPS")"; fi
out="$(cd "$P" && bash .claude/tools/knowledge-dir.sh remarks)"
[ "$out" = "$RC" ] || fail "the resolver prints '$out' as the remarks dir, expected $RC"

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
has "$tmp/out" "remarks: $RL: 1 moved, 0 already there"
run --drop-legacy
expect_rc 1

case="source"
if [ -f "$SCRIPT" ]; then
  ! grep -nE '\.claude/|\.claude-tracking|Claude Code' "$SCRIPT" || fail "a literal team path, legacy name or edition name in the script"
  ! grep -niE 'profile|DREAM_TEAM_PROFILE|inbox\.sh|knowledge-dir\.sh"? key' "$SCRIPT" || fail "the profile, the project key or the inbox tool in the script"
  if grep -nE '\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^)|declare -A|mapfile|readarray' "$SCRIPT"; then fail "bash-4-only construct"; fi
  [ "$(tr -cd '\r' < "$SCRIPT" | wc -c | tr -d ' ')" = 0 ] || fail "the script has CR line endings"
fi
grep -qxF 'tools/migrate-knowledge.sh text eol=lf' "$ROOT/.gitattributes" || fail ".gitattributes lacks the LF pin"
tr -d '\r' < "$ROOT/team-manifest.json" | grep -qF '"migration": "tools/migrate-knowledge.sh"' || fail "manifest lacks knowledge.migration"
tr -d '\r' < "$ROOT/team-manifest.json" | grep -qF '"migrateKnowledge": "bash checks/verify-migrate-knowledge.sh",' || fail "manifest lacks checks.migrateKnowledge"

[ "$status" = 0 ] && echo "verify-migrate-knowledge: all cases passed"
exit "$status"
