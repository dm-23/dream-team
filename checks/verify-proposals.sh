#!/usr/bin/env bash
# Repo-only test of tools/proposals.sh: every fixture is a fresh repository
# with a fake origin address (never contacted), a release branch "rel" holding
# committed knowledge, a work branch checked out, and the learnings inbox in a
# profile under DREAM_TEAM_PROFILE, in a temporary directory whose path holds a
# space. Never touches the real profile.
#
#   bash checks/verify-proposals.sh    (run from anywhere)
#
# Exit 0 = every case passed. 1 = a case failed; each failure is named.
set -uo pipefail
export LC_ALL=C

TEAM="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$TEAM/tools/proposals.sh"
DRIFT="$TEAM/tools/knowledge-drift.sh"
INBOXCHECK="$TEAM/checks/verify-learnings-inbox.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/proposals.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT
export DREAM_TEAM_PROFILE="$WORK/pro file"
export GIT_AUTHOR_NAME=prop GIT_AUTHOR_EMAIL=prop@example.com
export GIT_COMMITTER_NAME=prop GIT_COMMITTER_EMAIL=prop@example.com
KD=.dream-team/knowledge
PD="$KD/proposals"
TAB="$(printf '\t')"
CR="$(printf '\r')"
TODAY="$(date +%Y-%m-%d)"
EM="$(printf '\342\200\224')"   # the em dash, as bytes

FAILS=0
case=""
fail() { echo "FAIL [$case]: $1"; FAILS=$((FAILS + 1)); }

[ -f "$TOOL" ] || { echo "FAIL: $TOOL does not exist"; exit 1; }

P="" OPD=""
g() { git -C "$P" "$@"; }
# new_fixture <name> [dirty]: main with code, rel with committed knowledge,
# work checked out from rel; the inbox in the profile. With "dirty": a
# modified tracked file, a staged file and an untracked file.
new_fixture() {
  P="$WORK/$1"
  mkdir -p "$P"
  g init -q
  g config core.autocrlf true
  g config core.safecrlf false
  g symbolic-ref HEAD refs/heads/main
  g remote add origin "https://example.invalid/acme/$1.git"
  mkdir -p "$P/src"
  printf 'code\n' > "$P/src/a.txt"
  printf 'tracked\n' > "$P/t.txt"
  g add -A && g commit -q -m "code"
  g checkout -q -b rel
  mkdir -p "$P/$KD"
  printf '# Overview\nCovers: src/**\n\nA project.\n' > "$P/$KD/PROJECT-OVERVIEW.md"
  g add -A && g commit -q -m "knowledge"
  g checkout -q -b work
  printf 'work\n' > "$P/src/w.txt"
  g add -A && g commit -q -m "work"
  if [ "${2:-}" = dirty ]; then
    printf 'modified\n' >> "$P/t.txt"
    printf 'staged\n' > "$P/s.txt"; g add s.txt
    printf 'untracked\n' > "$P/u.txt"
  fi
  local key
  key="$(cd "$P" && bash "$TEAM/tools/knowledge-dir.sh" key | tr -d '\r')"
  [ -n "$key" ] || fail "fixture $1: no project key"
  OPD="$DREAM_TEAM_PROFILE/$key"
  mkdir -p "$OPD/learnings"
}
# entry <file> [crlf|crlf-noeol]: an inbox entry; its bytes are kept in
# $WORK/<fixture>.<file>.before.
entry() {
  local f="$OPD/learnings/$1"
  case "${2:-}" in
    crlf) printf '## [2026-11-01] %s\r\n- **Workflow:** Bug Fix\r\n- **Tags:** x\r\n' "$1" > "$f" ;;
    crlf-noeol) printf '## [2026-11-01] %s\r\n- **Workflow:** Bug Fix\r\n- **Tags:** x' "$1" > "$f" ;;
    *) printf '## [2026-11-01] %s\n- **Workflow:** Bug Fix\n- **Tags:** x\n' "$1" > "$f" ;;
  esac
  cp "$f" "$P.$1.before"
}
same_entry() { cmp -s "$OPD/learnings/$1" "$P.$1.before" || fail "entry $1 changed"; }
OUT="" ERR="" RC=0
run() { # the tool from the project root, its temporary files in $P.tmp
  mkdir -p "$P.tmp"
  (cd "$P" && TMPDIR="$P.tmp" bash "$TOOL" "$@") > "$P.out" 2> "$P.err"; RC=$?
  OUT="$(cat "$P.out")"; ERR="$(cat "$P.err")"
  [ -z "$(ls -A "$P.tmp")" ] || fail "temporary files left behind: $(ls -A "$P.tmp")"
  case "$OUT$ERR" in *"$DREAM_TEAM_PROFILE"*|*"pro file"*) fail "the profile path printed: $OUT $ERR";; esac
}
rc() { [ "$RC" = "$1" ] || fail "exit $RC, wanted $1 (out: $OUT; err: $ERR)"; }
has() { case "$OUT$ERR" in *"$1"*) ;; *) fail "output lacks '$1' (out: $OUT; err: $ERR)";; esac; }
has_line() { grep -qxF -- "$1" "$P.out" || fail "no line '$1' in: $OUT"; }
branches() { g for-each-ref --format='%(refname:short)' refs/heads/knowledge/ | tr -d '\r'; }
no_branch() { [ -z "$(branches)" ] || fail "a branch was created: $(branches)"; }
new_branch() { sed -n 's/^proposals: .* on \(knowledge\/proposals-[0-9]\{8\}-[0-9]\{6\}\) (base .*$/\1/p' "$P.out"; }
snapshot() {
  {
    g status --porcelain
    g rev-parse HEAD
    g write-tree
    g symbolic-ref --short HEAD
    g diff
    g diff --cached
  } 2>&1 | tr -d '\r'
}

