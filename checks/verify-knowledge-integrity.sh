#!/usr/bin/env bash
# Verifies that a /generate-knowledge fix run moved text without losing or
# altering it.
#
#   verify-knowledge-integrity.sh <backup-dir> <knowledge-dir>
#
# The manifest is read at "$(dirname <knowledge-dir>)/team-manifest.json",
# the deployed layout (.claude/knowledge/ beside .claude/team-manifest.json).
# knowledge.classification is the source of truth for what every knowledge
# file's verdict should be; this script never guesses a file's classification
# from directory structure. Missing manifest or missing/empty classification
# is a hard failure, not a silent pass. The "classification" key is only
# read where it is nested under "knowledge", and the manifest is refused
# outright if it is ambiguous about either key (more than one "knowledge"
# block, or more than one "classification" block anywhere) -- guessing among
# candidates in the manifest itself would reintroduce the exact defect this
# script exists to catch in the knowledge directory.
#
# For every file in knowledge.classification (other than LEARNINGS.md, which
# Check 1 owns):
#   - "subset" with a topic directory present  -> Check 2, both directions:
#     nothing in the topic directory is absent from the backup original
#     (nothing fabricated), and nothing in the backup original is absent from
#     the union of the topic directory and its index file (nothing lost). The
#     index may legitimately carry descriptive lines the original never had;
#     only the topic-directory side is held to the no-new-content rule.
#   - "subset" with no topic directory present -> it was never split, so it
#     must still be byte-identical to its backup copy. A subset file that
#     fits its budget and stays one file is not thereby exempt: either it was
#     split (covered above) or fix never touched it, and a difference either
#     way is unexplained.
#   - "whole" -> out of scope. fix changes such a file only under the
#     separate rewrites class, which the operator consents to separately and
#     which does not promise byte-for-byte preservation, so there is nothing
#     this script can verify for it. Its name is still listed alongside a
#     passing result, sourced from the manifest, so "ok" never implies more
#     than it checked.
# A file or directory present under <knowledge-dir> but absent from
# knowledge.classification is not a silent pass either: it is reported as
# unclassified and fails the run. The one exception is the keys of
# knowledge.environment, which are files written by /team-setup to describe
# the machine rather than the repository. They are deliberately outside
# knowledge.required and therefore outside knowledge.classification, fix
# never touches them, and fix is forbidden from editing the manifest, so an
# operator could not exempt them by hand either. They are read from the
# manifest and exempted from the file sweep -- and from that sweep only:
# nothing else about them is assumed, and a *directory* by the same name is
# still unclassified.
#
# Check 1: the entries accumulated in the learnings log survive the run. The
#          invariant is a set equation rather than a presence test: the entries
#          in the backup -- inline in its LEARNINGS.md plus whatever files its
#          learnings/ already held -- must equal the entries in the knowledge
#          dir, again inline plus files. Stating it that way covers the run
#          that moved nothing (moves declined, rewrites accepted: entries stay
#          inline and learnings/ is never created), the run that moved
#          everything, the partly-applied run, and a second consecutive run
#          over an already-migrated base -- none of which a "learnings/ must
#          exist" guard could tell apart from the one case that matters, a run
#          that stripped the entries out of LEARNINGS.md and wrote them
#          nowhere. LEARNINGS.md is the only knowledge file with no
#          version-controlled copy anywhere, so that case must not reach
#          "ok".
#
# What "without losing or altering it" means per check, so the claim above is
# not read wider than the checks support. Check 1 compares whole entries by
# hash: byte for byte within an entry (after trailing-whitespace
# normalization), and a set across entries, so it does not police the order
# entries appear in. Check 2 compares sorted, deduplicated line sets: it proves
# that no line was lost and that none was invented, and it would pass text
# whose lines were reordered, or a line that occurred twice and now occurs
# once. Neither reordering nor de-duplication is a move fix performs, so the
# gap is between what the checks prove and what fix promises, not a licence.
#
# Exit 0 = every guarantee held. Exit 1 = a guarantee was broken, or the
# classification needed to check it could not be read. Writes nothing.
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

manifest="$(dirname "$current")/team-manifest.json"
[ -f "$manifest" ] || { echo "FAIL: manifest not found at $manifest (needed to read knowledge.classification)" >&2; exit 1; }

status=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Trailing whitespace and trailing blank lines are formatting, not content.
normalize() {
  sed 's/[[:space:]]*$//' "$1" \
    | awk '{ l[NR] = $0 } END { last = NR; while (last > 0 && l[last] == "") last--;
             for (i = 1; i <= last; i++) print l[i] }'
}

