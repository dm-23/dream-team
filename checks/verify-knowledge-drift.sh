#!/usr/bin/env bash
# Repo-only test of tools/knowledge-drift.sh: every fixture is a fresh
# repository with committed knowledge, and the tool runs from its root the way
# a run does. Never touches the real profile: DREAM_TEAM_PROFILE points into
# the temporary directory.
#
#   verify-knowledge-drift.sh
#
# Exit 0 = every case behaved as expected. Exit 1 = a case failed.
set -uo pipefail
export LC_ALL=C

TEAM="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$TEAM/tools/knowledge-drift.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/knowledge-drift.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT
export DREAM_TEAM_PROFILE="$WORK/profile"
export GIT_AUTHOR_NAME=drift GIT_AUTHOR_EMAIL=drift@example.com
export GIT_COMMITTER_NAME=drift GIT_COMMITTER_EMAIL=drift@example.com
KD=.dream-team/knowledge
TAB="$(printf '\t')"
CR="$(printf '\r')"

FAILS=0
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

[ -f "$TOOL" ] || { echo "FAIL: $TOOL does not exist"; exit 1; }

P=""
new_repo() { # <name>: a fresh repository with an empty knowledge dir; sets P
  P="$WORK/$1"
  mkdir -p "$P/$KD"
  git -C "$P" init -q
  git -C "$P" config core.autocrlf false
}
commit() { git -C "$P" add -A && git -C "$P" commit -q -m "$1"; }
put() { # <path> [content]
  mkdir -p "$(dirname "$P/$1")"
  printf '%s\n' "${2:-x}" > "$P/$1"
}
kfile() { # <file relative to the knowledge dir> <covers value, or "" for no line>
  mkdir -p "$(dirname "$P/$KD/$1")"
  if [ -n "$2" ]; then
    printf '%s\n' "# ${1##*/}" "Covers: $2" "" "Body." > "$P/$KD/$1"
  else
    printf '%s\n' "# ${1##*/}" "" "Body." > "$P/$KD/$1"
  fi
}
base() { # records HEAD in BASELINE and commits it, as a refresh does
  BASE_SHA="$(git -C "$P" rev-parse HEAD | tr -d '\r')"
  printf '%s\n' "commit=$BASE_SHA" "date=2026-11-01" "branch=release/1.0" > "$P/$KD/BASELINE"
  commit "knowledge refresh"
}
OUT="" RC=0
drift() { OUT="$(cd "$P" && bash "$TOOL" "$@" 2>&1)"; RC=$?; }

has() { # <case> <fragment>
  case "$OUT" in *"$2"*) ;; *) fail "$1: output lacks '$2' ($OUT)";; esac
}
hasnt() {
  case "$OUT" in *"$2"*) fail "$1: output holds '$2' ($OUT)";; esac
}
first_is() { # <case> <exact first line>
  local l; l="$(printf '%s\n' "$OUT" | head -n 1)"
  [ "$l" = "$2" ] || fail "$1: first line '$l', wanted '$2'"
}
rc0() { [ "$RC" = 0 ] || fail "$1: exit $RC, wanted 0 ($OUT)"; }

# A standard knowledge set: six located topics, two convention files, one index.
std() {
  put README.md; put package.json; put src/billing/a.ts; put src/data/d.ts
  put docs/guide.md; put src/startup/s.ts
  kfile PROJECT-OVERVIEW.md "README.md"
  kfile BACKEND-ARCHITECTURE.md "topics"
  kfile backend-architecture/logic.md "src/billing/**"
  kfile backend-architecture/data.md "src/data/**, db/**"
  kfile TOOLCHAIN.md "package.json, tools/**"
  kfile SEARCH-PLAYBOOK.md "docs/**"
  kfile DI-AND-STARTUP.md "src/startup/**"
  kfile CODING-STANDARDS.md "conventions"
  kfile TESTING-CONVENTIONS.md "conventions"
  commit "code and knowledge"
  base
}