# --- (a) the working tree, the index, HEAD and the branch are untouched ------
case="a: two entries from a dirty work branch"
new_fixture alpha dirty
g update-ref refs/remotes/origin/rel refs/heads/rel
entry 2026-11-01-one.md
entry 2026-11-02-two.md
BEFORE="$(snapshot)"
run submit --branch rel learnings/2026-11-01-one.md learnings/2026-11-02-two.md
rc 0
AFTER="$(snapshot)"
[ "$BEFORE" = "$AFTER" ] || fail "the working copy changed: before [$BEFORE] after [$AFTER]"
BR="$(new_branch)"
[ -n "$BR" ] || fail "no branch named in: $OUT"
if [ -n "$BR" ]; then
  [ "$(branches)" = "$BR" ] || fail "branches: $(branches)"
  SHORT="$(g rev-parse --short "$BR" | tr -d '\r')"
  has_line "proposals: 2 remarks committed as $SHORT on $BR (base refs/remotes/origin/rel)"
  has_line "push: git push -u origin $BR"
  has_line "pull request: $BR → rel; one commit, only files under $PD/"
  [ "$(g rev-parse "$BR^" | tr -d '\r')" = "$(g rev-parse rel | tr -d '\r')" ] || fail "the commit's parent is not rel"
  [ "$(g rev-list --count "rel..$BR" | tr -d '\r')" = 1 ] || fail "not one commit"
  NS="$(g diff --name-status rel "$BR" | tr -d '\r')"
  WANT="$(printf 'A\t%s\nA\t%s' "$PD/2026-11-01-one.md" "$PD/2026-11-02-two.md")"
  [ "$NS" = "$WANT" ] || fail "diff: [$NS]"
  for f in 2026-11-01-one.md 2026-11-02-two.md; do
    g cat-file blob "$(g rev-parse "$BR" | tr -d "$CR"):$PD/$f" | cmp -s - "$P.$f.before" || fail "blob $f differs from the entry"
    IFS= read -r last < <(tail -n 1 "$OPD/learnings/$f")
    [ "$last" = "[SUBMITTED $TODAY] $BR as $f" ] || fail "$f ends with '$last'"
    head -c "$(wc -c < "$P.$f.before")" "$OPD/learnings/$f" | cmp -s - "$P.$f.before" || fail "$f: the entry's own bytes changed"
  done
  MSG="$(g log -1 --format=%B "$BR" | tr -d '\r')"
  WANTMSG="$(printf 'knowledge(proposals): 2 remarks\n\n2026-11-01-one.md\n2026-11-02-two.md')"
  [ "$MSG" = "$WANTMSG" ] || fail "message: [$MSG]"
