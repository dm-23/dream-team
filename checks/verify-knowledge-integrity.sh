#!/usr/bin/env bash
# Verifies that a /generate-knowledge fix run moved text without losing or
# altering it.
#
#   verify-knowledge-integrity.sh <backup-dir> <knowledge-dir>
#
# Check 1: every entry in the backup's LEARNINGS.md exists byte for byte as one
#          file under <knowledge-dir>/learnings/.
# Check 2: every content line in a split topic directory appears in the file that
#          directory was split from.
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

# --- Check 2: split topics introduce no content the original lacked ----------
for dir in "$current"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  [ "$name" = "learnings" ] && continue

  origin="$backup/$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]').md"
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

  if comm -23 "$tmp/topic-sorted" "$tmp/origin-sorted" | grep -q .; then
    echo "FAIL: $name/ contains lines absent from $origin:" >&2
    comm -23 "$tmp/topic-sorted" "$tmp/origin-sorted" | sed 's/^/    /' >&2
    status=1
  fi
done

[ $status -eq 0 ] && echo "knowledge integrity: ok"
exit $status
