#!/usr/bin/env bash
# Exercises checks/verify-knowledge-scaffold.sh against scratch project
# directories, and a hand-built scaffold knowledge base against
# checks/verify-knowledge-integrity.sh.
#
#   verify-scaffold-check.sh     (run from anywhere; it locates the team root from its own path)
#
# Each case builds a throwaway project and asserts on the two lines the
# scaffold check prints and on its exit code. Exit 0 = every case passed,
# 1 = at least one failed; each failure names its case.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/checks/verify-knowledge-scaffold.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

BANNER='> SCAFFOLD — written on an empty project on 2026-10-28; nothing here is verified against code. Run /generate-knowledge when the code exists.'

fails=0
fail() { echo "FAIL [$1] $2" >&2; fails=$((fails + 1)); }

project() { local p="$TMP/$1"; mkdir -p "$p/.claude"; printf '%s' "$p"; }
scaffold() { mkdir -p "$1/.claude/knowledge"; printf '%s\n' "$BANNER" > "$1/.claude/knowledge/PROJECT-OVERVIEW.md"; }
generated() { mkdir -p "$1/.claude/knowledge"; printf '# X\n' > "$1/.claude/knowledge/PROJECT-OVERVIEW.md"; }

# run CASE PROJECT -> sets OUT and RC
run() { OUT="$(bash "$CHECK" "$2" "$2/.claude/knowledge" 2>/dev/null)"; RC=$?; }
expect() { # CASE RC LINE1 LINE2
  [ "$RC" = "$2" ] || fail "$1" "exit $RC, expected $2: $OUT"
  [ "$(printf '%s\n' "$OUT" | sed -n 1p)" = "$3" ] || fail "$1" "line 1: $(printf '%s\n' "$OUT" | sed -n 1p), expected: $3"
  [ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "$4" ] || fail "$1" "line 2: $(printf '%s\n' "$OUT" | sed -n 2p), expected: $4"
}

p="$(project empty-absent)"
run empty-absent "$p"; expect empty-absent 0 "project: empty" "knowledge: absent"

p="$(project empty-generated)"; generated "$p"
run empty-generated "$p"; expect empty-generated 0 "project: empty" "knowledge: generated"

p="$(project empty-scaffold)"; scaffold "$p"
run empty-scaffold "$p"; expect empty-scaffold 3 "project: empty" "knowledge: scaffold 2026-10-28"

p="$(project dots-only)"; scaffold "$p"; mkdir -p "$p/.git" "$p/.github/workflows" "$p/.vscode"; : > "$p/.gitignore"
run dots-only "$p"; expect dots-only 3 "project: empty" "knowledge: scaffold 2026-10-28"

p="$(project content-scaffold)"; scaffold "$p"; echo hi > "$p/app.txt"
run content-scaffold "$p"; expect content-scaffold 1 "project: has content" "knowledge: scaffold 2026-10-28"

p="$(project empty-dir-content)"; scaffold "$p"; mkdir "$p/src"
run empty-dir-content "$p"; expect empty-dir-content 1 "project: has content" "knowledge: scaffold 2026-10-28"

p="$(project content-generated)"; generated "$p"; echo hi > "$p/app.txt"
run content-generated "$p"; expect content-generated 0 "project: has content" "knowledge: generated"

p="$(project crlf-banner)"; scaffold "$p"; printf '%s\r\n# more\r\n' "$BANNER" > "$p/.claude/knowledge/PROJECT-OVERVIEW.md"
run crlf-banner "$p"; expect crlf-banner 3 "project: empty" "knowledge: scaffold 2026-10-28"

p="$(project bom-banner)"; scaffold "$p"; printf '\xEF\xBB\xBF%s\n' "$BANNER" > "$p/.claude/knowledge/PROJECT-OVERVIEW.md"
run bom-banner "$p"; expect bom-banner 3 "project: empty" "knowledge: scaffold 2026-10-28"

# Root documents a developer has before any code — a repository initialised on a
# hosting service, or /init — do not make the project non-empty.
p="$(project root-docs)"; scaffold "$p"; echo hi > "$p/README.md"; : > "$p/LICENSE"; echo x > "$p/CLAUDE.md"; echo y > "$p/AGENTS.md"
run root-docs "$p"; expect root-docs 3 "project: empty" "knowledge: scaffold 2026-10-28"
p="$(project root-docs-and-code)"; scaffold "$p"; echo hi > "$p/README.md"; mkdir "$p/src"
run root-docs-and-code "$p"; expect root-docs-and-code 1 "project: has content" "knowledge: scaffold 2026-10-28"
p="$(project readme-dir)"; scaffold "$p"; mkdir "$p/README.md"
run readme-dir "$p"; expect readme-dir 1 "project: has content" "knowledge: scaffold 2026-10-28"