fi

# --- (b) CRLF ----------------------------------------------------------------
case="b: a CRLF entry"
new_fixture bravo
entry 2026-11-03-crlf.md crlf
entry 2026-11-03-noeol.md crlf-noeol
run submit --branch rel learnings/2026-11-03-crlf.md learnings/2026-11-03-noeol.md
rc 0
BR="$(new_branch)"
if [ -n "$BR" ]; then
  for f in 2026-11-03-crlf.md 2026-11-03-noeol.md; do
    g cat-file blob "$(g rev-parse "$BR" | tr -d "$CR"):$PD/$f" | cmp -s - "$P.$f.before" || fail "blob $f is not byte-identical"
  done
  printf '[SUBMITTED %s] %s as 2026-11-03-crlf.md\r\n' "$TODAY" "$BR" > "$WORK/want-tail"
  tail -c "$(wc -c < "$WORK/want-tail")" "$OPD/learnings/2026-11-03-crlf.md" | cmp -s - "$WORK/want-tail" \
    || fail "the CRLF entry's line: $(tail -n 1 "$OPD/learnings/2026-11-03-crlf.md" | od -c | head -3)"
  { cat "$P.2026-11-03-noeol.md.before"; printf '\r\n[SUBMITTED %s] %s as 2026-11-03-noeol.md\r\n' "$TODAY" "$BR"; } > "$WORK/want-noeol"
  cmp -s "$OPD/learnings/2026-11-03-noeol.md" "$WORK/want-noeol" || fail "the entry without a final newline: $(od -c "$OPD/learnings/2026-11-03-noeol.md" | tail -4)"
else
  fail "no branch: $OUT $ERR"
fi

# --- (c) a name taken in the release branch ----------------------------------
case="c: the same name with other bytes"
new_fixture charlie
entry 2026-11-04-taken.md
g checkout -q rel
mkdir -p "$P/$PD"
printf '## [2026-10-01] someone else\n' > "$P/$PD/2026-11-04-taken.md"
g -c core.autocrlf=false add -A && g commit -q -m "a proposal"
g checkout -q work
run submit --branch rel learnings/2026-11-04-taken.md
rc 0
BR="$(new_branch)"
if [ -n "$BR" ]; then
  NS="$(g diff --name-status rel "$BR" | tr -d '\r')"
  [ "$NS" = "A${TAB}$PD/2026-11-04-taken-2.md" ] || fail "diff: [$NS]"
  IFS= read -r last < <(tail -n 1 "$OPD/learnings/2026-11-04-taken.md")
  [ "$last" = "[SUBMITTED $TODAY] $BR as 2026-11-04-taken-2.md" ] || fail "line '$last'"
  MSG="$(g log -1 --format=%b "$BR" | tr -d '\r')"
  [ "$MSG" = "2026-11-04-taken-2.md" ] || fail "body: [$MSG]"
else
  fail "no branch: $OUT $ERR"
fi

case="c: the same name with the same bytes"
new_fixture charlie2
entry 2026-11-04-same.md
g checkout -q rel
mkdir -p "$P/$PD"
cp "$OPD/learnings/2026-11-04-same.md" "$P/$PD/2026-11-04-same.md"
g -c core.autocrlf=false add -A && g commit -q -m "the same proposal"
g checkout -q work
REL="$(g rev-parse rel | tr -d '\r')"
run submit --branch rel learnings/2026-11-04-same.md
rc 0
has "already proposed"
no_branch
same_entry 2026-11-04-same.md
[ "$(g rev-parse rel | tr -d '\r')" = "$REL" ] || fail "rel moved"