NONE='Knowledge baseline: none — the knowledge is not committed in this branch.'
SCAFFOLD='Knowledge baseline: scaffold knowledge — nothing in it is verified against code.'
MISSING='Knowledge baseline: missing — the lag is unknown until a refresh writes it.'

# --- the states before any comparison ----------------------------------------
mkdir -p "$WORK/plain/$KD"; printf '%s\n' '# A' > "$WORK/plain/$KD/PROJECT-OVERVIEW.md"
P="$WORK/plain"; drift
rc0 "not a repository"; first_is "not a repository" "$NONE"

new_repo untracked; put src/a.ts; commit "code"; kfile PROJECT-OVERVIEW.md "src/**"
drift
rc0 "knowledge untracked"; first_is "knowledge untracked" "$NONE"

new_repo scaffold; put src/a.ts
mkdir -p "$P/$KD"
printf '%s\n' '> SCAFFOLD — written on an empty project on 2026-11-01. Regenerate once code exists.' '# Overview' > "$P/$KD/PROJECT-OVERVIEW.md"
commit "scaffold"
drift
rc0 "scaffold"; first_is "scaffold" "$SCAFFOLD"

new_repo nobaseline; put src/a.ts; kfile PROJECT-OVERVIEW.md "src/**"; commit "k"
drift
rc0 "no BASELINE"; first_is "no BASELINE" "$MISSING"
printf '%s\n' 'commit=12345' 'date=2026-11-01' > "$P/$KD/BASELINE"; commit "bad baseline"
drift
first_is "BASELINE without a 40-hex commit" "$MISSING"

new_repo absent; put src/a.ts; kfile PROJECT-OVERVIEW.md "src/**"
printf '%s\n' 'commit=0123456789abcdef0123456789abcdef01234567' 'date=2026-10-30' 'branch=release/1.0' > "$P/$KD/BASELINE"
commit "k"
drift
rc0 "absent commit"
first_is "absent commit" 'Knowledge baseline: 0123456 (2026-10-30) is not in this copy — the lag is unknown.'
printf '%s\n' 'commit=0123456789abcdef0123456789abcdef01234567' > "$P/$KD/BASELINE"; commit "no date"
drift
first_is "absent commit, no date" 'Knowledge baseline: 0123456 (unknown) is not in this copy — the lag is unknown.'

# --- CRLF BASELINE, nothing changed -----------------------------------------
new_repo crlf; put src/a.ts; kfile PROJECT-OVERVIEW.md "src/**"; commit "k"
S="$(git -C "$P" rev-parse HEAD | tr -d '\r')"
printf 'commit=%s\r\ndate=2026-11-02\r\nbranch=release/2.0\r\n' "$S" > "$P/$KD/BASELINE"
commit "baseline"
drift
rc0 "crlf baseline"
first_is "crlf baseline" "Knowledge baseline: ${S:0:7} (2026-11-02). Nothing changed since."
case "$OUT" in *"$CR"*) fail "crlf baseline: output holds a CR";; esac
drift --list
has "crlf --list" "state${TAB}clean"
has "crlf --list" "branch${TAB}release/2.0"
case "$OUT" in *"$CR"*) fail "crlf --list: output holds a CR";; esac

# --- the billing fixture ----------------------------------------------------
new_repo billing; std
put src/billing/a.ts "changed"; put src/billing/b.ts; commit "billing"
drift
rc0 "billing"
first_is "billing" "Knowledge baseline: ${BASE_SHA:0:7} (2026-11-01). Changed since: 2 files."
has "billing" "Verify against the code before relying on:"
has "billing" "- backend-architecture/logic.md  (src/billing/**: 2 files)"
hasnt "billing" "Not covered by knowledge"
hasnt "billing" "TOOLCHAIN.md"
drift --list
rc0 "billing --list"
has "billing --list" "state${TAB}listed"
has "billing --list" "baseline${TAB}$BASE_SHA"
has "billing --list" "branch${TAB}release/1.0"
has "billing --list" "marked${TAB}backend-architecture/logic.md${TAB}2"
hasnt "billing --list" "Knowledge baseline"