# --- Read knowledge.classification from the manifest --------------------------
# Extracted structurally (brace counting, then character-position slicing
# between quotes), not by any JSON parser: this is a fixed shell/awk/sed/grep
# toolchain check, so classification is read the same way Task 1's budgets
# check reads its own JSON blocks.
#
# A file-wide search for "classification" alone is not enough: nothing stops
# an unrelated top-level key from also having its own "classification" object,
# and a search that just takes the first (or last) match would silently pick
# among candidates -- the same defect this script exists to catch, one level
# up, in its own input. So the key is scoped ("classification" only counts if
# it is nested inside "knowledge") and, separately, refused outright if the
# manifest is ambiguous about it (more than one "classification" block
# anywhere, or more than one "knowledge" block). Scoping and ambiguity are
# both checked because scoping alone would still happily pick the one
# "classification" block that exists if it happened to sit outside
# "knowledge", and the ambiguity count alone would not know which of several
# candidates is the real one.

# Count occurrences of a JSON `"key": {` opening anywhere in a file's text.
count_key_blocks() {
  awk -v key="$1" '
    { n = gsub("\"" key "\"[[:space:]]*:[[:space:]]*\\{", "&"); total += n }
    END { print total + 0 }
  ' "$2"
}

# Extract the raw text strictly between a named key's opening { and its
# matching closing }, by brace depth. Callers must first confirm with
# count_key_blocks that exactly one such key exists in the input, or this
# takes the first match, same as any other single-pass scan would.
extract_key_block() {
  awk -v key="$1" '
    BEGIN { found = 0; level = 0 }
    !found && $0 ~ ("\"" key "\"[[:space:]]*:[[:space:]]*\\{") {
      found = 1; level = 1; next
    }
    found && level > 0 {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "{") level++
        else if (c == "}") { level--; if (level == 0) exit }
      }
      print
    }
  ' "$2"
}

knowledge_blocks="$(count_key_blocks knowledge "$manifest")"
if [ "$knowledge_blocks" -ne 1 ]; then
  echo "FAIL: $manifest defines $knowledge_blocks \"knowledge\" blocks, expected exactly 1" >&2
  exit 1
fi

classification_blocks_total="$(count_key_blocks classification "$manifest")"
if [ "$classification_blocks_total" -ne 1 ]; then
  echo "FAIL: $manifest defines $classification_blocks_total \"classification\" blocks; refusing to guess which one is knowledge.classification" >&2
  exit 1
fi

extract_key_block knowledge "$manifest" > "$tmp/knowledge-block"

classification_blocks_in_knowledge="$(count_key_blocks classification "$tmp/knowledge-block")"
if [ "$classification_blocks_in_knowledge" -ne 1 ]; then
  echo "FAIL: no classification block found nested under \"knowledge\" in $manifest" >&2
  exit 1
fi

extract_key_block classification "$tmp/knowledge-block" > "$tmp/classification-block"

awk '
  {
    line = $0
    if (line ~ /"[^"]+\.md"[[:space:]]*:[[:space:]]*"(subset|whole)"/) {
      s = line
      sub(/^[^"]*"/, "", s)
      n = index(s, "\"")
      fname = substr(s, 1, n - 1)
      s = substr(s, n + 1)
      sub(/^[^"]*"/, "", s)
      n = index(s, "\"")
      val = substr(s, 1, n - 1)
      print fname "\t" val
    }
  }
' "$tmp/classification-block" > "$tmp/classification"

if [ ! -s "$tmp/classification" ]; then
  echo "FAIL: no knowledge.classification entries found in $manifest" >&2
  exit 1
fi

# --- Read knowledge.environment's keys (files exempt from the file sweep) -----
# Same scoping discipline as classification: the key only counts nested under
# "knowledge", and an ambiguous manifest is refused rather than guessed at.
# Absent is not an error -- a manifest may declare no environment files -- but
# more than one block is, because there would be no way to know which is
# knowledge.environment.
: > "$tmp/environment-names"
environment_blocks="$(count_key_blocks environment "$tmp/knowledge-block")"
if [ "$environment_blocks" -gt 1 ]; then
  echo "FAIL: $manifest defines $environment_blocks \"environment\" blocks under \"knowledge\"; refusing to guess which one is knowledge.environment" >&2
  exit 1
fi
if [ "$environment_blocks" -eq 1 ]; then
  extract_key_block environment "$tmp/knowledge-block" > "$tmp/environment-block"
  # A key of the environment block is a file name opening an object; the
  # string-valued keys inside each object (writtenBy, template, note) cannot
  # match, because they are not followed by a brace.
  awk '
    /"[^"]+\.md"[[:space:]]*:[[:space:]]*\{/ {
      s = $0
      sub(/^[^"]*"/, "", s)
      n = index(s, "\"")
      print substr(s, 1, n - 1)
    }
  ' "$tmp/environment-block" > "$tmp/environment-names"