# --- (d) refusals change nothing ----------------------------------------------
case="d: refusals"
new_fixture delta
g branch bare main
entry 2026-11-05-ok.md
entry 2026-11-05-done.md
printf '[SUBMITTED 2026-10-01] knowledge/proposals-20261001-120000 as 2026-11-05-done.md\n' >> "$OPD/learnings/2026-11-05-done.md"
cp "$OPD/learnings/2026-11-05-done.md" "$P.2026-11-05-done.md.before"
printf 'not an entry\n' > "$OPD/learnings/notes.txt"

case="d: an unknown release branch"
run submit --branch nope learnings/2026-11-05-ok.md
rc 1; has "no local ref for nope"; no_branch; same_entry 2026-11-05-ok.md

case="d: a release branch without knowledge"
run submit --branch bare learnings/2026-11-05-ok.md
rc 1; has "bare has no committed knowledge"; no_branch; same_entry 2026-11-05-ok.md

case="d: an entry already submitted"
run submit --branch rel learnings/2026-11-05-ok.md learnings/2026-11-05-done.md
rc 1; has "learnings/2026-11-05-done.md"; no_branch
same_entry 2026-11-05-ok.md; same_entry 2026-11-05-done.md

case="d: a missing entry and one that is not *.md"
run submit --branch rel learnings/2026-11-05-ok.md learnings/2026-11-05-gone.md learnings/notes.txt
rc 1; has "learnings/2026-11-05-gone.md"; has "learnings/notes.txt"; no_branch
same_entry 2026-11-05-ok.md

case="d: a name outside the inbox"
run submit --branch rel ../escape.md
rc 2; no_branch

case="d: no name"
run submit --branch rel
rc 2; no_branch

case="d: the branch name exists already"
now="$(date +%s)"
for i in 0 1 2 3 4; do
  g branch "knowledge/proposals-$(date -d "@$((now + i))" +%Y%m%d-%H%M%S)" rel
done
NB="$(branches)"
run submit --branch rel learnings/2026-11-05-ok.md
rc 2
[ "$(branches)" = "$NB" ] || fail "branches changed: $(branches)"
same_entry 2026-11-05-ok.md
for b in $NB; do g branch -q -D "$b"; done

case="d: no configured identity"
(
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  export HOME="$WORK/nohome" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$WORK/nohome/.gitconfig"
  mkdir -p "$HOME"
  g config user.useConfigOnly true
  mkdir -p "$P.tmp"
  cd "$P" && TMPDIR="$P.tmp" bash "$TOOL" submit --branch rel learnings/2026-11-05-ok.md
) > "$P.out" 2> "$P.err"; RC=$?
OUT="$(cat "$P.out")"; ERR="$(cat "$P.err")"
g config --unset user.useConfigOnly
rc 2; no_branch; same_entry 2026-11-05-ok.md

# --- (e) dry run ----------------------------------------------------------------
case="e: --dry-run"
new_fixture echo
entry 2026-11-06-dry.md
OBJ="$(g count-objects -v | tr -d '\r')"
run submit --dry-run --branch rel learnings/2026-11-06-dry.md
rc 0
grep -q '^would: proposals: 1 remarks committed on knowledge/proposals-[0-9]\{8\}-[0-9]\{6\} (base refs/heads/rel)$' "$P.out" || fail "no would: proposals line: $OUT"
grep -q '^would: push: git push -u origin knowledge/proposals-' "$P.out" || fail "no would: push line: $OUT"
grep -q '^would: pull request: knowledge/proposals-.* → rel; one commit, only files under ' "$P.out" || fail "no would: pull request line: $OUT"
grep -v '^would: ' "$P.out" | grep -q . && fail "a line without would: $OUT"
no_branch
same_entry 2026-11-06-dry.md
[ "$(g count-objects -v | tr -d '\r')" = "$OBJ" ] || fail "objects were written"

