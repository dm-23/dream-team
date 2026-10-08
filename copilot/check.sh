#!/usr/bin/env bash
# Tests the GitHub Copilot port: copilot/build.sh against fixture and real
# sources, and copilot/install.sh against throwaway projects.
#
#   bash copilot/check.sh        (from anywhere)
#
# Exit 0 = every case passed. 1 = at least one failed; each failure names its
# case. Structured assertions (YAML frontmatter, JSON fields) need a python
# with PyYAML; without one they are skipped with a warning, never passed.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/copilot/build.sh"
INSTALL="$ROOT/copilot/install.sh"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

fails=0
CASE=""
case_fails=0
start() { CASE="$1"; case_fails=$fails; }
finish() { [ "$fails" -ne "$case_fails" ] || echo "ok   [$CASE]"; }
fail() { echo "FAIL [$CASE] $*" >&2; fails=$((fails + 1)); }

PY=""
for p in python3 python py; do
  "$p" -c 'import yaml' >/dev/null 2>&1 && { PY="$p"; break; }
done
[ -n "$PY" ] || echo "warning: no python with PyYAML; structured assertions are skipped" >&2

run_build() { # out-dir source-root
  bash "$BUILD" "$1" "$2" > "$TMP/build.out" 2> "$TMP/build.err"; RC=$?
}
expect_build_fail() { # text the error output must contain
  [ "$RC" = 1 ] || fail "expected exit 1, got $RC"
  grep -qF -- "$1" "$TMP/build.err" || fail "error output lacks '$1': $(head -c 400 "$TMP/build.err")"
}

# --- fixture: a miniature team with every kind of input the engine handles --
make_fixture() {
  local s="$1"
  mkdir -p "$s/agents" "$s/skills/demo" "$s/templates" "$s/tools" "$s/checks" \
    "$s/copilot/overrides/skills/demo/SKILL.md" "$s/copilot/overrides/team-manifest.json" \
    "$s/copilot/files/dream-team/hooks"
  cat > "$s/agents/alpha.md" <<'EOF'
---
name: alpha
description: Test agent
tools: Read, Grep, Glob, Write, Edit, Bash
model: inherit
experimental:
  cacheTtl: 1h
---

Read `.claude/knowledge/X.md`.
EOF
  cat > "$s/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: Demo skill
---

Task: $ARGUMENTS

## Keep

kept. Ask via AskUserQuestion.

## Replace me

old text

```
## not a heading inside a fence
```

## After

1. **One.** first
   - **Sub.** nested
     - deeper
   - **Sub2.** second
2. **Two.** second item

Para start line
continues here

Tail.
EOF
  cat > "$s/team-manifest.json" <<'EOF'
{
  "team": {
    "name": "fixture",
    "version": "1.0.0"
  },
  "agents": [
    "alpha"
  ],
  "skills": [
    "demo"
  ],
  "modelRouting": {
    "tiers": ["haiku"]
  },
  "hooks": {
    "dir": ".claude/hooks"
  },
  "last": "x"
}
EOF
  echo "template" > "$s/templates/t.md"
  echo "#!/usr/bin/env bash" > "$s/tools/a.sh"
  for c in summarize-routing.sh verify-knowledge-integrity.sh verify-learnings-inbox.sh verify-role-consistency.sh; do
    echo "#!/usr/bin/env bash" > "$s/checks/$c"
  done
  echo "knowledge/" > "$s/.gitignore"
  echo "#!/usr/bin/env bash" > "$s/copilot/files/dream-team/hooks/h"
  printf '%s\t%s\t%s\n' '*' '.claude/' '.github/dream-team/' \
    'skills/demo/SKILL.md' 'Task: $ARGUMENTS' 'Task: the text the user typed after the command' \
    '*' 'AskUserQuestion' 'the question tool' > "$s/copilot/rules.tsv"
  printf '%s\n' '## Replace me' '## Replace me' '' 'new text' \
    > "$s/copilot/overrides/skills/demo/SKILL.md/replace-me.md"
  printf '%s\n' '   - **Sub.**' '   - **Sub.** replaced' \
    > "$s/copilot/overrides/skills/demo/SKILL.md/sub.md"
  printf '%s\n' 'Para start' 'New para.' \
    > "$s/copilot/overrides/skills/demo/SKILL.md/para.md"
  echo delete > "$s/copilot/overrides/team-manifest.json/modelRouting.json"
  printf '%s\n' '  "hooks": {' '    "dir": ".github/dream-team/hooks"' '  }' \
    > "$s/copilot/overrides/team-manifest.json/hooks.json"
}