fi

# --- Check 1: the learnings entries survive the run --------------------------
# Splits a learnings log into one file per entry under <outdir>.
#
# Fence-aware, and that is the whole point of it. templates/learnings.md
# documents the entry format inside a fenced block whose first line is a
# literal "## [YYYY-MM-DD] {short-title}". Every deployed LEARNINGS.md carries
# that example, so a splitter that keyed on "^## \[" alone counted one entry
# more than exists and failed a *correct* migration -- and the acceptance
# reacts to a failure by restoring the backup, so the check would have
# destroyed what it exists to protect.
#
# Two ways to exclude the example were available. Anchoring extraction to the
# region after the template's "---" separator was rejected: it depends on one
# separator staying in place in every deployed copy of a file nothing
# version-controls, and an entry body is free to contain "---" of its own. A
# fence flag reads the example where it is, and it equally protects an entry
# that quotes a fenced example of its own -- the same reason the example needs
# protecting in the first place.
#
# But the flag is one piece of state spanning the whole file, not a local
# reading of the fences around the example, and an unbalanced fence therefore
# changes how every line below it is read. Both faces of that are serious. An
# odd number of column-0 fence markers above the first entry inverts the flag,
# so every entry is read as documentation, both files split into nothing, and
# a comparison of {} against {} reports ok over a total loss. An unterminated
# fence inside an entry body merges the entries below it and fails a correct
# migration with a byte mismatch, which the runbook answers by restoring the
# backup. So an unbalanced fence is a hard failure here, in either file, and
# is reported as what it is. Refusing is what makes the paragraph above true
# rather than assumed.
split_entries() {
  local src="$1" outdir="$2"
  mkdir -p "$outdir"
  awk -v out="$outdir" '
    /^```/                 { fence = !fence }
    !fence && /^## \[/     { n++; f = sprintf("%s/entry-%04d", out, n) }
    n > 0                  { print > f }
    END                    { if (fence) exit 2 }
  ' "$src"
  if [ $? -eq 2 ]; then
    echo "FAIL: $src ends inside a fenced block (an odd number of lines starting with three backticks)" >&2
    echo "  Which entries this file contains cannot be determined while that is true:" >&2
    echo "  everything below the unclosed fence reads as documentation rather than as" >&2
    echo "  entry text, so this check would compare the wrong text, or no text at all." >&2
    echo "  Balance the fences in that file and run this check again." >&2
    exit 1
  fi
}

# Hashes every entry file in <dir> onto the end of <accumulator>.
hash_entries() {
  local dir="$1" acc="$2" f
  for f in "$dir"/entry-*; do
    [ -e "$f" ] || continue
    normalize "$f" | sha256sum | awk '{print $1}' >> "$acc"
  done
}

# Hashes every *.md in <dir> onto the end of <accumulator>.
hash_entry_files() {
  local dir="$1" acc="$2" f
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    normalize "$f" | sha256sum | awk '{print $1}' >> "$acc"
  done
}

# Both sides are the union of what is inline and what is in learnings/. The
# entry files are split into their own subdirectories rather than into $tmp,
# so that the entry-* glob can never pick up one of the hash accumulators and
# fold it back into itself.
: > "$tmp/old-hashes"
: > "$tmp/new-hashes"

if [ -f "$backup/LEARNINGS.md" ]; then
  split_entries "$backup/LEARNINGS.md" "$tmp/backup-inline"
  hash_entries "$tmp/backup-inline" "$tmp/old-hashes"
fi
[ -d "$backup/learnings" ] && hash_entry_files "$backup/learnings" "$tmp/old-hashes"

if [ -f "$current/LEARNINGS.md" ]; then
  split_entries "$current/LEARNINGS.md" "$tmp/current-inline"
  hash_entries "$tmp/current-inline" "$tmp/new-hashes"
fi
[ -d "$current/learnings" ] && hash_entry_files "$current/learnings" "$tmp/new-hashes"

# Deduplicated, because two entries with identical text are indistinguishable
# by content and this check is about content surviving, not about how many
# copies of it exist.
sort -u -o "$tmp/old-hashes" "$tmp/old-hashes"
sort -u -o "$tmp/new-hashes" "$tmp/new-hashes"

if ! diff -q "$tmp/old-hashes" "$tmp/new-hashes" >/dev/null 2>&1; then
  echo "FAIL: the learnings entries in $current are not the entries in $backup" >&2
  echo "  distinct entries in backup: $(wc -l < "$tmp/old-hashes")" >&2
  echo "  distinct entries now:       $(wc -l < "$tmp/new-hashes")" >&2
  comm -23 "$tmp/old-hashes" "$tmp/new-hashes" \
    | sed 's/^/  entry lost or altered, hash /' >&2
  comm -13 "$tmp/old-hashes" "$tmp/new-hashes" \
    | sed 's/^/  entry present now but not in the backup, hash /' >&2
  status=1
fi

# --- Check 2: every classified file gets a verdict ----------------------------
# name here is the topic directory's basename (already lowercase); "$name/"
# in messages refers to <current>/<name>/.
check_split_dir() {
  local name="$1" origin="$2" index_file="$3" topic_dir="$4"

  if [ ! -f "$origin" ]; then
    echo "FAIL: $name/ has no counterpart at $origin in the backup" >&2
    status=1
    return
  fi

  : > "$tmp/topic-lines"
  for f in "$topic_dir"/*.md; do
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
}

# name here is the file's own basename (e.g. "BACKEND-ARCHITECTURE.md"),
# unsplit: it must still exist, unchanged, since fix never touched it.
check_unsplit_subset() {
  local cname="$1" origin="$2" index_file="$3"

  if [ ! -f "$origin" ]; then
    return # nothing in the backup to compare against; not this script's call
  fi
  if [ ! -f "$index_file" ]; then
    echo "FAIL: $cname is classified subset but is missing from the knowledge dir (backup had it at $origin)" >&2
    status=1
    return
  fi

  normalize "$origin" > "$tmp/unsplit-origin"
  normalize "$index_file" > "$tmp/unsplit-current"
  if ! diff -q "$tmp/unsplit-origin" "$tmp/unsplit-current" >/dev/null 2>&1; then
    echo "FAIL: $cname was not split and differs from its backup copy at $origin:" >&2
    diff "$tmp/unsplit-origin" "$tmp/unsplit-current" | sed 's/^/    /' >&2
    status=1
  fi
}

declared_whole=""
: > "$tmp/known-names"

while IFS="$(printf '\t')" read -r cname cvalue; do
  [ -n "$cname" ] || continue
  [ "$cname" = "LEARNINGS.md" ] && continue # LEARNINGS is entirely Check 1's

  base="${cname%.md}"
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  printf '%s\n' "$lower" >> "$tmp/known-names"

  origin="$backup/$cname"
  index_file="$current/$cname"
  topic_dir="$current/$lower"

  case "$cvalue" in
    whole)
      declared_whole="$declared_whole $cname"
      ;;
    subset)
      if [ -d "$topic_dir" ]; then
        check_split_dir "$lower" "$origin" "$index_file" "$topic_dir"
      else
        check_unsplit_subset "$cname" "$origin" "$index_file"
      fi
      ;;
    *)
      echo "FAIL: $cname has an unrecognized classification value '$cvalue' in $manifest" >&2
      status=1
      ;;
  esac
done < "$tmp/classification"

# --- Anything in the knowledge dir the manifest never classified fails too ----
for f in "$current"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .md)"
  [ "$base" = "LEARNINGS" ] && continue
  # Declared under knowledge.environment: describes the machine, written by
  # /team-setup on every run, never classified and never touched by fix.
  grep -qxF "$(basename "$f")" "$tmp/environment-names" && continue
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  if ! grep -qxF "$lower" "$tmp/known-names"; then
    echo "FAIL: $f is not classified in $manifest (knowledge.classification)" >&2
    status=1
  fi
done

for dir in "$current"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  [ "$name" = "learnings" ] && continue
  if ! grep -qxF "$name" "$tmp/known-names"; then
    echo "FAIL: $dir is not classified in $manifest (knowledge.classification)" >&2
    status=1
  fi
done

if [ $status -eq 0 ]; then
  if [ -n "$declared_whole" ]; then
    echo "knowledge integrity: ok (not checked, classified whole in $manifest:$declared_whole)"
  else
    echo "knowledge integrity: ok"
  fi
fi
exit $status
