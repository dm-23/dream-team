#!/usr/bin/env bash
# Repo-only test of tools/knowledge-refresh.sh: every fixture is a fresh
# repository with a release branch "rel" holding committed knowledge, a fake
# origin address (never contacted) and the tracking dir excluded from git, in a
# temporary directory. Case (f) repeats (a) and (b) under a path that holds a
# space. Never touches the real profile.
#
#   bash checks/verify-knowledge-refresh.sh    (run from anywhere)
#
# Exit 0 = every case passed. 1 = a case failed; each failure is named.
set -uo pipefail
export LC_ALL=C

TEAM="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$TEAM/tools/knowledge-refresh.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/refresh.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT
export DREAM_TEAM_PROFILE="$WORK/profile"
export GIT_AUTHOR_NAME=refresh GIT_AUTHOR_EMAIL=refresh@example.com
export GIT_COMMITTER_NAME=refresh GIT_COMMITTER_EMAIL=refresh@example.com
KD=.dream-team/knowledge
STATE=.dream-team-tracking/.knowledge-refresh
MARKER=.dream-team-tracking/.team-mode

FAILS=0
case=""
fail() { echo "FAIL [$case]: $1"; FAILS=$((FAILS + 1)); }

[ -f "$TOOL" ] || { echo "FAIL: $TOOL does not exist"; exit 1; }

P=""
g() { git -C "$P" "$@"; }
# git with a <rev>:<path> argument, which Git Bash would rewrite as a path list
gx() { (cd "$P" && MSYS_NO_PATHCONV=1 git "$@"); }
# new_fixture <dir> [untracked]: rel with code and committed knowledge (no
# BASELINE yet); with "untracked", the knowledge files exist but nothing under
# the knowledge dir is committed.
new_fixture() {
  P="$1"
  mkdir -p "$P"
  g init -q
  g config core.autocrlf true
  g config core.safecrlf false
  g symbolic-ref HEAD refs/heads/rel
  g remote add origin "https://example.invalid/acme/refresh.git"
  printf '.dream-team-tracking/\n' >> "$P/.git/info/exclude"
  mkdir -p "$P/src" "$P/$KD"
  printf 'code\n' > "$P/src/a.txt"
  printf 'tracked\n' > "$P/t.txt"
  g add -A && g commit -q -m "code"
  printf '# Overview\nCovers: src/**\n\nA project.\n' > "$P/$KD/PROJECT-OVERVIEW.md"
  printf '# Testing\nCovers: conventions\n\nTests.\n' > "$P/$KD/TESTING-CONVENTIONS.md"
  printf '# Old\nCovers: conventions\n\nGone soon.\n' > "$P/$KD/OLD.md"
  if [ "${2:-}" != untracked ]; then
    g add -A && g commit -q -m "knowledge"
  fi
}
# product_changes: a modified tracked file, a staged new file, an untracked file.
product_changes() {
  printf 'modified\n' >> "$P/t.txt"
  printf 'staged\n' > "$P/s.txt"; g add s.txt
  printf 'untracked\n' > "$P/u.txt"
}
product_intact() {
  local st
  st="$(g status --porcelain -- t.txt s.txt u.txt | tr -d '\r')"
  printf '%s\n' "$st" | grep -qxF ' M t.txt' || fail "t.txt is not modified any more: $st"
  printf '%s\n' "$st" | grep -qxF 'A  s.txt' || fail "s.txt is not staged any more: $st"
  printf '%s\n' "$st" | grep -qxF '?? u.txt' || fail "u.txt is not untracked any more: $st"
  grep -qxF modified "$P/t.txt" || fail "t.txt lost its change"
}
OUT="" ERR="" RC=0
run() { # the tool from the project root
  (cd "$P" && bash "$TOOL" "$@") > "$P.out" 2> "$P.err"; RC=$?
  OUT="$(cat "$P.out")"; ERR="$(cat "$P.err")"
}
rc() { [ "$RC" = "$1" ] || fail "exit $RC, wanted $1 (out: $OUT; err: $ERR)"; }
has() { case "$OUT$ERR" in *"$1"*) ;; *) fail "output lacks '$1' (out: $OUT; err: $ERR)";; esac; }
has_line() { grep -qxF -- "$1" "$P.out" || fail "no line '$1' in: $OUT"; }
cur() { g symbolic-ref -q --short HEAD | tr -d '\r'; }
on() { [ "$(cur)" = "$1" ] || fail "on '$(cur)', wanted '$1'"; }
works() { g for-each-ref --format='%(refname:short)' refs/heads/knowledge/ | tr -d '\r'; }
work_from_out() { sed -n 's/^refresh: on \(knowledge\/refresh-[^ ]*\) from .*$/\1/p' "$P.out"; }
snapshot() {
  {
    g status --porcelain
    g rev-parse HEAD
    g symbolic-ref -q HEAD || echo detached
    g for-each-ref --format='%(refname) %(objectname)' refs/heads/
    [ -f "$P/$STATE" ] && cat "$P/$STATE"
    find "$P/$KD" -type f | sort | while IFS= read -r f; do cksum "$f"; done
  } 2>&1 | tr -d '\r'
}
unchanged() { # <snapshot before>
  local now
  now="$(snapshot)"
  [ "$now" = "$1" ] || fail "the tree or the branch changed: before <$1> now <$now>"
}
RULE='# Always X
- Kind: rule
- Rule: Always X.
- Source: lead
- Added: 2026-11-11
'

