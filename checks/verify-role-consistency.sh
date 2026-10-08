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

# --- model routing: floors, matrix and agent files agree ---------------------
# The orchestrator computes every Agent call's model from this block: the
# cell for its workflow and call, one tier up for a hard run, then the role's
# floor and the session ceiling. A role without a floor, a workflow without a
# block or a misspelt tier silently changes the model a call gets, so each is
# refused here. The block must occur once; an ambiguous manifest is refused,
# as in verify-manifest-budgets.sh. Every value is taken raw, whatever it
# looks like, and must then be a quoted tier: a pattern that only matched
# well-formed values would skip "Opus", "sonnet-4" or a bare number.
mr_count="$(grep -c '"modelRouting"[[:space:]]*:' team-manifest.json)"
if [ "$mr_count" != 1 ]; then
  echo "FAIL: team-manifest.json has $mr_count modelRouting blocks, expected 1" >&2
  status=1
else
  mr_block="$(awk '/"modelRouting"[[:space:]]*:/{f=1} f{print} f && /^  }/{exit}' team-manifest.json | tr -d '\r')"
  mr_tiers="$(echo "$mr_block" | sed -n 's/.*"tiers"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p' \
    | grep -o '"[a-z]*"' | tr -d '"')"
  # "One tier up" for a hard run reads this list in order, so a reordered
  # list would move a hard run down.
  if [ -z "$mr_tiers" ]; then
    echo "FAIL: modelRouting.tiers is empty or unreadable" >&2; status=1
  elif [ "$(echo $mr_tiers)" != "haiku sonnet opus fable" ]; then
    echo "FAIL: modelRouting.tiers must be haiku, sonnet, opus, fable in that order (has: $(echo $mr_tiers))" >&2
    status=1
  fi

  # tier_of VALUE ALLOW_CEILING -> prints the bare tier, or nothing if VALUE is
  # not a quoted tier (or "ceiling" where that is allowed).
  tier_of() {
    local a
    a="$(echo "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*,\{0,1\}[[:space:]]*$//' | sed -n 's/^"\([a-z]*\)"$/\1/p')"
    [ -n "$a" ] || return 0
    if echo "$mr_tiers" | grep -qx "$a" || { [ "$2" = yes ] && [ "$a" = ceiling ]; }; then echo "$a"; fi
  }

  # floors: exactly one per role, each a tier, one role per line
  if echo "$mr_block" | grep -qE '^[[:space:]]*"floors"[[:space:]]*:[[:space:]]*\{[[:space:]]*[^[:space:]]'; then
    echo "FAIL: modelRouting.floors: open the object on its own line, one role per line" >&2
    status=1
  else
    mr_floors="$(echo "$mr_block" | awk '/"floors"[[:space:]]*:/{f=1; next} f && /}/{exit} f')"
    floor_roles="$(echo "$mr_floors" | sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*:.*/\1/p' | sort)"
    if [ "$floor_roles" != "$dir_roles" ]; then
      echo "FAIL: modelRouting.floors and agents/*.md disagree" >&2
      echo "  floors: $(echo "$floor_roles" | tr '\n' ' ')" >&2
      echo "  files:  $(echo "$dir_roles" | tr '\n' ' ')" >&2
      status=1
    fi
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      r="$(echo "$line" | sed -n 's/^[[:space:]]*"\([^"]*\)".*/\1/p')"
      v="$(echo "${line#*:}" | sed 's/^[[:space:]]*//; s/[[:space:]]*,\{0,1\}[[:space:]]*$//')"
      [ -n "$(tier_of "$v" no)" ] \
        || { echo "FAIL: modelRouting.floors.$r is not a tier: $v" >&2; status=1; }
    done <<< "$mr_floors"
  fi

  # workflows: one block per workflow in the enum, one call per line.
  # awk prints "workflow<TAB>call<TAB>raw value", or "!layout<TAB>line" for a
  # line that is not a call inside a workflow that opened on its own line.
  mr_calls="$(echo "$mr_block" | awk '
    /"workflows"[[:space:]]*:/ { f=1; next }
    !f { next }
    wf == "" && /^[[:space:]]*}/ { exit }
    wf == "" && /^[[:space:]]*"[^"]*"[[:space:]]*:[[:space:]]*\{[[:space:]]*$/ {
      wf = $0; sub(/^[[:space:]]*"/, "", wf); sub(/".*/, "", wf); print wf "\t\t"; next }
    wf != "" && /^[[:space:]]*},?[[:space:]]*$/ { wf = ""; next }
    wf != "" && /^[[:space:]]*"[^"]*"[[:space:]]*:/ {
      k = $0; sub(/^[[:space:]]*"/, "", k); sub(/".*/, "", k)
      v = $0; sub(/^[[:space:]]*"[^"]*"[[:space:]]*:/, "", v); print wf "\t" k "\t" v; next }
    /^[[:space:]]*$/ { next }
    { print "!layout\t" $0 }')"

  mr_wfs="$(echo "$mr_calls" | awk -F'\t' '$1 != "!layout" && $2 == "" {print $1}' | sort)"
  enum_wfs="$(norm "$wf_marker" | tr 'A-Z ' 'a-z_' | sort)"
  if [ "$mr_wfs" != "$enum_wfs" ]; then
    echo "FAIL: modelRouting.workflows and the workflow enum disagree" >&2
    echo "  routing: $(echo "$mr_wfs" | tr '\n' ' ')" >&2
    echo "  enum:    $(echo "$enum_wfs" | tr '\n' ' ')" >&2
    status=1
  fi
  dup="$(echo "$mr_calls" | awk -F'\t' '$1 != "!layout" && $2 != "" {print $1 "." $2}' | sort | uniq -d)"
  [ -z "$dup" ] || { echo "FAIL: modelRouting.workflows repeats a call: $(echo "$dup" | tr '\n' ' ')" >&2; status=1; }

  # Every call a workflow's section in skills/team/SKILL.md can make needs a
  # cell, or the orchestrator invents a tier on the spot and logs it as a
  # deviation (the audit found eight such runs). This table is the contract;
  # extend it when a workflow gains a call.
  required_cells="analyze:researcher-explorer
