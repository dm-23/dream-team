#!/usr/bin/env bash
# The team's roles and workflows are named in five places: the manifest's
# agents[], the agents/ directory, the handoff template's two enums, the
# status template's workflow enum, and the sticky marker block in the team
# command. They drift silently, because nothing reads two of them at once.
# This exits 1 and names the pair that disagrees.
#
#   verify-role-consistency.sh     (run from anywhere; it locates the team
#                                   root from its own path)
#
# The manifest is read structurally, never with a JSON parser, for the same
# reason checks/verify-manifest-budgets.sh gives: this is a fixed
# bash/awk/sed/grep toolchain check.
set -uo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.." || exit 1
status=0

# --- roles: manifest agents[] vs agents/*.md ---------------------------------
manifest_roles="$(sed -n '/"agents"[[:space:]]*:[[:space:]]*\[/,/\]/p' team-manifest.json \
  | grep -o '"[a-z][a-z-]*"' | tr -d '"' | grep -v '^agents$' | sort)"
dir_roles="$(ls agents/*.md 2>/dev/null | sed 's|agents/||; s|\.md$||' | sort)"

if [ -z "$manifest_roles" ]; then
  echo "FAIL: could not read agents[] from team-manifest.json" >&2
  status=1
elif [ "$manifest_roles" != "$dir_roles" ]; then
  echo "FAIL: team-manifest.json agents[] and agents/*.md disagree" >&2
  echo "  manifest: $(echo "$manifest_roles" | tr '\n' ' ')" >&2
  echo "  files:    $(echo "$dir_roles" | tr '\n' ' ')" >&2
  status=1
fi

# --- roles: each file's frontmatter name matches its filename ----------------
for r in $dir_roles; do
  n="$(awk -F': ' '/^name: /{print $2; exit}' "agents/$r.md" | tr -d '\r')"
  [ "$n" = "$r" ] || { echo "FAIL: agents/$r.md declares name: $n" >&2; status=1; }
done

# --- roles: the handoff role enum lists exactly those roles ------------------
handoff_roles="$(sed -n 's/^- role: {\(.*\)}.*/\1/p' templates/handoff.md \
  | tr '|' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | sort)"
if [ "$handoff_roles" != "$dir_roles" ]; then
  echo "FAIL: templates/handoff.md role enum and agents/*.md disagree" >&2
  echo "  enum:  $(echo "$handoff_roles" | tr '\n' ' ')" >&2
  echo "  files: $(echo "$dir_roles" | tr '\n' ' ')" >&2
  status=1
fi

# --- workflows: the three enums are the same list ----------------------------
wf_handoff="$(sed -n 's/^- workflow: {\(.*\)}.*/\1/p' templates/handoff.md)"
wf_status="$(sed -n 's/^\*\*Workflow:\*\* {\(.*\)}.*/\1/p' templates/status.md)"
wf_marker="$(sed -n 's/^workflow={\(.*\)}.*/\1/p' skills/team/SKILL.md)"

norm() { echo "$1" | tr '|' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | sort; }

for pair in "handoff:$wf_handoff" "status:$wf_status" "marker:$wf_marker"; do
  name="${pair%%:*}"; val="${pair#*:}"
  [ -n "$val" ] || { echo "FAIL: could not read the workflow enum ($name)" >&2; status=1; }
done

if [ -n "$wf_handoff" ] && [ -n "$wf_status" ] && [ -n "$wf_marker" ]; then
  if [ "$(norm "$wf_handoff")" != "$(norm "$wf_status")" ] \
  || [ "$(norm "$wf_handoff")" != "$(norm "$wf_marker")" ]; then
    echo "FAIL: the three workflow enums disagree" >&2
    echo "  handoff: $wf_handoff" >&2
    echo "  status:  $wf_status"  >&2
    echo "  marker:  $wf_marker"  >&2
    status=1
  fi
fi

# --- workflows: the decision-routing question set offers the same workflows --
# templates/jev/workflow.json asks the service to pick a workflow. Its option
# keys are the enum lowercased with spaces as underscores, plus "other".
qs=templates/jev/workflow.json
if [ ! -f "$qs" ]; then
  echo "FAIL: $qs not found" >&2; status=1