# --- (a) and (b): begin, then finish with product changes present ---------------
case_ab() { # <fixture dir> <label>
  local label="$2" base short work n bad dt
  case="a $label"
  new_fixture "$1"
  product_changes
  base="$(g rev-parse HEAD | tr -d '\r')"
  short="$(g rev-parse --short HEAD | tr -d '\r')"
  run begin
  rc 0
  work="$(work_from_out)"
  case "$work" in
    knowledge/refresh-rel-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]) ;;
    *) fail "work branch '$work' is not knowledge/refresh-rel-<YYYYMMDD-HHmm>" ;;
  esac
  has_line "refresh: on $work from rel at $short"
  has_line "baseline: none"
  has_line "branch line: new"
  on "$work"
  [ "$(g rev-parse HEAD | tr -d '\r')" = "$base" ] || fail "the work branch is not at the base commit"
  [ -f "$P/$STATE" ] || fail "no state file"
  grep -qxF "branch=rel" "$P/$STATE" || fail "state lacks branch=rel: $(cat "$P/$STATE")"
  grep -qxF "base=$base" "$P/$STATE" || fail "state lacks base=$base"
  grep -qxF "work=$work" "$P/$STATE" || fail "state lacks work=$work"
  product_intact

  case="b $label"
  printf 'More.\n' >> "$P/$KD/PROJECT-OVERVIEW.md"
  mkdir -p "$P/$KD/rules"
  printf '%s' "$RULE" > "$P/$KD/rules/x.md"
  rm "$P/$KD/OLD.md"
  run finish
  rc 0
  on rel
  has_line "refresh: committed $(g rev-parse --short "$work" | tr -d '\r') on $work"
  has_line "push: git push -u origin $work"
  has_line "pull request: $work → rel; knowledge only"
  n="$(g rev-list --count "rel..$work" | tr -d '\r')"
  [ "$n" = 1 ] || fail "the work branch is $n commits ahead of rel, wanted 1"
  [ "$(g rev-parse "$work^" | tr -d '\r')" = "$base" ] || fail "the commit's parent is not the base"
  [ "$(g rev-parse rel | tr -d '\r')" = "$base" ] || fail "rel moved"
  bad="$(g diff --name-only rel "$work" | tr -d '\r' | grep -v "^$KD/")"
  [ -z "$bad" ] || fail "the commit holds paths outside the knowledge dir: $bad"
  for f in BASELINE rules/x.md OLD.md PROJECT-OVERVIEW.md; do
    g diff --name-only rel "$work" | tr -d '\r' | grep -qxF "$KD/$f" || fail "the commit lacks $KD/$f"
  done
  [ "$(g log -1 --format=%s "$work" | tr -d '\r')" = "knowledge: refresh rel to $short" ] \
    || fail "subject: $(g log -1 --format=%s "$work")"
  dt="$(g log -1 --format=%cs "$base" | tr -d '\r')"
  gx show "$work:$KD/BASELINE" > "$P.baseline"
  [ "$(cat "$P.baseline")" = "commit=$base
date=$dt
branch=rel" ] || fail "BASELINE in the commit: $(cat "$P.baseline")"
  if od -c "$P.baseline" | grep -q '\\r'; then fail "BASELINE has a CR"; fi
  product_intact
  [ -z "$(g status --porcelain -- "$KD" | tr -d '\r')" ] || fail "the knowledge dir differs from rel: $(g status --porcelain -- "$KD")"
  [ -z "$(g diff --name-only rel -- "$KD" | tr -d '\r')" ] || fail "the knowledge dir's worktree is not rel's"
  [ -f "$P/$KD/OLD.md" ] || fail "OLD.md was not put back from rel"
  [ ! -e "$P/$KD/BASELINE" ] || fail "BASELINE left in rel's worktree"
  [ ! -e "$P/$KD/rules/x.md" ] || fail "rules/x.md left in rel's worktree"
  [ ! -e "$P/$STATE" ] || fail "the state file is still there"
  WORKB="$work"
}