docs:doc-writer
bug_fix:researcher-explorer brainstorm developer tester reviewer
small_change:researcher-explorer brainstorm developer tester reviewer
change_set:researcher-explorer brainstorm developer doc-writer tester reviewer
full_feature:brainstorm researcher-explorer:wide researcher-explorer architect developer doc-writer tester reviewer reviewer:final"
  while IFS=: read -r wf cells; do
    for c in $cells; do
      echo "$mr_calls" | awk -F'\t' -v w="$wf" -v k="$c" '$1 == w && $2 == k {found=1} END {exit !found}' \
        || { echo "FAIL: modelRouting.workflows.$wf has no cell for $c, a call that workflow makes" >&2; status=1; }
    done
  done <<< "$required_cells"

  while IFS="$(printf '\t')" read -r wf call val; do
    [ -n "$wf" ] || continue
    if [ "$wf" = "!layout" ]; then
      echo "FAIL: modelRouting.workflows: a workflow opens on its own line and holds one call per line:$call" >&2
      status=1; continue
    fi
    [ -n "$call" ] || continue
    role="${call%%:*}"
    echo "$dir_roles" | grep -qx "$role" \
      || { echo "FAIL: modelRouting.workflows.$wf.$call names no role in agents/" >&2; status=1; }
    case "$call" in
      *:*) case "$call" in researcher-explorer:wide|reviewer:final) ;;
             *) echo "FAIL: modelRouting.workflows.$wf.$call: the only suffixes are researcher-explorer:wide and reviewer:final" >&2; status=1 ;;
           esac ;;
    esac
    case "$val" in
      *"{"*)
        case "$wf" in change_set|full_feature) ;;
          *) echo "FAIL: modelRouting.workflows.$wf.$call: low/medium/high only in change_set and full_feature" >&2; status=1 ;;
        esac
        inner="$(echo "$val" | sed 's/^[^{]*{//; s/}.*$//')"
        keys="$(echo "$inner" | tr ',' '\n' | sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*:.*/\1/p' \
          | sort | tr '\n' ' ')"
        [ "$keys" = "high low medium " ] \
          || { echo "FAIL: modelRouting.workflows.$wf.$call must map exactly low, medium, high (has: $keys)" >&2; status=1; }
        vals="$(echo "$inner" | tr ',' '\n' | sed 's/^[^:]*:[[:space:]]*//')" ;;
      *) vals="$val" ;;
    esac
    while IFS= read -r v; do
      v="$(echo "$v" | sed 's/^[[:space:]]*//; s/[[:space:]]*,\{0,1\}[[:space:]]*$//')"
      [ -n "$v" ] || continue
      [ -n "$(tier_of "$v" yes)" ] \
        || { echo "FAIL: modelRouting.workflows.$wf.$call uses unknown tier $v" >&2; status=1; }
    done <<< "$vals"
  done <<< "$mr_calls"
fi

# --- agent files: every role inherits the session model ----------------------
# A call that omits model must land exactly on the ceiling, so no agent file
# may pin a model of its own: a pin above the session model would exceed it.
for r in $dir_roles; do
  m="$(awk -F': ' '/^model: /{print $2; exit}' "agents/$r.md" | tr -d '\r')"
  [ "$m" = inherit ] || { echo "FAIL: agents/$r.md declares model: $m, expected inherit" >&2; status=1; }
done

[ "$status" -eq 0 ] && echo "role consistency: ok"
exit "$status"
