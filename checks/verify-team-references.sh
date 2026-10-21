#!/usr/bin/env bash
# The orchestrator is split in two: skills/team/SKILL.md holds what every
# turn needs, and skills/team/references/ holds one file per workflow plus the
# shared mechanics a workflow step names. The split drifts silently: a
# workflow gains no file, a section creeps back into SKILL.md, a pointer names
# a file that was renamed, a file is left that nothing names, or the core and
# one workflow together outgrow what a turn should load. This exits 1 and
# names the failure.
#
#   verify-team-references.sh      (run from anywhere; it locates the team
#                                   root from its own path)
#
# Workflow keys come from the sticky marker block in SKILL.md, transformed as
# checks/verify-role-consistency.sh transforms them: lower case, spaces as
# underscores. Sizes are wc -c of the files as checked out.
set -uo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.." || exit 1

MAX_PER_TURN=38000
SKILL=skills/team/SKILL.md
REFS=skills/team/references
status=0
fail() { echo "FAIL: $*" >&2; status=1; }

# --- 1. the references directory exists -------------------------------------
if [ ! -d "$REFS" ]; then
  echo "FAIL: $REFS/ does not exist" >&2
  exit 1
fi
if [ ! -f "$SKILL" ]; then
  echo "FAIL: $SKILL not found" >&2
  exit 1
fi

# --- 2. one file per workflow -------------------------------------------------
wf_marker="$(tr -d '\r' < "$SKILL" | sed -n 's/^workflow={\(.*\)}.*/\1/p')"
keys="$(echo "$wf_marker" | tr '|' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | tr 'A-Z ' 'a-z_')"
if [ -z "$keys" ]; then
  fail "could not read the workflow enum from the marker block in $SKILL"
fi
workflow_files=""
for key in $keys; do
  found=0
  for f in "$REFS/$key.md" "$REFS/$key"-*.md; do
    [ -f "$f" ] || continue
    found=1
    workflow_files="$workflow_files $f"
  done
  [ "$found" = 1 ] || fail "no workflow file for $key: expected $REFS/$key.md or $REFS/$key-*.md"
done

# --- 3. no workflow section left in SKILL.md ----------------------------------
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  fail "$SKILL:$hit still holds a workflow section; it belongs in $REFS/"
done <<< "$(tr -d '\r' < "$SKILL" | grep -n '^## Workflow:')"

# --- 4. every named file exists; every file is named somewhere ------------------
for name in $(tr -d '\r' < "$SKILL" | grep -o 'references/[a-z_-]*\.md' | sed 's|^references/||' | sort -u); do
  [ -f "$REFS/$name" ] || fail "$SKILL names references/$name, which does not exist"
done
# A "Read first:" line in a reference names bare <name>.md files beside it.
for f in "$REFS"/*.md; do
  [ -f "$f" ] || continue
  for name in $(tr -d '\r' < "$f" | grep '^Read first:' | grep -o '[A-Za-z0-9_-]*\.md' | sort -u); do
    [ -f "$REFS/$name" ] || fail "$f names $name, which does not exist"
  done
done
for f in "$REFS"/*.md; do
  [ -f "$f" ] || continue
  name="${f##*/}"
  pat="(^|[^a-z_-])${name//./\\.}"
  reached=0
  if tr -d '\r' < "$SKILL" | grep -qE "$pat"; then
    reached=1
  else
    for other in "$REFS"/*.md; do
      [ "$other" = "$f" ] && continue
      if tr -d '\r' < "$other" | grep -qE "$pat"; then reached=1; break; fi
    done
  fi
  [ "$reached" = 1 ] || fail "$f is reachable from nowhere"
done

# --- 5. per-turn load: the core plus the largest workflow file ----------------
skill_size="$(wc -c < "$SKILL" | tr -d ' ')"
largest=""; largest_size=0
for f in $workflow_files; do
  s="$(wc -c < "$f" | tr -d ' ')"
  if [ "$s" -gt "$largest_size" ]; then largest="$f"; largest_size="$s"; fi
done
total=$(( skill_size + largest_size ))
if [ "$total" -gt "$MAX_PER_TURN" ]; then
  fail "per-turn load $total exceeds $MAX_PER_TURN ($SKILL $skill_size + $largest $largest_size)"
fi

[ "$status" = 0 ] && echo "team references: ok"
exit "$status"