case_ab "$WORK/plain" plain
P="$WORK/plain"

# --- the branch line once BASELINE exists ----------------------------------------
case="branch line"
g merge -q --ff-only "$WORKB"
g branch -q -d "$WORKB"
base="$(g rev-parse HEAD | tr -d '\r')"
oldbase="$(gx show "rel:$KD/BASELINE" | sed -n 's/^commit=//p' | tr -d '\r')"
run begin
rc 0
has_line "baseline: ${oldbase:0:7}"
has_line "branch line: same"
run abort
rc 0
on rel
g checkout -q -b 'release/5.1_x'
run begin
rc 0
has_line "branch line: rel → release/5.1_x"
w="$(work_from_out)"
case "$w" in
  knowledge/refresh-release-5.1-x-[0-9]*) ;;
  *) fail "the slug of release/5.1_x: $w" ;;
esac
run abort
rc 0
on 'release/5.1_x'
g checkout -q rel
product_intact

# --- (c) finish refused by the shape check, then fixed ----------------------------
case="c"
P="$WORK/c"
new_fixture "$P"
base="$(g rev-parse HEAD | tr -d '\r')"
run begin
rc 0
work="$(work_from_out)"
printf '# New\n\nNo covers line.\n' > "$P/$KD/NEW.md"
run finish
rc 1
has 'NEW.md: no "Covers:" line in its first five lines'
on "$work"
[ "$(g rev-parse HEAD | tr -d '\r')" = "$base" ] || fail "a commit was made"
[ -f "$P/$STATE" ] || fail "the state file was removed"
printf '# New\nCovers: conventions\n\nNow covered.\n' > "$P/$KD/NEW.md"
run finish
rc 0
on rel
[ "$(g rev-list --count "rel..$work" | tr -d '\r')" = 1 ] || fail "no commit after the fix"
gx cat-file -e "$work:$KD/NEW.md" 2>/dev/null || fail "NEW.md not committed"

# neutral check refuses too
case="c neutral"
P="$WORK/c2"
new_fixture "$P"
run begin
rc 0
work="$(work_from_out)"
printf '# Bad\nCovers: conventions\n\nSee .claude/agents/x.md here.\n' > "$P/$KD/BAD.md"
run finish
rc 1
has 'names a team path'
on "$work"
run abort
rc 0
on rel

# --- (d) begin refusals ------------------------------------------------------------
case="d untracked knowledge"
P="$WORK/d1"
new_fixture "$P" untracked
before="$(snapshot)"
run begin
rc 1
unchanged "$before"

case="d dirty knowledge"
P="$WORK/d2"
new_fixture "$P"
printf 'dirty\n' >> "$P/$KD/PROJECT-OVERVIEW.md"
before="$(snapshot)"
run begin
rc 1
unchanged "$before"
g checkout -q -- "$KD"

case="d untracked file under the knowledge dir"
printf '# Stray\n' > "$P/$KD/STRAY.md"
before="$(snapshot)"
run begin
rc 1
unchanged "$before"
rm "$P/$KD/STRAY.md"

case="d open run marker"
mkdir -p "$P/.dream-team-tracking"
printf 'state=open\nrun=x\n' > "$P/$MARKER"
before="$(snapshot)"
run begin
rc 1
unchanged "$before"
printf 'run=x\n' > "$P/$MARKER"
before="$(snapshot)"
run begin
rc 1
unchanged "$before"