FIX="$TMP/fixture"
make_fixture "$FIX"

start engine-build
run_build "$TMP/fx-out" "$FIX"
[ "$RC" = 0 ] || fail "build exited $RC: $(cat "$TMP/build.err")"
want="$TMP/want-files"
printf '%s\n' .github/agents/alpha.agent.md .github/dream-team/.gitignore \
  .github/dream-team/checks/summarize-routing.sh .github/dream-team/checks/verify-knowledge-integrity.sh \
  .github/dream-team/checks/verify-learnings-inbox.sh .github/dream-team/hooks/h \
  .github/dream-team/team-manifest.json .github/dream-team/templates/t.md \
  .github/dream-team/tools/a.sh .github/skills/demo/SKILL.md | sort > "$want"
(cd "$TMP/fx-out" 2>/dev/null && find . -type f | sed 's|^\./||' | sort) > "$TMP/got-files"
diff "$want" "$TMP/got-files" >/dev/null || fail "file set differs: $(diff "$want" "$TMP/got-files" | tr '\n' ' ')"
finish

start engine-agent-frontmatter
cat > "$TMP/want-agent" <<'EOF'
---
name: alpha
description: Test agent
tools: ['read', 'search', 'edit', 'execute']
user-invocable: false
---

Read `.github/dream-team/knowledge/X.md`.
EOF
diff "$TMP/want-agent" "$TMP/fx-out/.github/agents/alpha.agent.md" >/dev/null \
  || fail "agent differs: $(diff "$TMP/want-agent" "$TMP/fx-out/.github/agents/alpha.agent.md" | tr '\n' ' ')"
finish

start engine-overlays-rules-note
cat > "$TMP/want-skill" <<'EOF'
---
name: demo
description: Demo skill
---

The question tool is `vscode/askQuestions` in VS Code and `ask_user` in the Copilot CLI. The subagent tool is `runSubagent` in VS Code and `task` in the Copilot CLI.

Task: the text the user typed after the command

## Keep

kept. Ask via the question tool.

## Replace me

new text

## After

1. **One.** first
   - **Sub.** replaced
   - **Sub2.** second
2. **Two.** second item

New para.

Tail.
EOF
diff "$TMP/want-skill" "$TMP/fx-out/.github/skills/demo/SKILL.md" >/dev/null \
  || fail "skill differs: $(diff "$TMP/want-skill" "$TMP/fx-out/.github/skills/demo/SKILL.md" | tr '\n' ' ')"
finish

start engine-manifest
cat > "$TMP/want-manifest" <<'EOF'
{
  "team": {
    "name": "fixture",
    "version": "1.0.0"
  },
  "agents": [
    "alpha"
  ],
  "skills": [
    "demo"
  ],
  "hooks": {
    "dir": ".github/dream-team/hooks"
  },
  "last": "x"
}
EOF
diff "$TMP/want-manifest" "$TMP/fx-out/.github/dream-team/team-manifest.json" >/dev/null \
  || fail "manifest differs: $(diff "$TMP/want-manifest" "$TMP/fx-out/.github/dream-team/team-manifest.json" | tr '\n' ' ')"
finish

# Each failure case starts from a fresh copy of the fixture.
variant() { rm -rf "$TMP/v"; cp -r "$FIX" "$TMP/v"; rm -rf "$TMP/v-out"; }

start engine-rule-no-match
variant
printf '%s\t%s\t%s\n' 'skills/demo/SKILL.md' 'no such text' 'x' >> "$TMP/v/copilot/rules.tsv"
run_build "$TMP/v-out" "$TMP/v"
expect_build_fail "rules.tsv:4 matched nothing in skills/demo/SKILL.md"
[ ! -e "$TMP/v-out" ] || fail "a failed build left $TMP/v-out behind"
finish

start engine-anchor-missing
variant
printf '%s\n' '## Nope' '## Nope' > "$TMP/v/copilot/overrides/skills/demo/SKILL.md/nope.md"
run_build "$TMP/v-out" "$TMP/v"
expect_build_fail "overrides/skills/demo/SKILL.md/nope.md: anchor not found: ## Nope"
finish

start engine-anchor-twice
variant
printf '%s\n' '   - **Sub' '   - x' > "$TMP/v/copilot/overrides/skills/demo/SKILL.md/sub-any.md"
run_build "$TMP/v-out" "$TMP/v"
expect_build_fail "anchor found more than once:    - **Sub"
finish

