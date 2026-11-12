#!/usr/bin/env bash
# Tests tools/remarks.sh against throwaway projects: accept copies a remark byte
# for byte into the remarks dir under a name carrying its content hash, is
# idempotent, refuses bad sources before writing anything, never stages; pending
# lists the files of a directory that are not accepted yet.
#
#   bash checks/verify-remarks.sh    (run from anywhere)
#
# Exit 0 = every case passed. 1 = a case failed; each failure is named.
# Repo-only: it never ships to the Copilot edition, so fixtures spell team
# paths literally.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
status=0
case=""
fail() { echo "FAIL [$case]: $*" >&2; status=1; }

[ -f "$ROOT/tools/remarks.sh" ] || { echo "FAIL: $ROOT/tools/remarks.sh is missing" >&2; exit 1; }

NEW=".dream-team/knowledge/proposals"
LEG=".dream-team-tracking/operative/proposals"

n=0
# make_project: a git repository with a copy of the team's tools and manifest
# under team/ (beside the repository, never inside it).
make_project() {
  n=$((n + 1))
  P="$tmp/p$n"
  mkdir -p "$P/team" "$P/proj"
  cp -r "$ROOT/tools" "$P/team/tools"
  cp "$ROOT/team-manifest.json" "$P/team/team-manifest.json"
  git init -q "$P/proj" || fail "git init"
  git -C "$P/proj" config user.email t@example.com
  git -C "$P/proj" config user.name t
}
# run <args...>: remarks.sh in the project; sets out, err and rc.
run() {
  out="$(cd "$P/proj" && bash "$P/team/tools/remarks.sh" "$@" 2>"$tmp/err")"; rc=$?
  out="$(printf '%s' "$out" | tr -d '\r')"
  err="$(tr -d '\r' < "$tmp/err")"
}
write_src() { # <path> <content>
  mkdir -p "$(dirname "$P/proj/$1")"
  printf '%s\n' "$2" > "$P/proj/$1"
}
hash6() { git hash-object --no-filters "$P/proj/$1" | cut -c1-6; }
count_files() { find "$P/proj/$1" -type f 2>/dev/null | wc -l | tr -d ' '; }

case="accept into a missing remarks dir"
make_project
write_src drafts/2026-11-12-utc-dates.md "Store dates as UTC."
h="$(hash6 drafts/2026-11-12-utc-dates.md)"
T="$NEW/2026-11-12-utc-dates-$h.md"
run accept drafts/2026-11-12-utc-dates.md
[ "$rc" -eq 0 ] || fail "exit $rc ($err)"
[ "$out" = "added: $T" ] || fail "got '$out', expected 'added: $T'"
cmp -s "$P/proj/drafts/2026-11-12-utc-dates.md" "$P/proj/$T" || fail "target differs from the source"

case="git sees an untracked file and nothing staged"
st="$(git -C "$P/proj" status --porcelain -- "$NEW" | tr -d '\r')"
case "$st" in "?? $NEW/"*) ;; *) fail "status: '$st'" ;; esac
[ -z "$(git -C "$P/proj" diff --cached --name-only)" ] || fail "something is staged"

case="the same source again"
run accept drafts/2026-11-12-utc-dates.md
[ "$rc" -eq 0 ] || fail "exit $rc ($err)"
[ "$out" = "already there: $T" ] || fail "got '$out'"
cmp -s "$P/proj/drafts/2026-11-12-utc-dates.md" "$P/proj/$T" || fail "target changed"
[ "$(count_files "$NEW")" = 1 ] || fail "expected one file in the remarks dir"

case="a CRLF source"
make_project
mkdir -p "$P/proj/drafts"
printf 'line one\r\nline two\r\n' > "$P/proj/drafts/crlf.md"
run accept drafts/crlf.md
[ "$rc" -eq 0 ] || fail "exit $rc ($err)"
f="${out#added: }"
cmp -s "$P/proj/drafts/crlf.md" "$P/proj/$f" || fail "target differs from the source"
od -c "$P/proj/$f" | grep -q '\\r  \\n' || fail "CRLF lost in the target"