case="d closed run marker"
printf 'state=closed\r\nrun=x\r\n' > "$P/$MARKER"
run begin
rc 0
run abort
rc 0
rm "$P/$MARKER"

case="d detached HEAD"
g checkout -q --detach
before="$(snapshot)"
run begin
rc 1
unchanged "$before"
g checkout -q rel

case="d second begin"
run begin
rc 0
before="$(snapshot)"
run begin
rc 1
unchanged "$before"
[ "$(works | wc -l | tr -d ' ')" = 1 ] || fail "more than one work branch: $(works)"
run abort
rc 0

# --- (e) abort -----------------------------------------------------------------------
case="e"
P="$WORK/e"
new_fixture "$P"
product_changes
base="$(g rev-parse HEAD | tr -d '\r')"
run begin
rc 0
work="$(work_from_out)"
printf 'Edited.\n' >> "$P/$KD/PROJECT-OVERVIEW.md"
printf 'Staged.\n' >> "$P/$KD/TESTING-CONVENTIONS.md"; g add "$KD/TESTING-CONVENTIONS.md"
printf '# Junk\n' > "$P/$KD/junk.md"
mkdir -p "$P/$KD/topic"; printf '# T\n' > "$P/$KD/topic/t.md"
rm "$P/$KD/OLD.md"
run abort
rc 0
on rel
[ -z "$(g status --porcelain -- "$KD" | tr -d '\r')" ] || fail "the knowledge dir is not clean: $(g status --porcelain -- "$KD")"
[ -z "$(g diff --name-only "$base" -- "$KD" | tr -d '\r')" ] || fail "the knowledge dir differs from base"
[ ! -e "$P/$KD/junk.md" ] || fail "junk.md is still there"
[ ! -e "$P/$KD/topic" ] || fail "topic/ is still there"
[ -f "$P/$KD/OLD.md" ] || fail "OLD.md was not restored"
[ -z "$(works)" ] || fail "the work branch is still there: $(works)"
[ ! -e "$P/$STATE" ] || fail "the state file is still there"
product_intact

case="e no state"
run abort
rc 1
run finish
rc 1

# --- (f) a project path with a space -------------------------------------------------
case_ab "$WORK/with space/pro ject" spaced

# --- (g) finish --message-file -------------------------------------------------------
case="g"
P="$WORK/g"
new_fixture "$P"
run begin
rc 0
work="$(work_from_out)"
printf 'More.\n' >> "$P/$KD/PROJECT-OVERVIEW.md"
printf 'Refreshed the overview.\r\n\r\nVerified against src/.\r\n' > "$WORK/g-body.txt"
run finish --message-file "$WORK/g-body.txt"
rc 0
body="$(g log -1 --format=%b "$work" | tr -d '\r')"
want="$(tr -d '\r' < "$WORK/g-body.txt")"
[ "$body" = "$want" ] || fail "body <$body>, wanted <$want>"
[ "$(g log -1 --format=%s "$work" | tr -d '\r')" = "knowledge: refresh rel to $(g rev-parse --short rel | tr -d '\r')" ] \
  || fail "subject: $(g log -1 --format=%s "$work")"

case="d work branch exists already"
# A finished refresh leaves its work branch; a second begin within the same
# minute would want the same name. Checked only when the minute did not turn.
stamp="$(date +%Y%m%d-%H%M)"
g branch -q -f "knowledge/refresh-rel-$stamp" rel
before="$(snapshot)"
run begin
if [ "$(date +%Y%m%d-%H%M)" = "$stamp" ]; then
  rc 1
  has "exists already"
  unchanged "$before"
elif [ "$RC" = 0 ]; then
  run abort
fi
g branch -q -D "knowledge/refresh-rel-$stamp"
g branch -q -D "$work" 2>/dev/null

case="g missing message file"
run begin
rc 0
run finish --message-file "$WORK/none.txt"
rc 2
[ -f "$P/$STATE" ] || fail "the state file was removed"
run abort
rc 0

# --- usage ----------------------------------------------------------------------------
case="usage"
run bogus
rc 2
run
rc 2

if [ "$FAILS" -gt 0 ]; then exit 1; fi
echo "knowledge-refresh: ok"
true