start engine-key-missing
variant
printf '%s\n' '  "nokey": 1' > "$TMP/v/copilot/overrides/team-manifest.json/nokey.json"
run_build "$TMP/v-out" "$TMP/v"
expect_build_fail "overrides/team-manifest.json/nokey.json: key not found: nokey"
finish

start engine-unknown-tool
variant
sed -i 's/^tools: .*/tools: Read, WebFetch/' "$TMP/v/agents/alpha.md"
run_build "$TMP/v-out" "$TMP/v"
expect_build_fail "unknown tool: WebFetch"
finish

start engine-residual
variant
echo "Runs in Claude Code." >> "$TMP/v/templates/t.md"
run_build "$TMP/v-out" "$TMP/v"
expect_build_fail "residual Claude term in .github/dream-team/templates/t.md:2:"
printf '%s\t%s\n' '.github/dream-team/templates/t.md' 'Claude Code' > "$TMP/v/copilot/allow.tsv"
run_build "$TMP/v-out" "$TMP/v"
[ "$RC" = 0 ] || fail "allow.tsv did not let the line through: $(cat "$TMP/build.err")"
finish

start engine-crlf
variant
for f in "$TMP/v/copilot/rules.tsv" "$TMP/v/copilot/overrides/skills/demo/SKILL.md/"*.md "$TMP/v/skills/demo/SKILL.md"; do
  sed -i 's/$/\r/' "$f"
done
run_build "$TMP/v-out" "$TMP/v"
[ "$RC" = 0 ] || fail "CRLF inputs broke the build: $(cat "$TMP/build.err")"
if grep -rlq $'\r' "$TMP/v-out" 2>/dev/null; then fail "CR reached the output"; fi
diff "$TMP/want-skill" "$TMP/v-out/.github/skills/demo/SKILL.md" >/dev/null || fail "CRLF skill output differs"
finish

start engine-overlay-list-item-keeps-following-prose
variant
printf '%s\n' '2. **Two.**' '2. **Two.** replaced' > "$TMP/v/copilot/overrides/skills/demo/SKILL.md/two.md"
run_build "$TMP/v-out" "$TMP/v"
[ "$RC" = 0 ] || fail "build exited $RC: $(cat "$TMP/build.err")"
sed 's/^2\. \*\*Two\.\*\* second item$/2. **Two.** replaced/' "$TMP/want-skill" > "$TMP/want-skill-two"
diff "$TMP/want-skill-two" "$TMP/v-out/.github/skills/demo/SKILL.md" >/dev/null \
  || fail "last list item overlay ate following text: $(diff "$TMP/want-skill-two" "$TMP/v-out/.github/skills/demo/SKILL.md" | tr '\n' ' ')"
finish