# The date is reported only when it is one; a copied template or a hand-edited
# banner reports "unknown" and the byte after the prefix never leaks half-cut.
p="$(project literal-date)"; scaffold "$p"; printf '> SCAFFOLD — written on an empty project on YYYY-MM-DD; nothing here is verified against code.\n' > "$p/.claude/knowledge/PROJECT-OVERVIEW.md"
run literal-date "$p"; expect literal-date 3 "project: empty" "knowledge: scaffold unknown"
p="$(project odd-date)"; scaffold "$p"; printf '> SCAFFOLD — written on an empty project on 28 октября 2026; nothing here is verified against code.\n' > "$p/.claude/knowledge/PROJECT-OVERVIEW.md"
run odd-date "$p"; expect odd-date 3 "project: empty" "knowledge: scaffold unknown"

# Mixed state: one file regenerated from code, the others still scaffolds. Any
# bannered knowledge file makes the base a scaffold; the date comes from the
# first bannered file in name order when PROJECT-OVERVIEW.md has none.
p="$(project mixed)"; generated "$p"; printf '%s\n# Toolchain\n' "$BANNER" > "$p/.claude/knowledge/TOOLCHAIN.md"; mkdir "$p/src"
run mixed "$p"; expect mixed 1 "project: has content" "knowledge: scaffold 2026-10-28"
p="$(project mixed-topic-ignored)"; generated "$p"; mkdir -p "$p/.claude/knowledge/learnings"; printf '%s\n' "$BANNER" > "$p/.claude/knowledge/learnings/2026-10-01-x.md"
run mixed-topic-ignored "$p"; expect mixed-topic-ignored 0 "project: empty" "knowledge: generated"

run missing-project "$TMP/does-not-exist"
[ "$RC" = 2 ] || fail missing-project "exit $RC, expected 2: $OUT"

# A scaffold knowledge base, built by hand to the shape /generate-knowledge
# writes on an empty project, passes verify-knowledge-integrity.sh against a
# copy of itself, as a /generate-knowledge shape-work run would check it. The
# knowledge sits at .dream-team/knowledge and the team at .claude/, so the
# manifest is found beside the check, never beside the knowledge.
root="$TMP/integrity"; k="$root/.dream-team/knowledge"; mkdir -p "$k/learnings" "$root/.claude/checks"
cp "$ROOT/team-manifest.json" "$root/.claude/team-manifest.json"; cp "$ROOT/checks/verify-knowledge-integrity.sh" "$root/.claude/checks/"
for f in PROJECT-OVERVIEW TESTING-CONVENTIONS SEARCH-PLAYBOOK TOOLCHAIN REVIEW-CHECKLIST PROJECT-RULES; do
  printf '%s\n# %s\n\nnot yet known — empty project\n' "$BANNER" "$f" > "$k/$f.md"
done
for f in BACKEND-ARCHITECTURE FRONTEND-ARCHITECTURE DI-AND-STARTUP CODING-STANDARDS; do
  printf '%s\n# %s\n\n- Layout — not yet known\n' "$BANNER" "$f" > "$k/$f.md"
  mkdir -p "$k/$(printf '%s' "$f" | tr 'A-Z' 'a-z')"
done
printf '# Generic card\n\n- Follow the repository structure [declared]\n' > "$k/coding-standards/generic.md"
cp "$ROOT/templates/learnings.md" "$k/LEARNINGS.md"
cp -r "$k" "$root/backup"
OUT="$(cd "$root" && bash .claude/checks/verify-knowledge-integrity.sh backup .dream-team/knowledge 2>&1)"; RC=$?
[ "$RC" = 0 ] || fail integrity "integrity check exit $RC on a scaffold base: $OUT"

# The widened origin still catches a fabricated line: one the backup holds in
# neither its index nor its topic directory.
printf -- '- Invented after the backup\n' >> "$k/coding-standards/generic.md"
OUT="$(cd "$root" && bash .claude/checks/verify-knowledge-integrity.sh backup .dream-team/knowledge 2>&1)"; RC=$?
[ "$RC" = 1 ] || fail integrity-fabricated "expected exit 1 for a fabricated topic line, got $RC: $OUT"
case "$OUT" in *"Invented after the backup"*) ;; *) fail integrity-fabricated "the fabricated line is not named: $OUT" ;; esac

if [ "$fails" -eq 0 ]; then echo "verify-scaffold-check: all cases passed"; exit 0; fi
echo "verify-scaffold-check: $fails failure(s)" >&2; exit 1
