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
  # a topic an editor on Windows saved with CRLF
  put src/jobs/j.ts
  printf '%s\r\n' '# Jobs' 'Covers: src/jobs/**' '' 'Body.' > "$P/$KD/backend-architecture/jobs.md"
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

# --- a CRLF topic -------------------------------------------------------------
new_repo crlftopic; std
put src/jobs/j.ts "changed"; commit "jobs"
drift
has "crlf topic" "- backend-architecture/jobs.md  (src/jobs/**: 1 files)"
case "$OUT" in *"$CR"*) fail "crlf topic: output holds a CR";; esac

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

# --- the project in a subdirectory of the repository -------------------------
# Covers: patterns and "not covered" groups are repository-root paths; a change
# under the project's knowledge dir is still no change.
new_repo mono
P="$WORK/mono/app"; mkdir -p "$P/$KD"
put src/a.ts; put src/b.ts
kfile PROJECT-OVERVIEW.md "app/src/**"
kfile TOOLCHAIN.md "app/package.json"; put package.json
kfile DI-AND-STARTUP.md "app/startup/**"; put startup/s.ts
P="$WORK/mono"; put lib/l.ts; commit "monorepo"
BASE_SHA="$(git -C "$P" rev-parse HEAD | tr -d '\r')"
printf '%s\n' "commit=$BASE_SHA" "date=2026-11-01" "branch=release/1.0" > "$P/app/$KD/BASELINE"
commit "knowledge refresh"
P="$WORK/mono/app"; kfile SEARCH-PLAYBOOK.md "app/docs/**"
P="$WORK/mono"; commit "knowledge edit"
P="$WORK/mono/app"; drift
rc0 "subdirectory, knowledge-only change"
first_is "subdirectory, knowledge-only change" "Knowledge baseline: ${BASE_SHA:0:7} (2026-11-01). Nothing changed since."
put src/a.ts "changed"; P="$WORK/mono"; put lib/m.ts; commit "code"
P="$WORK/mono/app"; drift
first_is "subdirectory, code change" "Knowledge baseline: ${BASE_SHA:0:7} (2026-11-01). Changed since: 2 files."
has "subdirectory, code change" "- PROJECT-OVERVIEW.md  (app/src/**: 1 files)"
has "subdirectory, code change" "Not covered by knowledge: lib/ (1 files)"

# --- a failed diff is never "Nothing changed since." -------------------------
# A git that fails every diff, ahead of the real one on PATH.
REALGIT="$(command -v git)"
mkdir -p "$WORK/stub"
printf '%s\n' '#!/usr/bin/env bash' 'for a in "$@"; do [ "$a" = diff ] && exit 128; done' "exec \"$REALGIT\" \"\$@\"" > "$WORK/stub/git"
chmod +x "$WORK/stub/git"
P="$WORK/knowledgeonly"
OUT="$(cd "$P" && PATH="$WORK/stub:$PATH" bash "$TOOL" 2>&1)"; RC=$?
rc0 "failed diff"
UNCOMPARED="cannot be compared with HEAD in this copy — the lag is unknown."
has "failed diff" "$UNCOMPARED"
hasnt "failed diff" "Nothing changed since"
OUT="$(cd "$P" && PATH="$WORK/stub:$PATH" bash "$TOOL" --list 2>&1)"; RC=$?
has "failed diff --list" "state${TAB}unresolved"