# --- package.json -------------------------------------------------------------
new_repo toolchain; std
put package.json "changed"; commit "deps"
drift
has "package.json" "- TOOLCHAIN.md  (package.json: 1 files)"

# --- not covered --------------------------------------------------------------
new_repo uncovered; std
put src/notifications/a.ts; put src/notifications/b.ts; put src/notifications/c.ts; put NOTES.txt
commit "notifications"
drift
rc0 "not covered"
has "not covered" "Not covered by knowledge: NOTES.txt, src/notifications/ (3 files)"
drift --list
has "not covered --list" "uncovered${TAB}src/notifications/${TAB}3"
has "not covered --list" "uncovered${TAB}NOTES.txt${TAB}1"

# --- a change only under the knowledge dir -----------------------------------
new_repo knowledgeonly; std
kfile SEARCH-PLAYBOOK.md "docs/**, scripts/**"; commit "knowledge edit"
drift
first_is "knowledge-only change" "Knowledge baseline: ${BASE_SHA:0:7} (2026-11-01). Nothing changed since."

# --- conventions are never listed --------------------------------------------
new_repo conventions; std
for f in README.md package.json src/billing/a.ts src/data/d.ts docs/guide.md src/startup/s.ts; do put "$f" "changed"; done
put lib/new.ts; commit "everything"
drift
rc0 "whole tree"
hasnt "whole tree" "CODING-STANDARDS.md"
hasnt "whole tree" "TESTING-CONVENTIONS.md"
hasnt "whole tree" "BACKEND-ARCHITECTURE.md"
drift --list
has "whole tree --list" "state${TAB}over"
hasnt "whole tree --list" "CODING-STANDARDS.md"
hasnt "whole tree --list" "${TAB}BACKEND-ARCHITECTURE.md"

# --- four of ten located topics marked ---------------------------------------
new_repo share
for i in 1 2 3 4 5 6 7 8 9 10; do put "area$i/f.ts"; kfile "topic-$i.md" "area$i/**"; done
commit "areas"; base
for i in 1 2 3 4; do put "area$i/f.ts" "changed"; done; commit "four areas"
drift
rc0 "forty percent"
first_is "forty percent" "Knowledge baseline: ${BASE_SHA:0:7} (2026-11-01). 2 commits behind, 40% of the located topics changed: a refresh is due; verify every topic against the code."
# three of ten is 30%, under the budget: the block
new_repo share30
for i in 1 2 3 4 5 6 7 8 9 10; do put "area$i/f.ts"; kfile "topic-$i.md" "area$i/**"; done
commit "areas"; base
for i in 1 2 3; do put "area$i/f.ts" "changed"; done; commit "three areas"
drift
first_is "thirty percent" "Knowledge baseline: ${BASE_SHA:0:7} (2026-11-01). Changed since: 3 files."

# --- a located file without a Covers line ------------------------------------
new_repo nocovers; std
kfile FRONTEND-ARCHITECTURE.md ""
kfile frontend-architecture/pages.md ""
kfile REVIEW-CHECKLIST.md ""
commit "knowledge without Covers lines"
put src/notifications/a.ts; commit "code"
drift
rc0 "no Covers line"
has "no Covers line" "- FRONTEND-ARCHITECTURE.md  (no Covers line)"
has "no Covers line" "- frontend-architecture/pages.md  (no Covers line)"
hasnt "no Covers line" "REVIEW-CHECKLIST.md"

