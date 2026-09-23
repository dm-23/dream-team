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

# --- README: the roles table has one row per role ----------------------------
readme_rows="$(awk '/^\| Role \| Tools \|/{f=1; next} f && /^\|---/{next} f && /^\|/{c++} f && !/^\|/{exit} END{print c+0}' README.md)"
role_count="$(echo "$dir_roles" | grep -c .)"
if [ "$readme_rows" != "$role_count" ]; then
  echo "FAIL: README roles table has $readme_rows rows, agents/ has $role_count roles" >&2
  status=1
fi

[ "$status" -eq 0 ] && echo "role consistency: ok"
exit "$status"