case="same base name, different bytes"
make_project
write_src a/note.md "first"
write_src b/note.md "second"
run accept a/note.md b/note.md
[ "$rc" -eq 0 ] || fail "exit $rc ($err)"
l1="$(printf '%s\n' "$out" | sed -n 1p)"; l2="$(printf '%s\n' "$out" | sed -n 2p)"
case "$l1" in "added: "*) ;; *) fail "line 1: '$l1'" ;; esac
case "$l2" in "added: "*) ;; *) fail "line 2: '$l2'" ;; esac
[ "$l1" != "$l2" ] || fail "both got one name"
[ "$(count_files "$NEW")" = 2 ] || fail "expected two files"

case="a source already named with its own hash"
make_project
write_src x/idea.md "an idea"
run accept x/idea.md
f="${out#added: }"
base="${f##*/}"
write_src y/"$base" "an idea"
run accept y/"$base"
[ "$out" = "already there: $f" ] || fail "got '$out', expected 'already there: $f'"
[ "$(count_files "$NEW")" = 1 ] || fail "suffix doubled"

case="bad sources write nothing"
make_project
write_src good/ok.md "valid"
mkdir -p "$P/proj/dir.md"
write_src bad/file.txt "text"
write_src real.md "target of link"
MSYS=winsymlinks:nativestrict ln -s real.md "$P/proj/link.md" 2>/dev/null
for bad in dir.md bad/file.txt ../outside.md good/../good/ok.md missing.md link.md; do
  if [ "$bad" = link.md ] && [ ! -L "$P/proj/link.md" ]; then continue; fi
  run accept good/ok.md "$bad"
  [ "$rc" -eq 2 ] || fail "$bad: exit $rc, expected 2"
  case "$err" in "remarks: "*) ;; *) fail "$bad: stderr '$err'" ;; esac
  [ -e "$P/proj/$NEW" ] && fail "$bad: the valid source was written"
done

case="a name taken by other bytes"
make_project
write_src s/clash.md "mine"
run accept s/clash.md
f="${out#added: }"
printf 'other\n' > "$P/proj/$f"
run accept s/clash.md
[ "$rc" -eq 2 ] || fail "exit $rc, expected 2"
case "$err" in *"exists with other content"*) ;; *) fail "stderr '$err'" ;; esac

case="legacy fixture"
make_project
mkdir -p "$P/proj/.claude/knowledge"
echo x > "$P/proj/.claude/knowledge/PROJECT-OVERVIEW.md"
write_src d/leg.md "legacy"
run accept d/leg.md
[ "$rc" -eq 0 ] || fail "exit $rc ($err)"
case "$out" in "added: $LEG/leg-"*".md") ;; *) fail "got '$out'" ;; esac
[ -f "$P/proj/${out#added: }" ] || fail "target missing"

case="pending"
make_project
write_src in/one.md "1"
write_src in/two.md "2"
write_src in/three.md "3"
write_src in/skip.txt "ignored"
run accept in/two.md
run pending in
[ "$rc" -eq 0 ] || fail "exit $rc ($err)"
[ "$out" = "in/one.md
in/three.md" ] || fail "got '$out'"
rm -rf "$P/proj/$NEW"
run pending in
[ "$out" = "in/one.md
in/three.md
in/two.md" ] || fail "no remarks dir: got '$out'"
run pending nowhere
{ [ "$rc" -eq 0 ] && [ -z "$out" ]; } || fail "missing dir: rc $rc out '$out'"

case="pending reports a failure to hash"
mkdir -p "$tmp/failbin"
printf '#!/bin/sh\nexit 1\n' > "$tmp/failbin/git"
chmod +x "$tmp/failbin/git"
out="$(cd "$P/proj" && PATH="$tmp/failbin:$PATH" bash "$P/team/tools/remarks.sh" pending in 2>"$tmp/err")"; rc=$?
[ "$rc" -eq 2 ] || fail "exit $rc, expected 2"
case "$(cat "$tmp/err")" in "remarks: "*) ;; *) fail "stderr '$(cat "$tmp/err")'" ;; esac

case="no command and an unknown command"
make_project
run
[ "$rc" -eq 2 ] || fail "no command: exit $rc, expected 2"
[ -n "$err" ] || fail "no command: nothing on stderr"
run frobnicate
[ "$rc" -eq 2 ] || fail "unknown: exit $rc, expected 2"
[ -n "$err" ] || fail "unknown: nothing on stderr"

[ "$status" -eq 0 ] && echo "verify-remarks: ok"
exit "$status"