REAL="$TMP/real-out"
start real-build
run_build "$REAL" "$ROOT"
[ "$RC" = 0 ] || fail "real build exited $RC: $(head -c 2000 "$TMP/build.err")"
(cd "$ROOT" && {
  for f in agents/*.md; do n="${f#agents/}"; echo ".github/agents/${n%.md}.agent.md"; done
  find skills -type f | sed 's|^|.github/|'
  find templates -type f | sed 's|^|.github/dream-team/|'
  for f in tools/*.sh; do echo ".github/dream-team/$f"; done
  for c in summarize-routing.sh verify-knowledge-integrity.sh verify-learnings-inbox.sh; do
    echo ".github/dream-team/checks/$c"
  done
  echo .github/dream-team/team-manifest.json
  echo .github/dream-team/.gitignore
  (cd copilot/files && find . -type f | sed 's|^\./|.github/|')
} | sort) > "$TMP/real-want"
(cd "$REAL" 2>/dev/null && find . -type f | sed 's|^\./||' | sort) > "$TMP/real-got"
diff "$TMP/real-want" "$TMP/real-got" >/dev/null \
  || fail "real file set differs: $(diff "$TMP/real-want" "$TMP/real-got" | tr '\n' ' ')"
finish

start real-structure
if [ -n "$PY" ]; then
  "$PY" - "$REAL" "$ROOT/team-manifest.json" <<'EOF' || fail "structure assertions failed"
import glob, json, os, sys, yaml
out, src_manifest = sys.argv[1], sys.argv[2]
bad = []
def front(path):
    text = open(path, encoding="utf-8").read()
    assert text.startswith("---\n"), path
    return yaml.safe_load(text.split("---\n", 2)[1])
for p in glob.glob(os.path.join(out, ".github/agents/*.agent.md")):
    fm = front(p)
    name = os.path.basename(p)[:-len(".agent.md")]
    if fm.get("name") != name: bad.append(f"{p}: name {fm.get('name')!r}")
    if not fm.get("description"): bad.append(f"{p}: no description")
    if fm.get("user-invocable") is not False: bad.append(f"{p}: user-invocable not false")
    if "model" in fm or "experimental" in fm: bad.append(f"{p}: model or experimental left")
    tools = fm.get("tools")
    if not isinstance(tools, list) or not tools or set(tools) - {"read", "search", "edit", "execute"}:
        bad.append(f"{p}: tools {tools!r}")
for p in glob.glob(os.path.join(out, ".github/skills/*/SKILL.md")):
    fm = front(p)
    if fm.get("name") != os.path.basename(os.path.dirname(p)): bad.append(f"{p}: name")
    if not fm.get("description"): bad.append(f"{p}: no description")
m = json.load(open(os.path.join(out, ".github/dream-team/team-manifest.json"), encoding="utf-8"))
s = json.load(open(src_manifest, encoding="utf-8"))
checks = {
    "modelRouting absent": "modelRouting" not in m,
    "version kept": m["team"]["version"] == s["team"]["version"],
    "agents kept": m["agents"] == s["agents"],
    "skills kept": m["skills"] == s["skills"],
    "knowledge.dir": m["knowledge"]["dir"] == ".github/dream-team/knowledge",
    "tracking.dir": m["tracking"]["dir"] == ".dream-team-tracking",
    "tracking.legacyDir": m["tracking"].get("legacyDir") == ".claude-tracking",
    "tracking.migration": m["tracking"].get("migration") == "tools/migrate-tracking.sh",
    "gitExclude": m["gitExclude"] == [".github/dream-team/knowledge/", ".dream-team-tracking/"],
    "hooks.config": m["hooks"]["config"] == ".github/hooks/dream-team.json",
    "hooks.marker": m["hooks"]["marker"] == ".dream-team-tracking/.team-mode",
    "plugins have both setups": all(p.get("installVscode") and p.get("installCli") for p in m["plugins"]),
    "lint regex kept": m["checks"]["stackNeutralityLint"].startswith(
        s["checks"]["stackNeutralityLint"].split('" agents/')[0]),
    "only runtime checks": not {"manifestBudgets", "roleConsistency", "textEncoding", "jevClient",
                                "updateCheckClient", "routingSummary", "copilotPort", "migrateTracking"} & set(m["checks"]),
}
bad += [k for k, ok in checks.items() if not ok]
hooks = json.load(open(os.path.join(out, ".github/hooks/dream-team.json"), encoding="utf-8"))
if hooks.get("version") != 1 or not hooks["hooks"].get("sessionStart"): bad.append("hook config shape")
print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
EOF
else
  echo "skip [$CASE] no python with PyYAML" >&2
fi
finish

start real-neutrality
if [ -n "$PY" ]; then
  lint="$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["checks"]["stackNeutralityLint"])' \
    "$REAL/.github/dream-team/team-manifest.json")"
  hits="$(cd "$REAL/.github/dream-team" && eval "$lint" 2>&1)"
  [ -z "$hits" ] || fail "neutrality lint hits in the built team: $hits"
else
  echo "skip [$CASE] no python" >&2
fi
finish

start copilot-migrate-script
MS="$REAL/.github/dream-team/tools/migrate-tracking.sh"
[ -f "$MS" ] || fail "migrate-tracking.sh not in the edition"
grep -qF "'^[.]claude/'" "$MS" && grep -qF "'^[.]github/dream-team/'" "$MS" \
  || fail "the edition's migration script lost an exclusion pattern"
finish

start real-drift
rm -rf "$TMP/doctored"; mkdir -p "$TMP/doctored"
(cd "$ROOT" && tar --exclude=./.git -cf - .) | (cd "$TMP/doctored" && tar -xf -)
sed -i 's/^## Model routing$/## Model selection/' "$TMP/doctored/skills/team/SKILL.md"
run_build "$TMP/doctored-out" "$TMP/doctored"
expect_build_fail "overrides/skills/team/SKILL.md/model-routing.md: anchor not found: ## Model routing"
finish

start real-hook
HOOK="$REAL/.github/dream-team/hooks/session-start"
hp="$TMP/hookproj"; mkdir -p "$hp"
out="$(cd "$hp" && bash "$HOOK" < /dev/null)"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] || fail "no marker: exit $rc, output '$out'"
mkdir -p "$hp/.dream-team-tracking"
printf 'context_id=bug_fix_x_2026-10-07\nworkflow=Bug Fix\nphase=3 "quoted" \\ back\n' > "$hp/.dream-team-tracking/.team-mode"
out="$(cd "$hp" && bash "$HOOK" < /dev/null)"
if [ -n "$PY" ]; then
  printf '%s' "$out" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
a = d["additionalContext"]; h = d["hookSpecificOutput"]
assert h["hookEventName"] == "SessionStart", h
assert h["additionalContext"] == a
assert "bug_fix_x_2026-10-07" in a and "TEAM-MODE-ACTIVE" in a and "\"quoted\"" in a
' || fail "hook output is not the expected JSON: $out"
else
  case "$out" in *bug_fix_x_2026-10-07*SessionStart*) ;; *) fail "hook output: $out" ;; esac
