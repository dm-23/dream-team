#!/usr/bin/env bash
# Every file the team ships is text an agent reads literally: a rule it must
# follow, a template it fills, a string the orchestrator copies verbatim into
# a run's own files. Three kinds of damage are invisible to every other check
# in this directory and to a reviewer skimming a diff. This exits 1 and names
# the file and line.
#
#   - Double-encoded UTF-8. An editing pass that encodes text which was
#     already UTF-8 turns every typographic mark into a run of Latin-1
#     letters: an em dash becomes three characters that render as mojibake.
#     The result is still valid UTF-8 and still Latin script, so neither the
#     stack-neutrality lint nor a search for non-Latin scripts sees anything.
#     This repository shipped exactly that defect once, in the one section an
#     orchestrator has to follow word for word.
#   - Invalid UTF-8. A truncated or half-converted write leaves bytes no
#     reader can decode, and what an agent then reads is anyone's guess.
#   - Invisible characters. A non-breaking space, a zero-width mark or a
#     stray byte-order mark reads as ordinary text to a human and silently
#     breaks every literal match against the line that carries it.
#
# The double-encoding test keys on C1 control characters (U+0080-U+009F),
# which no text legitimately contains and which every double-encoded
# typographic mark in this repository produces -- an em dash, an arrow, a
# multiplication sign and a middle dot all yield at least one. That is why
# this check needs no list of permitted characters and never has to be
# edited when a new mark comes into use.
#
#   verify-text-encoding.sh        (run from anywhere; it locates the team
#                                   root from its own path)
#
# Patterns are built with printf and matched under LC_ALL=C, so they are
# byte comparisons on every platform. This is the same fixed
# bash/awk/sed/grep toolchain the other checks here are limited to; iconv is
# the one addition, used only to ask whether a file decodes at all, and the
# check says so and continues when it is absent.
set -uo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.." || exit 1
status=0

# C1 controls: the fingerprint of text that was encoded twice.
c1="$(printf '\302[\200-\237]')"

# Characters that are there but cannot be seen: non-breaking space,
# zero-width space/non-joiner/joiner, and a byte-order mark anywhere.
# U+FE0F, the variation selector this repository uses after a warning sign,
# is deliberately not listed.
invisible="$(printf '\302\240|\342\200[\213-\215]|\357\273\277')"

have_iconv=1
command -v iconv >/dev/null 2>&1 || have_iconv=0

# What this checks is the content the team ships. Inside a repository that is
# the tracked files plus the ones not yet added, and never the ignored ones:
# a run's own tracking directory and any scratch a tool leaves behind hold
# copies of old text whose damage is history, not a defect to fix. Without
# git -- an export, an unpacked archive -- fall back to walking the tree.
list_files() {
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files --cached --others --exclude-standard
  else
    find . -name .git -prune -o -type f -print
  fi
}

checked=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # Skip anything holding a NUL byte: that is a binary file, and none of the
  # three questions below is meaningful for one.
  nul="$(head -c 8000 "$f" | tr -dc '\000' | wc -c)"
  [ "$nul" -eq 0 ] || continue
  checked=$((checked + 1))

  if [ "$have_iconv" -eq 1 ] && ! iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; then
    echo "FAIL: $f is not valid UTF-8" >&2
    status=1
  fi

  if grep -nE "$c1" "$f" >/dev/null 2>&1; then
    echo "FAIL: $f carries C1 control characters -- text encoded twice:" >&2
    grep -nE "$c1" "$f" | cut -c1-100 | sed 's/^/  /' >&2
    status=1
  fi

  if grep -nE "$invisible" "$f" >/dev/null 2>&1; then
    echo "FAIL: $f carries invisible characters (non-breaking space, zero-width mark or byte-order mark):" >&2
    grep -nE "$invisible" "$f" | cut -c1-100 | sed 's/^/  /' >&2
    status=1
  fi
done <<EOF
$(list_files)
EOF

if [ "$checked" -eq 0 ]; then
  echo "FAIL: no text files found to check" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  if [ "$have_iconv" -eq 0 ]; then
    echo "text encoding: ok ($checked files; iconv absent, so validity was not tested)"
  else
    echo "text encoding: ok ($checked files)"
  fi
fi
exit "$status"
