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
    "gitExclude": m["gitExclude"] == [".github/dream-team/knowledge/", ".dream-team-tracking/"],
    "hooks.config": m["hooks"]["config"] == ".github/hooks/dream-team.json",
    "hooks.marker": m["hooks"]["marker"] == ".dream-team-tracking/.team-mode",
    "plugins have both setups": all(p.get("installVscode") and p.get("installCli") for p in m["plugins"]),
    "lint regex kept": m["checks"]["stackNeutralityLint"].startswith(
        s["checks"]["stackNeutralityLint"].split('" agents/')[0]),
    "only runtime checks": not {"manifestBudgets", "roleConsistency", "textEncoding", "jevClient",
                                "updateCheckClient", "routingSummary"} & set(m["checks"]),
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
finish
# @CASES-INSTALL@  (Task 3 inserts install cases here)

[ "$fails" -eq 0 ] || { echo "$fails failure(s)" >&2; exit 1; }
echo "all copilot checks passed"