fi
mkdir -p "$hp/.claude-tracking"
out="$(cd "$hp" && bash "$HOOK" < /dev/null)"
case "$out" in *TEAM-LEGACY-STATE*TEAM-MODE-ACTIVE*) ;; *) fail "legacy dir present: expected legacy then active blocks: $out" ;; esac
rm -f "$hp/.dream-team-tracking/.team-mode"
out="$(cd "$hp" && bash "$HOOK" < /dev/null)"; rc=$?
[ "$rc" = 0 ] || fail "legacy dir, no marker: exit $rc"
case "$out" in *TEAM-LEGACY-STATE*) ;; *) fail "legacy dir, no marker: expected the legacy block: $out" ;; esac
case "$out" in *TEAM-MODE-ACTIVE*) fail "legacy dir, no marker: active block without a marker: $out" ;; esac
rm -rf "$hp/.claude-tracking"
finish
run_install() { bash "$INSTALL" "$@" > "$TMP/inst.out" 2> "$TMP/inst.err"; RC=$?; }
new_project() { local p="$TMP/$1"; mkdir -p "$p" && (cd "$p" && git init -q) && printf '%s' "$p"; }
team_state() { # every installed path: hash mtime path
  (cd "$1" && find .github -type f 2>/dev/null | sort | while IFS= read -r f; do
    printf '%s %s %s\n' "$(git hash-object -- "$f")" "$(stat -c %Y -- "$f")" "$f"; done)
}
SEEDED=".github/dream-team/knowledge/learnings/2026-01-01-trap.md .github/dream-team/knowledge/LEARNINGS.md
.github/dream-team/knowledge/CAPABILITIES.md .dream-team-tracking/.team-mode .dream-team-tracking/run_x/status.md
.dream-team-tracking/.service-consent .git/info/exclude .github/copilot-instructions.md .github/agents/other.agent.md
.vscode/settings.json"
seed_state() {
  local p="$1"
  mkdir -p "$p/.github/dream-team/knowledge/learnings" "$p/.dream-team-tracking/run_x" "$p/.github/agents" "$p/.vscode"
  echo "entry" > "$p/.github/dream-team/knowledge/learnings/2026-01-01-trap.md"
  echo "# Learnings" > "$p/.github/dream-team/knowledge/LEARNINGS.md"
  echo "caps" > "$p/.github/dream-team/knowledge/CAPABILITIES.md"
  echo "context_id=run_x" > "$p/.dream-team-tracking/.team-mode"
  echo "status" > "$p/.dream-team-tracking/run_x/status.md"
  echo "update-check=granted 2026-10-01" > "$p/.dream-team-tracking/.service-consent"
  echo ".github/dream-team/knowledge/" >> "$p/.git/info/exclude"
  echo "project instructions" > "$p/.github/copilot-instructions.md"
  printf -- '---\nname: other\ndescription: mine\n---\n' > "$p/.github/agents/other.agent.md"
  echo '{}' > "$p/.vscode/settings.json"
}
seeded_state() { local f; for f in $SEEDED; do printf '%s %s\n' "$(git hash-object -- "$1/$f")" "$f"; done; }
built_list() { (cd "$REAL" && find . -type f | sed 's|^\./||' | sort); }