# --- a path with a space ------------------------------------------------------
new_repo space; std
put "src/billing/a b.ts"; put "my dir/x y.ts"; commit "spaces"
drift
rc0 "space"
first_is "space" "Knowledge baseline: ${BASE_SHA:0:7} (2026-11-01). Changed since: 2 files."
has "space" "- backend-architecture/logic.md  (src/billing/**: 1 files)"
has "space" "Not covered by knowledge: my dir/ (1 files)"

# --- the pattern that matched most -------------------------------------------
new_repo most; std
put db/a.sql; put db/b.sql; put src/data/d.ts "changed"; commit "data"
drift
has "most matches" "- backend-architecture/data.md  (db/**: 2 files)"

# --- the cut ------------------------------------------------------------------
new_repo cut
for i in $(seq 10 59); do put "area$i/f.ts"; kfile "topic-$i.md" "area$i/**"; done
commit "areas"; base
for i in $(seq 10 24); do put "area$i/f.ts" "changed"; done
for i in $(seq 10 23); do put "loose$i/f.ts"; done
commit "fifteen areas, fourteen loose"
drift
rc0 "cut"
n="$(printf '%s\n' "$OUT" | grep -c '^- topic-')"
[ "$n" = 12 ] || fail "cut: $n topic lines, wanted 12 ($OUT)"
has "cut" "- … and 3 more"
has "cut" "loose21/ (1 files), … and 2 more"
hasnt "cut" "loose22/"
drift --list
n="$(printf '%s\n' "$OUT" | grep -c "^marked${TAB}")"
[ "$n" = 15 ] || fail "cut --list: $n marked records, wanted 15"
n="$(printf '%s\n' "$OUT" | grep -c "^uncovered${TAB}")"
[ "$n" = 14 ] || fail "cut --list: $n uncovered records, wanted 14"

# --- the in-process matching agrees with git's glob pathspecs ----------------
new_repo glob
FILES='src/billing/x.ts
src/billing/deep/y.ts
src/a b/c d.ts
lib/billing/z.ts
root.ts
srcfile.ts
package.json
src/billing.ts
docs/a.b/c.md'
while IFS= read -r f; do put "$f"; done <<EOF
$FILES
EOF
PATTERNS='src/**
src
src/billing
src/billing/
src/*
src/billing/*
src/billing/*.ts
**/*.ts
*.ts
**.ts
src**
src/b**
s**/x.ts
src/**x.ts
src/**/y.ts
src/**/**/y.ts
*/billing/**
**/billing/*.ts
**/billing
src/[ab]*/**
src/[!b]*/**
src/bil?ing/**
src/billing.ts
docs/a.b/**
docs/a?b/**
package.json
SRC/**'
i=0
while IFS= read -r p; do i=$((i + 1)); kfile "g-$i.md" "$p"; done <<EOF
$PATTERNS
EOF
put keep.txt; commit "knowledge"; base
while IFS= read -r f; do put "$f" "changed"; done <<EOF
$FILES
EOF
commit "every file"
drift --list
LISTED="$OUT"
i=0
while IFS= read -r p; do
  i=$((i + 1))
  want="$(git -C "$P" diff --name-only -z "$BASE_SHA" HEAD -- ":(glob)$p" | tr -cd '\000' | wc -c | tr -d ' ')"
  got="$(printf '%s\n' "$LISTED" | awk -F'\t' -v f="g-$i.md" '$1 == "marked" && $2 == f { print $3 }')"
  [ -n "$got" ] || got=0
  [ "$got" = "$want" ] || fail "glob '$p': the tool counts $got, git counts $want"
done <<EOF
$PATTERNS
EOF

# --- arguments ----------------------------------------------------------------
P="$WORK/billing"; drift --bogus
[ "$RC" = 2 ] || fail "bad argument: exit $RC, wanted 2"
drift --list extra
[ "$RC" = 2 ] || fail "two arguments: exit $RC, wanted 2"

if [ "$FAILS" -gt 0 ]; then exit 1; fi
echo "knowledge drift: ok"