# --- a partial clone is never fetched into -----------------------------------
# The source: main holds the code and the knowledge, whose BASELINE names a
# commit of a branch the clone never fetches.
SRC="$WORK/partial-src"
new_repo partial-src
git -C "$P" symbolic-ref HEAD refs/heads/main
git -C "$P" config uploadpack.allowFilter true
git -C "$P" config uploadpack.allowAnySHA1InWant true
put src/a.ts; commit "code"
git -C "$P" checkout -q -b other; put src/other.ts; commit "other"
OTHER="$(git -C "$P" rev-parse HEAD | tr -d '\r')"
git -C "$P" checkout -q main
kfile PROJECT-OVERVIEW.md "src/**"
printf '%s\n' "commit=$OTHER" "date=2026-11-01" "branch=release/1.0" > "$P/$KD/BASELINE"
commit "knowledge"
SRCDIR="$(cd "$SRC" && { pwd -W 2>/dev/null || pwd; })"
case "$SRCDIR" in /*) SRCURL="file://$SRCDIR" ;; *) SRCURL="file:///$SRCDIR" ;; esac
if git -c protocol.file.allow=always clone -q --filter=blob:none --single-branch --branch main "$SRCURL" "$WORK/partial-blobless" 2>/dev/null \
   && [ "$(git -C "$WORK/partial-blobless" config --get remote.origin.promisor 2>/dev/null | tr -d '\r')" = true ]; then
  P="$WORK/partial-blobless"
  GIT_NO_LAZY_FETCH=1 git -C "$P" cat-file -e "$OTHER^{commit}" 2>/dev/null \
    && fail "partial clone: the fixture already holds the other branch's commit"
  drift
  rc0 "partial clone"
  first_is "partial clone" "Knowledge baseline: ${OTHER:0:7} (2026-11-01) is not in this copy — the lag is unknown."
  GIT_NO_LAZY_FETCH=1 git -C "$P" cat-file -e "$OTHER^{commit}" 2>/dev/null \
    && fail "partial clone: the tool fetched the baseline commit"

  # A treeless clone holds the baseline commit but not its tree: the diff fails.
  P="$SRC"
  git -C "$P" checkout -q other; put src/third.ts; commit "third"; git -C "$P" checkout -q main
  git -C "$P" merge -q --no-edit other >/dev/null 2>&1
  OLD="$(git -C "$P" rev-parse HEAD~1 | tr -d '\r')"
  printf '%s\n' "commit=$OLD" "date=2026-11-01" "branch=release/1.0" > "$P/$KD/BASELINE"
  put src/later.ts; commit "baseline and a change"
  if git -c protocol.file.allow=always clone -q --filter=tree:0 --single-branch --branch main "$SRCURL" "$WORK/partial-treeless" 2>/dev/null; then
    P="$WORK/partial-treeless"
    if GIT_NO_LAZY_FETCH=1 git -C "$P" cat-file -e "$OLD^{tree}" 2>/dev/null; then
      echo "skip [treeless clone] the clone already holds the baseline tree"
    else
      drift
      rc0 "treeless clone"
      has "treeless clone" "$UNCOMPARED"
      hasnt "treeless clone" "Nothing changed since"
      GIT_NO_LAZY_FETCH=1 git -C "$P" cat-file -e "$OLD^{tree}" 2>/dev/null \
        && fail "treeless clone: the tool fetched the baseline tree"
    fi
  else
    echo "skip [treeless clone] this git cannot make a tree:0 partial clone"
  fi
else
  echo "skip [partial clone] this git cannot make a blob:none partial clone"
fi

# --- the proposals budget -----------------------------------------------------
# More files under proposals/ than knowledge.budgets.proposalsMaxFiles: every
# output but none gains a last line; --list always ends with the count.
PMAX="$(tr -d '\r' < "$TEAM/team-manifest.json" | sed -n 's/^ *"proposalsMaxFiles": *\([0-9][0-9]*\).*/\1/p')"
[ -n "$PMAX" ] || fail "proposals: no proposalsMaxFiles in the manifest"
PLINE="Proposals: $((PMAX + 1)) waiting, the budget is $PMAX: a refresh is due."
proposals() { # <count>: exactly that many files under proposals/, committed
  rm -rf "$P/$KD/proposals"; mkdir -p "$P/$KD/proposals"
  local i
  for i in $(seq 1 "$1"); do printf '%s\n' "## [2026-11-01] p$i" > "$P/$KD/proposals/p$i.md"; done
  commit "$1 proposals"
}
last_is() { # <case> <exact last line>
  local l; l="$(printf '%s\n' "$OUT" | tail -n 1)"
  [ "$l" = "$2" ] || fail "$1: last line '$l', wanted '$2'"
}
new_repo propbudget; std
put src/billing/a.ts "changed"; commit "billing"
proposals $((PMAX + 1))
drift
rc0 "proposals over, listed"
first_is "proposals over, listed" "Knowledge baseline: ${BASE_SHA:0:7} (2026-11-01). Changed since: 1 files."
has "proposals over, listed" "- backend-architecture/logic.md  (src/billing/**: 1 files)"
last_is "proposals over, listed" "$PLINE"
drift --list
last_is "proposals over, --list" "proposals${TAB}$((PMAX + 1))"
hasnt "proposals over, --list" "Proposals:"
proposals "$PMAX"
drift
hasnt "proposals at the budget" "Proposals:"
drift --list
last_is "proposals at the budget, --list" "proposals${TAB}$PMAX"

new_repo propclean; std
proposals $((PMAX + 1))
drift
first_is "proposals over, clean" "Knowledge baseline: ${BASE_SHA:0:7} (2026-11-01). Nothing changed since."
last_is "proposals over, clean" "$PLINE"

new_repo propmissing; put src/a.ts; kfile PROJECT-OVERVIEW.md "src/**"; commit "k"
proposals $((PMAX + 1))
drift
first_is "proposals over, missing" "$MISSING"
last_is "proposals over, missing" "$PLINE"

new_repo propscaffold; put src/a.ts
printf '%s\n' '> SCAFFOLD — written on an empty project on 2026-11-01. Regenerate once code exists.' '# Overview' > "$P/$KD/PROJECT-OVERVIEW.md"
commit "scaffold"
proposals $((PMAX + 1))
drift
first_is "proposals over, scaffold" "$SCAFFOLD"
last_is "proposals over, scaffold" "$PLINE"

P="$WORK/plain"; drift
hasnt "proposals, none" "Proposals:"
drift --list
hasnt "proposals, none --list" "proposals${TAB}"

# --- arguments ----------------------------------------------------------------
P="$WORK/billing"; drift --bogus
[ "$RC" = 2 ] || fail "bad argument: exit $RC, wanted 2"
drift --list extra
[ "$RC" = 2 ] || fail "two arguments: exit $RC, wanted 2"

if [ "$FAILS" -gt 0 ]; then exit 1; fi
echo "knowledge drift: ok"