start install-fresh
P="$(new_project fresh)"
run_install "$P"
[ "$RC" = 0 ] || fail "exit $RC: $(cat "$TMP/inst.err")"
built_list | while IFS= read -r f; do [ -f "$P/$f" ] || echo "$f"; done > "$TMP/missing"
[ ! -s "$TMP/missing" ] || fail "not installed: $(tr '\n' ' ' < "$TMP/missing")"
version="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$ROOT/team-manifest.json" | head -1)"
[ "$(head -1 "$P/.github/dream-team/.installed")" = "# dream-team $version" ] || fail "record header"
[ "$(($(wc -l < "$P/.github/dream-team/.installed") - 1))" = "$(built_list | wc -l)" ] || fail "record line count"
finish

start install-second-run
before="$(team_state "$P")"
run_install "$P"
[ "$RC" = 0 ] || fail "exit $RC: $(cat "$TMP/inst.err")"
grep -qE '^  add 0$' "$TMP/inst.out" && grep -qE '^  update 0$' "$TMP/inst.out" || fail "second run changed files: $(cat "$TMP/inst.out")"
[ "$before" = "$(team_state "$P")" ] || fail "a file's content or mtime changed on a no-op run"
finish

start install-state-untouched
P="$(new_project seeded)"
seed_state "$P"
before="$(seeded_state "$P")"
run_install "$P"
[ "$RC" = 0 ] || fail "exit $RC: $(cat "$TMP/inst.err")"
run_install "$P"
[ "$before" = "$(seeded_state "$P")" ] || fail "seeded state changed: $(diff <(echo "$before") <(seeded_state "$P") | tr '\n' ' ')"
grep -q '^\.github/dream-team/knowledge' "$P/.github/dream-team/.installed" && fail "record claims a knowledge file"
finish

start install-conflict
P="$(new_project conflict)"
mkdir -p "$P/.github/agents" && echo "mine" > "$P/.github/agents/developer.agent.md"
run_install "$P"
[ "$RC" = 1 ] || fail "expected exit 1, got $RC"
grep -qF '.github/agents/developer.agent.md' "$TMP/inst.err" || fail "conflict not named: $(cat "$TMP/inst.err")"
[ "$(cat "$P/.github/agents/developer.agent.md")" = mine ] || fail "foreign file changed"
[ ! -e "$P/.github/dream-team" ] || fail "something was written despite the conflict"
finish

start install-modified
P="$(new_project modified)"
run_install "$P"
echo "local edit" >> "$P/.github/agents/developer.agent.md"
run_install "$P"
[ "$RC" = 1 ] || fail "edited file did not stop the install (exit $RC)"
grep -qF 'edited by hand' "$TMP/inst.err" || fail "refusal message: $(cat "$TMP/inst.err")"
grep -q 'local edit' "$P/.github/agents/developer.agent.md" || fail "refused run changed the edited file"
ls -d "$P"/.dream-team-tracking/install-backup-* >/dev/null 2>&1 && fail "refused run wrote a backup"
run_install "$P" --force
[ "$RC" = 0 ] || fail "--force exit $RC: $(cat "$TMP/inst.err")"
cmp -s "$P/.github/agents/developer.agent.md" "$REAL/.github/agents/developer.agent.md" || fail "not replaced"
bk="$(ls -d "$P"/.dream-team-tracking/install-backup-*/.github/agents/developer.agent.md 2>/dev/null | head -1)"
[ -n "$bk" ] && grep -q 'local edit' "$bk" || fail "no backup holding the edit"
finish

start install-crlf-clone
# A clone made with core.autocrlf=true checks the unpinned files out with CRLF; it is still an untouched install.
P="$(new_project crlf-src)"
run_install "$P"
[ "$RC" = 0 ] || fail "exit $RC: $(cat "$TMP/inst.err")"
(cd "$P" && git add -A && git -c user.name=t -c user.email=t@example.com commit -q -m install) >/dev/null 2>&1 || fail "could not commit the install"
rm -rf "$TMP/crlf-clone"
git -c core.autocrlf=true clone -q "$P" "$TMP/crlf-clone" >/dev/null 2>&1 || fail "could not clone"
if [ "$(tr -cd '\r' < "$TMP/crlf-clone/.github/agents/developer.agent.md" | wc -c)" -eq 0 ]; then
  fail "the clone has no CRLF files, so this case proves nothing (is core.autocrlf honoured?)"
else
  run_install "$TMP/crlf-clone"
  [ "$RC" = 0 ] || fail "untouched CRLF clone: exit $RC: $(cat "$TMP/inst.err")"
  grep -qE '^  modified 0$' "$TMP/inst.out" && grep -qE '^  update 0$' "$TMP/inst.out"     || fail "untouched CRLF clone not reported unchanged: $(cat "$TMP/inst.out")"
  echo "local edit" >> "$TMP/crlf-clone/.github/agents/developer.agent.md"
  run_install "$TMP/crlf-clone"
  [ "$RC" = 1 ] && grep -qF 'edited by hand' "$TMP/inst.err" || fail "a real edit in the clone was not caught (exit $RC)"
