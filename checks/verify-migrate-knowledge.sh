#!/usr/bin/env bash
# Tests tools/migrate-knowledge.sh against throwaway projects, each a fresh git
# repository with the real team tree copied to .claude/: the operative files
# moving out, the project files waiting or moving to the committed directory,
# authored lines of a private copy kept as inbox entries, the refusals and
# that a refusal changes nothing, dry run, reruns, dropping the private copy,
# and what the resolver prints afterwards.
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
TODAY="$(date +%Y-%m-%d)"
EM="$(printf '\342\200\224')"   # the em dash, as bytes

# The real team tree, copied once; every fixture copies it to .claude/.
TEAM="$tmp/team"
mkdir -p "$TEAM"
for d in agents skills templates tools checks hooks team-manifest.json; do
  [ -e "$ROOT/$d" ] && cp -R "$ROOT/$d" "$TEAM/"
done

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
    cp "$TEAM/templates/learnings.md" "$P/$OLD/LEARNINGS.md"
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
# the slug templates/learnings-entry.md derives from an index title
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
fi
L="$P/$OPS/LEARNINGS.md"
[ -f "$L" ] || fail "no index created"
if [ -f "$L" ]; then
  tr -d '\r' < "$L" | grep -qxF "| $TODAY | Migrated rule 1 | migration |" || fail "index row 1 missing"
  tr -d '\r' < "$L" | grep -qxF "| $TODAY | Migrated rule 2 | migration |" || fail "index row 2 missing"
  tr -d '\r' < "$L" | grep -qF "# Dream Team Learnings Inbox" || fail "index not created from the template"
  # rows sit inside the table, before the template's comment
  r="$(tr -d '\r' < "$L" | grep -nF "| Migrated rule 2 |" | cut -d: -f1)"; c="$(tr -d '\r' < "$L" | grep -nF '<!-- INDEX' | cut -d: -f1)"
  [ -n "$r" ] && [ -n "$c" ] && [ "$r" -lt "$c" ] || fail "rows not inside the index table"
  lines="$(wc -l < "$L" | tr -d ' ')"; crs="$(tr -cd '\r' < "$L" | wc -c | tr -d ' ')"
  [ "$crs" = 0 ] || [ "$crs" = "$lines" ] || fail "mixed line endings in the index ($crs CR, $lines lines)"
  # every row's title names its entry file through the slug rule
  tr -d '\r' < "$L" | sed -n 's/^| \([0-9-]*\) | \(Migrated rule [0-9]*\) | migration |$/\1\t\2/p' > "$tmp/rows"
  [ "$(wc -l < "$tmp/rows" | tr -d ' ')" = 2 ] || fail "expected 2 migrated rows"
  while IFS="$(printf '\t')" read -r d t; do
    [ -f "$P/$OPS/learnings/$d-$(slug "$t").md" ] || fail "row '$t' names no entry file"
  done < "$tmp/rows"
fi
[ -f "$P/$CAPS/.legacy-rules-imported" ] || fail "no stamp"
has "$P/$CAPS/.legacy-rules-imported" "$TODAY"
has "$P/$CAPS/.legacy-rules-imported" "lines=2"
(cd "$P" && bash .claude/checks/verify-learnings-inbox.sh "$OPS") > "$tmp/inbox" 2>&1; irc=$?
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
[ "$(tr -d '\r' < "$P/$OPS/LEARNINGS.md" | grep -c '| Migrated rule ')" = 3 ] || fail "expected 3 index rows"

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
tr -d '\r' < "$TEAM/templates/learnings.md" | awk -v BINMODE=3 '
  { printf "%s\r\n", $0 }
  /^\|------\|-------\|------\|$/ { printf "| 2026-10-01 | Migrated rule 4 | migration |\r\n" }' > "$P/$OLD/LEARNINGS.md"
printf '## [2026-10-01] Migrated rule 4\r\n- **Tags:** migration\r\n' > "$P/$OLD/learnings/2026-10-01-migrated-rule-4.md"
run
expect_rc 0
has "$tmp/out" "operative: moved 2 entries to $OPS"
has "$tmp/out" "(1 authored lines kept as inbox entries)"
E5="$P/$OPS/learnings/$TODAY-migrated-rule-5.md"
[ -f "$E5" ] || fail "entry not numbered after the highest: $(ls "$P/$OPS/learnings")"
[ -f "$E5" ] && { tr -d '\r' < "$E5" | grep -qxF "[PROMOTE] PROJECT-RULES.md $EM Never Y" || fail "entry 5 mark: $(cat "$E5")"; }
[ -z "$(ls "$P/$OPS/learnings" | grep -e '-migrated-rule-[1-36]\.md$')" ] || fail "unexpected entry: $(ls "$P/$OPS/learnings")"
L="$P/$OPS/LEARNINGS.md"
lines="$(wc -l < "$L" | tr -d ' ')"; crs="$(tr -cd '\r' < "$L" | wc -c | tr -d ' ')"
[ "$crs" = "$lines" ] || fail "CRLF index not kept CRLF ($crs CR, $lines lines)"
r4="$(tr -d '\r' < "$L" | grep -nxF "| 2026-10-01 | Migrated rule 4 | migration |" | cut -d: -f1)"
r5="$(tr -d '\r' < "$L" | grep -nxF "| $TODAY | Migrated rule 5 | migration |" | cut -d: -f1)"
[ -n "$r4" ] && [ -n "$r5" ] && [ "$r5" = "$((r4 + 1))" ] || fail "row 5 not right after row 4 ($r4, $r5)"
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
cp "$TEAM/templates/learnings.md" "$P/$OTHER/LEARNINGS.md"
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

# --- (m) an interrupted import: an entry without its index row --------------------
case="m: interrupted import"
new_project m
mkdir -p "$P/$NEW"
printf '# Project Rules\n\n- Keep the build green.\n' > "$P/$NEW/PROJECT-RULES.md"
commit_knowledge
{ printf -- '- Always X %s source: user\n' "$EM"; printf -- '- Never Y %s source: user\n' "$EM"; } >> "$P/$OLD/PROJECT-RULES.md"
run
expect_rc 0
has "$tmp/out" "(2 authored lines kept as inbox entries)"
# What an interrupt after the entry files and before the rows and stamp leaves.
L="$P/$OPS/LEARNINGS.md"
grep -v -F "| Migrated rule 2 |" "$L" > "$tmp/idx" && cat "$tmp/idx" > "$L"
rm -f "$P/$CAPS/.legacy-rules-imported"
run
expect_rc 0
has "$tmp/out" "(0 authored lines kept as inbox entries)"
[ "$(tr -d '\r' < "$L" | grep -cxF "| $TODAY | Migrated rule 2 | migration |")" = 1 ] || fail "the missing row was not restored once"
[ "$(tr -d '\r' < "$L" | grep -cxF "| $TODAY | Migrated rule 1 | migration |")" = 1 ] || fail "row 1 duplicated or lost"
[ "$(ls "$P/$OPS/learnings" | grep -c -e '-migrated-rule-')" = 2 ] || fail "an entry was written twice: $(ls "$P/$OPS/learnings")"
has "$P/$CAPS/.legacy-rules-imported" "lines=0"

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
cp "$TEAM/templates/learnings.md" "$P/$OTHER/LEARNINGS.md"
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
cp "$TEAM/templates/learnings.md" "$P/$OTHER/LEARNINGS.md"
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
cp "$TEAM/templates/learnings.md" "$P/$OTHER/LEARNINGS.md"
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
