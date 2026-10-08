#!/usr/bin/env bash
# Tests tools/migrate-tracking.sh against throwaway projects: refusals, the
# move, the path rewrite and what it must never touch, knowledge backup,
# reruns, dry run, awkward paths. Also guards the source: the legacy name may
# survive only in the migration script, this test, and lines that say
# "legacy".
#
#   bash checks/verify-migrate-tracking.sh    (run from anywhere)
#
# Exit 0 = every case passed. 1 = a case failed; each failure is named.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/migrate-tracking.sh"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
status=0
fail() { echo "FAIL [$case]: $*" >&2; status=1; }

# A project with the team at .claude/, legacy run state, knowledge that
# names the legacy directory, and project files that do too.
make_project() {
  local p="$1" r="$1/.claude-tracking/bugfix_x_2026-10-01"
  mkdir -p "$p/.claude/tools" "$p/.claude/knowledge" "$r/plans" \
    "$p/.claude-tracking/knowledge-backup-2026-10-01-0900" "$p/docs"
  cp "$SCRIPT" "$p/.claude/tools/migrate-tracking.sh"
  cat > "$p/.claude/team-manifest.json" <<'EOF'
{
  "knowledge": {
    "dir": ".claude/knowledge",
    "budgets": {
      "dir": "not this one"
    }
  },
  "tracking": {
    "dir": ".dream-team-tracking",
    "legacyDir": ".claude-tracking",
    "migration": "tools/migrate-tracking.sh"
  }
}
EOF
  printf '# Status\n**Context:** `.claude-tracking/bugfix_x_2026-10-01/`\n' > "$r/status.md"
  printf 'see .claude-tracking/bugfix_x_2026-10-01/plans\r\nline two\r\n' > "$r/plans/crlf.md"
  printf '#!/usr/bin/env bash\ncat .claude-tracking/bugfix_x_2026-10-01/status.md\n' > "$r/run.sh"
  printf 'notes in .claude-tracking too\n' > "$r/my notes.md"
  printf 'no mention here\n' > "$r/plain.txt"
  touch -t 202001010000 "$r/plain.txt"
  printf 'bin\000.claude-tracking\000' > "$r/blob.bin"
  printf 'backup keeps .claude-tracking verbatim\n' > "$p/.claude-tracking/knowledge-backup-2026-10-01-0900/LEARNINGS.md"
  echo "jev=declined 2026-10-04" > "$p/.claude-tracking/.service-consent"
  printf 'Put long narratives into `.claude-tracking/{context_id}/status.md`.\n' > "$p/.claude/knowledge/LEARNINGS.md"
  printf 'no mention\n' > "$p/.claude/knowledge/PROJECT-OVERVIEW.md"
  printf '.claude-tracking/\n' > "$p/.gitignore"
  printf 'Runs live in .claude-tracking/.\n' > "$p/CLAUDE.md"
  printf 'See `.claude-tracking/` for runs.\n' > "$p/docs/x.md"
  (cd "$p" && git init -q)
}
# hash and path of every file outside .git, for byte-identity checks
snap() {
  (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s %s\n' "$(git hash-object --stdin < "$f")" "$f"; done)
}
run() { # project-dir [args]
  local p="$1"; shift
  (cd "$p" && bash .claude/tools/migrate-tracking.sh "$@") > "$tmp/out" 2> "$tmp/err"; rc=$?
}
has() { grep -qF -- "$2" "$1" || fail "$(basename "$1") lacks '$2': $(head -c 400 "$1")"; }

case=plain
P="$tmp/p1"; make_project "$P"; run "$P"
[ "$rc" = 0 ] || fail "exit $rc: $(cat "$tmp/err")"
[ ! -e "$P/.claude-tracking" ] || fail "legacy directory still there"
N="$P/.dream-team-tracking/bugfix_x_2026-10-01"
[ -f "$N/status.md" ] || fail "run not moved"
grep -qF '.dream-team-tracking/bugfix_x_2026-10-01/' "$N/status.md" || fail "status.md not rewritten"
[ "$(cat "$P/.dream-team-tracking/.service-consent")" = "jev=declined 2026-10-04" ] || fail "consent changed"
has "$tmp/out" "Migrated"
has "$tmp/out" "  bugfix_x_2026-10-01"
has "$tmp/out" "  .service-consent"

case=rewrite-scope
[ "$(tr -cd '\r' < "$N/plans/crlf.md" | wc -c | tr -d ' ')" = 2 ] || fail "CRLF not preserved"
grep -qF '.dream-team-tracking/' "$N/plans/crlf.md" || fail "crlf.md not rewritten"
grep -qF 'cat .dream-team-tracking/' "$N/run.sh" || fail "run.sh not rewritten"
[ "$(cat "$P/.dream-team-tracking/knowledge-backup-2026-10-01-0900/LEARNINGS.md")" = "backup keeps .claude-tracking verbatim" ] \
  || fail "a knowledge backup was rewritten"
printf 'bin\000.claude-tracking\000' > "$tmp/blob"; cmp -s "$tmp/blob" "$N/blob.bin" || fail "binary file changed"
[ -z "$(find "$N/plain.txt" -newermt 2021-01-01)" ] || fail "an unmentioning file was rewritten (mtime moved)"

case=spaces
grep -qF '.dream-team-tracking' "$N/my notes.md" || fail "file with a space not rewritten"

case=knowledge
grep -qF '`.dream-team-tracking/{context_id}' "$P/.claude/knowledge/LEARNINGS.md" || fail "knowledge not rewritten"
bk="$(ls -d "$P"/.dream-team-tracking/knowledge-backup-*-tracking 2>/dev/null | head -1)"
[ -n "$bk" ] && grep -qF '.claude-tracking' "$bk/LEARNINGS.md" || fail "no knowledge backup with the original text"
[ "$(cat "$P/.claude/knowledge/PROJECT-OVERVIEW.md")" = "no mention" ] || fail "an unmentioning knowledge file changed"
has "$tmp/out" "Knowledge backup:"

case=project-files
[ "$(cat "$P/.gitignore")" = ".claude-tracking/" ] || fail ".gitignore edited"
[ "$(cat "$P/CLAUDE.md")" = "Runs live in .claude-tracking/." ] || fail "CLAUDE.md edited"
has "$tmp/out" "Project files that still mention"
for f in .gitignore CLAUDE.md docs/x.md; do has "$tmp/out" "$f"; done
grep -qF '.claude/knowledge' "$tmp/out" && fail "the team's own directory is listed as a project file"

case=rerun
before="$(snap "$P")"; run "$P"
[ "$rc" = 0 ] || fail "second run exit $rc"
has "$tmp/out" "nothing to migrate"
[ "$before" = "$(snap "$P")" ] || fail "second run changed files"

case=merge
P="$tmp/p2"; make_project "$P"
mkdir -p "$P/.dream-team-tracking/analyze_y_2026-10-02"; echo "copilot run" > "$P/.dream-team-tracking/analyze_y_2026-10-02/status.md"
run "$P"
[ "$rc" = 0 ] || fail "exit $rc: $(cat "$tmp/err")"
[ -f "$P/.dream-team-tracking/analyze_y_2026-10-02/status.md" ] && [ -f "$P/.dream-team-tracking/bugfix_x_2026-10-01/status.md" ] \
  || fail "merge lost an entry"

case=conflict
P="$tmp/p3"; make_project "$P"
mkdir -p "$P/.dream-team-tracking"; echo "update-check=granted 2026-10-07" > "$P/.dream-team-tracking/.service-consent"
before="$(snap "$P")"; run "$P"
[ "$rc" = 1 ] || fail "expected exit 1, got $rc"
has "$tmp/err" "refused — these names exist in both"
has "$tmp/err" ".service-consent"
[ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"

case=open-run-legacy
P="$tmp/p4"; make_project "$P"
printf 'context_id=bugfix_x_2026-10-01\nworkflow=Bug Fix\n' > "$P/.claude-tracking/.team-mode"
before="$(snap "$P")"; run "$P"
[ "$rc" = 1 ] || fail "expected exit 1, got $rc"
has "$tmp/err" "refused — a run is open: bugfix_x_2026-10-01"
has "$tmp/err" "/team stop"
[ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"

case=open-run-new
P="$tmp/p5"; make_project "$P"
mkdir -p "$P/.dream-team-tracking"; printf 'context_id=analyze_z_2026-10-08\n' > "$P/.dream-team-tracking/.team-mode"
before="$(snap "$P")"; run "$P"
[ "$rc" = 1 ] || fail "expected exit 1, got $rc"
has "$tmp/err" "analyze_z_2026-10-08"
[ "$before" = "$(snap "$P")" ] || fail "a refused run changed files"

case=dry-run
P="$tmp/p6"; make_project "$P"
before="$(snap "$P")"; run "$P" --dry-run
[ "$rc" = 0 ] || fail "exit $rc"
has "$tmp/out" "bugfix_x_2026-10-01"
has "$tmp/out" "dry run; nothing was changed"
has "$tmp/out" "CLAUDE.md"
[ "$before" = "$(snap "$P")" ] || fail "dry run changed files"

case=half-moved
# What an interrupted run leaves: knowledge and the legacy tree already
# rewritten, one entry already moved, the legacy directory still present.
P="$tmp/p7"; make_project "$P"
(cd "$P" && grep -rlIF --exclude-dir='knowledge-backup-*' '.claude-tracking' .claude-tracking .claude/knowledge \
  | while IFS= read -r f; do sed 's/\.claude-tracking/.dream-team-tracking/g' "$f" > "$f.t" && cat "$f.t" > "$f" && rm "$f.t"; done)
mkdir -p "$P/.dream-team-tracking"; mv "$P/.claude-tracking/bugfix_x_2026-10-01" "$P/.dream-team-tracking/"
run "$P"
[ "$rc" = 0 ] || fail "exit $rc: $(cat "$tmp/err")"
[ ! -e "$P/.claude-tracking" ] || fail "legacy directory still there"
[ -f "$P/.dream-team-tracking/.service-consent" ] || fail "remaining entry not moved"
left="$(cd "$P/.dream-team-tracking" && grep -rlIF --exclude-dir='knowledge-backup-*' '.claude-tracking' . )"
[ -z "$left" ] || fail "legacy name left in: $left"

case=unicode-path
P="$tmp/Administración Test"; make_project "$P"; run "$P"
[ "$rc" = 0 ] || fail "exit $rc: $(cat "$tmp/err")"
[ ! -e "$P/.claude-tracking" ] && [ -f "$P/.dream-team-tracking/bugfix_x_2026-10-01/status.md" ] || fail "not migrated"

case=not-a-directory
P="$tmp/p8"; mkdir -p "$P/.claude/tools"; cp "$SCRIPT" "$P/.claude/tools/"; cp "$tmp/p1/.claude/team-manifest.json" "$P/.claude/"
echo x > "$P/.claude-tracking"; run "$P"
[ "$rc" = 2 ] || fail "expected exit 2 for a legacy file, got $rc"

case=bash3
if grep -nE '\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^)|declare -A|mapfile|readarray' "$SCRIPT"; then fail "bash-4-only construct"; fi

case=atomic-rewrite
# A failing rename of the temp file must leave every original untouched.
P="$tmp/p9"; make_project "$P"
mkdir -p "$tmp/stub"
cat > "$tmp/stub/mv" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in *.mt-tmp) exit 1 ;; esac; done
exec /usr/bin/env -i PATH="$REAL_PATH" mv "$@"
STUB
chmod +x "$tmp/stub/mv"
before="$(snap "$P")"
(cd "$P" && REAL_PATH="$PATH" PATH="$tmp/stub:$PATH" bash .claude/tools/migrate-tracking.sh) > "$tmp/out" 2> "$tmp/err"; rc=$?
[ "$rc" = 2 ] || fail "expected exit 2, got $rc"
after="$(snap "$P" | grep -v "knowledge-backup-.*-tracking/")"; [ "$before" = "$after" ] || fail "a failed rewrite changed or left files"
has "$tmp/err" "could not rewrite"

case=symlink
P="$tmp/p10"; make_project "$P"
mkdir -p "$tmp/outside"; echo "outside .claude-tracking" > "$tmp/outside/f.md"
rm -rf "$P/.claude-tracking"
if MSYS=winsymlinks:nativestrict ln -s "$tmp/outside" "$P/.claude-tracking" 2>/dev/null && [ -L "$P/.claude-tracking" ]; then
  run "$P"
  [ "$rc" = 2 ] || fail "expected exit 2 for a symlinked legacy directory, got $rc"
  has "$tmp/err" "symbolic link"
  [ "$(cat "$tmp/outside/f.md")" = "outside .claude-tracking" ] || fail "a file outside the project was rewritten"
else
  echo "skip [symlink] cannot create symlinks here"
fi

case=stale-temp
# What an interrupt between the temp copy and the rewrite leaves behind.
P="$tmp/p11"; make_project "$P"
cp -p "$P/.claude-tracking/bugfix_x_2026-10-01/status.md" "$P/.claude-tracking/bugfix_x_2026-10-01/status.md.mt-tmp"
cp -p "$P/.claude/knowledge/LEARNINGS.md" "$P/.claude/knowledge/LEARNINGS.md.mt-tmp"
run "$P"
[ "$rc" = 0 ] || fail "exit $rc: $(cat "$tmp/err")"
[ -z "$(find "$P" -name '*.mt-tmp' -print)" ] || fail "a temp file is left: $(find "$P" -name '*.mt-tmp')"
grep -qF '.dream-team-tracking/bugfix_x' "$P/.dream-team-tracking/bugfix_x_2026-10-01/status.md" || fail "original not rewritten"
grep -qF '`.dream-team-tracking/{context_id}' "$P/.claude/knowledge/LEARNINGS.md" || fail "knowledge not rewritten"

# @GUARD@  (Task 2 inserts the source guard here)

[ "$status" = 0 ] && echo "verify-migrate-tracking: all cases passed"
exit "$status"