fi
finish

start install-remove
rec="$P/.github/dream-team/.installed"
echo "old" > "$P/.github/dream-team/templates/obsolete.md"
echo "old2" > "$P/.github/dream-team/templates/obsolete2.md"
printf '%s %s\n' "$(git hash-object "$P/.github/dream-team/templates/obsolete.md")" .github/dream-team/templates/obsolete.md \
  "$(git hash-object "$P/.github/dream-team/templates/obsolete2.md")" .github/dream-team/templates/obsolete2.md >> "$rec"
echo "edited" >> "$P/.github/dream-team/templates/obsolete2.md"
run_install "$P"
[ "$RC" = 0 ] || fail "exit $RC: $(cat "$TMP/inst.err")"
[ ! -e "$P/.github/dream-team/templates/obsolete.md" ] || fail "obsolete file kept"
[ -e "$P/.github/dream-team/templates/obsolete2.md" ] || fail "edited obsolete file deleted"
grep -qF 'orphan-modified .github/dream-team/templates/obsolete2.md' "$TMP/inst.out" || fail "orphan not reported"
finish

start install-dry-run
P="$(new_project dry)"
run_install "$P" --dry-run
[ "$RC" = 0 ] || fail "exit $RC"
[ ! -e "$P/.github" ] || fail "dry run wrote files"
grep -q '^add \.github/agents/developer\.agent\.md$' "$TMP/inst.out" || fail "plan not printed"
finish

start install-space-path
P="$(new_project "with space [x] 'q'")"
run_install "$P"
[ "$RC" = 0 ] && [ -f "$P/.github/skills/team/SKILL.md" ] || fail "path with a space: exit $RC $(cat "$TMP/inst.err")"
run_install "$P"
[ "$RC" = 0 ] && grep -qE '^  update 0$' "$TMP/inst.out" && grep -qE '^  modified 0$' "$TMP/inst.out" \
  || fail "rerun on a special-character path: exit $RC $(cat "$TMP/inst.out" "$TMP/inst.err")"
finish

start install-relative
P="$(new_project relative)"
(cd "$P" && bash "$INSTALL" . > "$TMP/inst.out" 2> "$TMP/inst.err"); RC=$?
[ "$RC" = 0 ] && [ -f "$P/.github/dream-team/.installed" ] || fail "install from inside with '.': exit $RC"
finish

start install-resume
rm -f "$P/.github/dream-team/.installed"
run_install "$P"
[ "$RC" = 0 ] || fail "interrupted install did not finish: $(cat "$TMP/inst.err")"
[ -f "$P/.github/dream-team/.installed" ] || fail "record not restored"
grep -qE '^  conflict 0$' "$TMP/inst.out" || fail "identical files were treated as foreign"
finish

start install-tampered-record
P="$(new_project tampered)"
seed_state "$P"
run_install "$P"
k="$P/.github/dream-team/knowledge/CAPABILITIES.md"
printf '%s %s\n' "$(git hash-object "$k")" .github/dream-team/knowledge/CAPABILITIES.md >> "$P/.github/dream-team/.installed"
run_install "$P"
[ "$RC" = 2 ] || fail "tampered record: expected exit 2, got $RC"
grep -qF "outside the team's paths" "$TMP/inst.err" || fail "message: $(cat "$TMP/inst.err")"
[ "$(cat "$k")" = caps ] || fail "knowledge file touched"
grep -v 'knowledge/CAPABILITIES' "$P/.github/dream-team/.installed" > "$TMP/rec.clean" && cp "$TMP/rec.clean" "$P/.github/dream-team/.installed"
printf '%s %s\n' "$(git hash-object "$k")" ".github/dream-team/templates/../knowledge/CAPABILITIES.md" >> "$P/.github/dream-team/.installed"
run_install "$P"
[ "$RC" = 2 ] || fail "dot-dot record path: expected exit 2, got $RC"
grep -qF "outside the team's paths" "$TMP/inst.err" || fail "dot-dot message: $(cat "$TMP/inst.err")"
[ "$(cat "$k")" = caps ] || fail "knowledge file deleted through a dot-dot path"
finish

