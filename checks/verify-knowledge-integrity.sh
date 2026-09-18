#!/usr/bin/env bash
# Verifies that a /generate-knowledge fix run moved text without losing or
# altering it.
#
#   verify-knowledge-integrity.sh <backup-dir> <knowledge-dir>
#
# Check 1: every entry in the backup's LEARNINGS.md exists byte for byte as one
#          file under <knowledge-dir>/learnings/.
# Check 2: for a split ("subset"-classified) file, every content line of the
#          backup original appears somewhere in the union of its index file
#          and its topic directory (nothing lost), and every content line in
#          the topic directory appears in the backup original (nothing
#          fabricated). The index may legitimately carry descriptive lines
#          the original never had; only the topic-directory side is held to
#          that stricter no-new-content rule.
#
# Files classified "whole" in team-manifest.json are out of scope for both
# checks: fix changes such a file only under the separate rewrites class,
# which the operator consents to separately and which does not promise
# byte-for-byte preservation, so there is nothing this script can verify for
# them. Their names are still listed alongside a passing result so "ok" never
# implies more than it checked.
#
# Exit 0 = both guarantees held. Exit 1 = a guarantee was broken. Writes nothing.
set -uo pipefail
export LC_ALL=C

backup="${1:?usage: verify-knowledge-integrity.sh <backup-dir> <knowledge-dir>}"
current="${2:?usage: verify-knowledge-integrity.sh <backup-dir> <knowledge-dir>}"

# A missing backup or knowledge dir means nothing was actually compared. Fail
# loudly instead of silently reporting "ok" having verified nothing: the
# knowledge dir is not version controlled, so this script is the only
# evidence a fix run did not lose anything.
[ -d "$backup" ] || { echo "FAIL: backup dir not found: $backup" >&2; exit 1; }
[ -d "$current" ] || { echo "FAIL: knowledge dir not found: $current" >&2; exit 1; }

status=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Trailing whitespace and trailing blank lines are formatting, not content.
normalize() {
  sed 's/[[:space:]]*$//' "$1" \
    | awk '{ l[NR] = $0 } END { last = NR; while (last > 0 && l[last] == "") last--;
             for (i = 1; i <= last; i++) print l[i] }'
}

# --- Check 1: LEARNINGS entries survive byte for byte ------------------------
if [ -f "$backup/LEARNINGS.md" ] && [ -d "$current/learnings" ]; then
  # Split entries into files under a prefix that cannot collide with the
  # "old-hashes"/"new-hashes" accumulator files below: a plain "old-*" glob
  # would also match a file literally named "old-hashes" in the same
  # directory and fold its own growing content back into itself.
  awk -v out="$tmp" '
    /^## \[/ { n++; f = sprintf("%s/entry-%04d", out, n) }
    n > 0    { print > f }
  ' "$backup/LEARNINGS.md"

  : > "$tmp/old-hashes"
  for f in "$tmp"/entry-*; do
    [ -e "$f" ] || continue
    normalize "$f" | sha256sum | awk '{print $1}' >> "$tmp/old-hashes"
  done

  : > "$tmp/new-hashes"
  for f in "$current"/learnings/*.md; do
    [ -e "$f" ] || continue
    normalize "$f" | sha256sum | awk '{print $1}' >> "$tmp/new-hashes"
  done

  sort -o "$tmp/old-hashes" "$tmp/old-hashes"
  sort -o "$tmp/new-hashes" "$tmp/new-hashes"

  if ! diff -q "$tmp/old-hashes" "$tmp/new-hashes" >/dev/null 2>&1; then
    echo "FAIL: LEARNINGS entries are not byte-identical after the move" >&2
    echo "  entries in backup: $(wc -l < "$tmp/old-hashes")" >&2
    echo "  entry files now:   $(wc -l < "$tmp/new-hashes")" >&2
    comm -23 "$tmp/old-hashes" "$tmp/new-hashes" \
      | sed 's/^/  entry lost or altered, hash /' >&2
    status=1
  fi
fi

# --- Check 2: split files lose nothing and topics fabricate nothing ----------
# "$checked" collects the lowercase names of every topic directory Check 2
# looked at, so the closing summary can name which top-level knowledge files
# it never touched (the "whole"-classified ones).
checked=""

for dir in "$current"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  [ "$name" = "learnings" ] && continue
  checked="$checked $name"

  upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
  origin="$backup/$upper.md"
  index_file="$current/$upper.md"

  if [ ! -f "$origin" ]; then
    echo "FAIL: $name/ has no counterpart at $origin in the backup" >&2
    status=1
    continue
  fi

  : > "$tmp/topic-lines"
  for f in "$dir"*.md; do
    [ -e "$f" ] || continue
    normalize "$f" >> "$tmp/topic-lines"
  done
  grep -v '^$' "$tmp/topic-lines" | sort -u > "$tmp/topic-sorted"
  normalize "$origin" | grep -v '^$' | sort -u > "$tmp/origin-sorted"

  # Nothing fabricated: every topic line must trace back to the original.
  if comm -23 "$tmp/topic-sorted" "$tmp/origin-sorted" | grep -q .; then
    echo "FAIL: $name/ contains lines absent from $origin:" >&2
    comm -23 "$tmp/topic-sorted" "$tmp/origin-sorted" | sed 's/^/    /' >&2
    status=1
  fi

  # Nothing lost: every original line must reappear in the topic directory or
  # the index (the index may add its own descriptive lines; those are not
  # checked here, only that nothing from the original is missing from the
  # union). fix's moves class relocates text verbatim and never summarizes,
  # so this direction is safe to enforce as strictly as the other.
  if [ -f "$index_file" ]; then
    normalize "$index_file" | grep -v '^$' | sort -u > "$tmp/index-sorted"
  else
    : > "$tmp/index-sorted"
  fi
  sort -u "$tmp/topic-sorted" "$tmp/index-sorted" > "$tmp/covered-sorted"

  if comm -23 "$tmp/origin-sorted" "$tmp/covered-sorted" | grep -q .; then
    echo "FAIL: $origin has content missing from $name/ and $index_file:" >&2
    comm -23 "$tmp/origin-sorted" "$tmp/covered-sorted" | sed 's/^/    /' >&2
    status=1
  fi
done

# --- Report what "whole"-classified files were not checked -------------------
# A top-level .md file with no matching topic directory was left untouched by
# Check 2 by construction (there is nothing to iterate over for it), which is
# exactly the set of files this script cannot verify: those classified
# "whole" in team-manifest.json, whose changes fall under the separate
# rewrites class instead of the moves class this script checks.
uncovered=""
for f in "$current"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .md)"
  [ "$base" = "LEARNINGS" ] && continue
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  case " $checked " in
    *" $lower "*) ;;
    *) uncovered="$uncovered $base.md" ;;
  esac
done

if [ $status -eq 0 ]; then
  if [ -n "$uncovered" ]; then
    echo "knowledge integrity: ok (not checked, classified whole:$uncovered)"
  else
    echo "knowledge integrity: ok"
  fi
fi
exit $status