elif [ -n "$wf_marker" ]; then
  qs_keys="$(tr -d '\r' < "$qs" | awk '/"criteria"[[:space:]]*:/{f=1; next} f && /}/{exit} f' \
    | grep -o '^[[:space:]]*"[a-z_]*"' | tr -d ' "' | grep -v '^other$' | sort)"
  wf_keys="$(norm "$wf_marker" | tr 'A-Z ' 'a-z_' | sort)"
  if [ "$qs_keys" != "$wf_keys" ]; then
    echo "FAIL: $qs criteria and the workflow enum disagree" >&2
    echo "  question set: $(echo "$qs_keys" | tr '\n' ' ')" >&2
    echo "  enum:         $(echo "$wf_keys" | tr '\n' ' ')" >&2
    status=1
  fi
fi

# --- README: the roles table has one row per role ----------------------------
readme_rows="$(awk '/^\| Role \| Tools \|/{f=1; next} f && /^\|---/{next} f && /^\|/{c++} f && !/^\|/{exit} END{print c+0}' README.md)"
role_count="$(echo "$dir_roles" | grep -c .)"
if [ "$readme_rows" != "$role_count" ]; then
  echo "FAIL: README roles table has $readme_rows rows, agents/ has $role_count roles" >&2
  status=1
fi

# --- model routing: one row per role, every tier a known alias ----------------
# The orchestrator picks each Agent call's model from this table, so a role
# without a row silently runs on its file's default, and a misspelt alias
# fails the call at run time. The block must occur once; an ambiguous manifest
# is refused, as in verify-manifest-budgets.sh.
mr_count="$(grep -c '"modelRouting"[[:space:]]*:' team-manifest.json)"
if [ "$mr_count" != 1 ]; then
  echo "FAIL: team-manifest.json has $mr_count modelRouting blocks, expected 1" >&2
  status=1
else
  mr_block="$(awk '/"modelRouting"[[:space:]]*:/{f=1} f{print} f && /^  }/{exit}' team-manifest.json | tr -d '\r')"
  mr_aliases="$(echo "$mr_block" | sed -n 's/.*"aliases"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p' \
    | grep -o '"[a-z]*"' | tr -d '"' | sort)"
  mr_lines="$(echo "$mr_block" | grep -E '^[[:space:]]*"[a-z][a-z-]*"[[:space:]]*:[[:space:]]*[{"]' \
    | grep -v -E '^[[:space:]]*"(modelRouting|roles)"')"
  mr_roles="$(echo "$mr_lines" | sed 's/^[[:space:]]*"\([a-z-]*\)".*/\1/' | grep -v '^$' | sort)"

  [ -n "$mr_aliases" ] || { echo "FAIL: modelRouting.aliases is empty or unreadable" >&2; status=1; }
  if [ "$mr_roles" != "$dir_roles" ]; then
    echo "FAIL: modelRouting.roles and agents/*.md disagree" >&2
    echo "  routing: $(echo "$mr_roles" | tr '\n' ' ')" >&2
    echo "  files:   $(echo "$dir_roles" | tr '\n' ' ')" >&2
    status=1
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    r="$(echo "$line" | sed 's/^[[:space:]]*"\([a-z-]*\)".*/\1/')"
    rest="${line#*:}"
    # Every value is taken raw, whatever it looks like, and must then be a
    # quoted alias from the list: a pattern that only matched well-formed
    # values would skip "Opus", "sonnet-4" or a bare number without a word.
    case "$rest" in
      *"{"*)
        inner="$(echo "$rest" | sed 's/^[^{]*{//; s/}.*$//')"
        keys="$(echo "$inner" | tr ',' '\n' | sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*:.*/\1/p' \
          | sort | tr '\n' ' ')"
        [ "$keys" = "high low medium " ] \
          || { echo "FAIL: modelRouting.roles.$r must map exactly low, medium, high (has: $keys)" >&2; status=1; }
        vals="$(echo "$inner" | tr ',' '\n' | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//')" ;;
      *)
        vals="$(echo "$rest" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/,$//; s/[[:space:]]*$//')" ;;
    esac
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      a="$(echo "$v" | sed -n 's/^"\([a-z]*\)"$/\1/p')"
      [ -n "$a" ] && echo "$mr_aliases" | grep -qx "$a" \
        || { echo "FAIL: modelRouting.roles.$r uses unknown alias $v" >&2; status=1; }
    done <<< "$vals"
  done <<< "$mr_lines"
fi

[ "$status" -eq 0 ] && echo "role consistency: ok"
exit "$status"