start install-tampered-record-shapes
P="$(new_project shapes)"
seed_state "$P"
run_install "$P"
k="$P/.github/dream-team/knowledge/CAPABILITIES.md"
rec="$P/.github/dream-team/.installed"
cp "$rec" "$TMP/rec.orig"
bsl=$'\x5c'
for bad in ".github/dream-team/templates${bsl}..${bsl}knowledge${bsl}CAPABILITIES.md" \
  ".github/dream-team/..${bsl}..${bsl}.git${bsl}info${bsl}exclude" \
  ".github/dream-team/Knowledge/CAPABILITIES.md" ".github/dream-team/KNOWLEDGE/CAPABILITIES.md" \
  ".github/dream-team/KNOWLE~1/CAPABILITIES.md"; do
  cp "$TMP/rec.orig" "$rec"
  printf '%s %s\n' "$(git hash-object "$k")" "$bad" >> "$rec"
  run_install "$P"
  [ "$RC" = 2 ] || fail "$bad: expected exit 2, got $RC"
  grep -qF "outside the team's paths" "$TMP/inst.err" || fail "$bad: message: $(cat "$TMP/inst.err")"
  [ "$(cat "$k")" = caps ] || fail "$bad: knowledge file touched"
  [ -f "$P/.git/info/exclude" ] || fail "$bad: .git/info/exclude touched"
done
finish

start install-case-variants
P="$(new_project variants)"
run_install "$P"
rec="$P/.github/dream-team/.installed"
probe="$P/.github/dream-team/templates/probe.md"
echo probe > "$probe"
cp "$rec" "$TMP/rec.orig"
for bad in ".GITHUB/dream-team/templates/probe.md" ".github/Skills/team/probe.md"; do
  cp "$TMP/rec.orig" "$rec"
  printf '%s %s\n' "$(git hash-object "$probe")" "$bad" >> "$rec"
  run_install "$P"
  [ "$RC" = 2 ] || fail "$bad: expected exit 2, got $RC"
  grep -qF "outside the team's paths" "$TMP/inst.err" || fail "$bad: message: $(cat "$TMP/inst.err")"
  [ -f "$probe" ] || fail "$bad: probe file deleted"
done
cp "$TMP/rec.orig" "$rec"
printf '%s %s\n' "$(git hash-object "$P/.github/dream-team/team-manifest.json")" ".github/dream-team/Team-Manifest.json" >> "$rec"
run_install "$P"
[ "$RC" = 0 ] || fail "case variant of a built file: exit $RC: $(cat "$TMP/inst.err")"
[ -f "$P/.github/dream-team/team-manifest.json" ] || fail "a case variant of a built file removed it"
finish

start install-bash3-compatible
caret="$(printf '\x5e')"
if grep -nE '[$][{][A-Za-z_0-9]+(,,|'"$caret$caret"')|declare -A|mapfile|readarray' "$INSTALL" > "$TMP/bash4.hits"; then
  fail "bash-4-only construct in install.sh: $(cat "$TMP/bash4.hits")"
fi
finish

start install-remove-role
P="$(new_project oldrole)"
run_install "$P"
im="$P/.github/dream-team/team-manifest.json"
rec="$P/.github/dream-team/.installed"
awk '{ print } /^  "agents": \[/ { print "    \"old-role\"," }' "$im" > "$TMP/im.new" && cp "$TMP/im.new" "$im"
grep -v ' \.github/dream-team/team-manifest\.json$' "$rec" > "$TMP/rec.new"
printf '%s %s\n' "$(git hash-object "$im")" .github/dream-team/team-manifest.json >> "$TMP/rec.new"
echo "role" > "$P/.github/agents/old-role.agent.md"
printf '%s %s\n' "$(git hash-object "$P/.github/agents/old-role.agent.md")" .github/agents/old-role.agent.md >> "$TMP/rec.new"
cp "$TMP/rec.new" "$rec"
run_install "$P"
[ "$RC" = 0 ] || fail "exit $RC: $(cat "$TMP/inst.err")"
[ ! -e "$P/.github/agents/old-role.agent.md" ] || fail "dropped role kept"
grep -qF 'remove .github/agents/old-role.agent.md' "$TMP/inst.out" || fail "remove not planned: $(cat "$TMP/inst.out")"
cmp -s "$im" "$REAL/.github/dream-team/team-manifest.json" || fail "installed manifest not restored"
finish

[ "$fails" -eq 0 ] || { echo "$fails failure(s)" >&2; exit 1; }
echo "all copilot checks passed"