# --- (f) status -----------------------------------------------------------------
case="f: status pending"
new_fixture foxtrot
entry 2026-11-07-st.md
entry 2026-11-07-plain.md
run submit --branch rel learnings/2026-11-07-st.md
rc 0
BR="$(new_branch)"
run status
rc 0
[ "$OUT" = "2026-11-07-st.md${TAB}pending" ] || fail "status: [$OUT]"
run status learnings/2026-11-07-st.md learnings/2026-11-07-plain.md
rc 0
[ "$OUT" = "2026-11-07-st.md${TAB}pending" ] || fail "status with names: [$OUT]"

case="f: status in force"
g checkout -q rel && g merge -q --no-edit "$BR" && g checkout -q work && g merge -q --no-edit rel
run status
rc 0
[ "$OUT" = "2026-11-07-st.md${TAB}in force" ] || fail "status: [$OUT]"

case="f: status closed"
g checkout -q rel
g rm -q "$PD/2026-11-07-st.md"
printf 'knowledge: refresh\n\nrejected: 2026-11-07-st.md %s duplicate of rule:x\n' "$EM" > "$WORK/msg"
g commit -q -F "$WORK/msg"
g checkout -q work && g merge -q --no-edit rel
run status
rc 0
[ "$OUT" = "2026-11-07-st.md${TAB}closed${TAB}rejected: 2026-11-07-st.md $EM duplicate of rule:x" ] || fail "status: [$OUT]"

case="f: status of a missing entry"
run status learnings/2026-11-07-gone.md
rc 1

# --- (g) the proposals budget in the drift report -------------------------------
case="g: the drift report"
new_fixture golf
g checkout -q rel
S="$(g rev-parse HEAD | tr -d '\r')"
printf 'commit=%s\ndate=2026-11-01\nbranch=rel\n' "$S" > "$P/$KD/BASELINE"
mkdir -p "$P/$PD"
for i in $(seq 1 41); do printf '## [2026-11-01] p%s\n' "$i" > "$P/$PD/p$i.md"; done
g add -A && g commit -q -m "baseline and 41 proposals"
OUT="$(cd "$P" && bash "$DRIFT" 2>&1)"
[ "$(printf '%s\n' "$OUT" | tail -n 1)" = "Proposals: 41 waiting, the budget is 40: a refresh is due." ] || fail "41: [$OUT]"
OUT="$(cd "$P" && bash "$DRIFT" --list 2>&1)"
printf '%s\n' "$OUT" | grep -qxF "proposals${TAB}41" || fail "41 --list: [$OUT]"
g rm -q "$PD/p41.md" && g commit -q -m "40"
OUT="$(cd "$P" && bash "$DRIFT" 2>&1)"
case "$OUT" in *Proposals:*) fail "40: [$OUT]";; esac
OUT="$(cd "$P" && bash "$DRIFT" --list 2>&1)"
printf '%s\n' "$OUT" | grep -qxF "proposals${TAB}40" || fail "40 --list: [$OUT]"

# --- (h) the inbox check --------------------------------------------------------
case="h: the inbox check on a submitted entry"
mkdir -p "$WORK/ops-h/learnings"
printf '## [2026-11-01] h\n- **Tags:** x\n[PROMOTE] PROJECT-RULES.md %s Always X\n[SUBMITTED 2026-11-02] knowledge/proposals-20261102-101010 as h.md\n' "$EM" > "$WORK/ops-h/learnings/h.md"
bash "$INBOXCHECK" "$WORK/ops-h" > "$WORK/h.out" 2>&1; RC=$?
OUT="$(cat "$WORK/h.out")"; ERR=""
rc 0
grep -qF "1 index rows" "$WORK/h.out" || fail "rows: $OUT"
grep -qF "0 pending marks" "$WORK/h.out" || fail "marks: $OUT"

# --- usage ------------------------------------------------------------------------
case="usage"
P="$WORK/alpha"
run bogus
rc 2

if [ "$FAILS" -gt 0 ]; then exit 1; fi
echo "proposals: ok"
