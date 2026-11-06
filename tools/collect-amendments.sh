#!/usr/bin/env bash
# Collects the team amendments of several projects into one report for the
# lead, who ports them into the team by hand.
#
#   collect-amendments.sh <project-dir>...
#
# Reads <project-dir>/.dream-team-tracking/team-amendments.md for each
# argument (the format is templates/team-amendments.md) and prints Markdown
# to stdout: one "## <Proposal file>" section per team file the proposals
# target, sorted, and under it one bullet per distinct Rule, with the Seen
# counts summed and the ids and projects that carry it. The Proposal and Why
# lines shown are the first entry's.
#
# Read-only: it never writes into a project. CRLF collectors read the same as
# LF ones. A project without a collector is named in a comment line.
# Exit 0 = report printed, 2 = no project given.
set -uo pipefail
export LC_ALL=C

if [ "$#" -eq 0 ]; then
  echo "usage: collect-amendments.sh <project-dir>..." >&2
  exit 2
fi

records=""
notes=""
for dir in "$@"; do
  name="$(basename "$dir")"
  file="$dir/.dream-team-tracking/team-amendments.md"
  if [ ! -f "$file" ]; then
    notes="${notes}<!-- ${name}: no collector -->"$'\n'
    continue
  fi
  # One record per entry: file<TAB>rule<TAB>seen<TAB>id<TAB>project<TAB>change<TAB>why
  records="${records}$(tr -d '\r' < "$file" | awk -v proj="$name" '
    function flush() {
      if (id != "" && rule != "") {
        if (seen == "") seen = 1
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", pfile, rule, seen, id, proj, change, why
      }
      id = ""; rule = ""; pfile = ""; change = ""; why = ""; seen = ""
    }
    function after(s, prefix) { return substr(s, length(prefix) + 1) }
    /^## / {
      flush()
      id = after($0, "## ")
      sep = index(id, " — ")
      if (sep > 0) id = substr(id, 1, sep - 1)
      next
    }
    /^- Rule: / { rule = after($0, "- Rule: "); next }
    /^- Why: / { why = after($0, "- Why: "); next }
    /^- Proposal: / {
      p = after($0, "- Proposal: ")
      sep = index(p, " — ")
      if (sep > 0) { pfile = substr(p, 1, sep - 1); change = substr(p, sep + length(" — ")) }
      else { pfile = p; change = "" }
      next
    }
    /^- Seen: / {
      s = after($0, "- Seen: ")
      if (match(s, /^[0-9]+/)) seen = substr(s, 1, RLENGTH)
      next
    }
    END { flush() }
  ')"$'\n'
done

echo "# Team amendment proposals"
echo
if [ -n "$notes" ]; then printf '%s' "$notes"; echo; fi

printf '%s' "$records" | grep -v '^$' | sort -t "$(printf '\t')" -k1,1 -k2,2 -s | awk -F'\t' '
  function emit() {
    if (key == "") return
    printf "- %s — seen %d — ids: %s — projects: %s\n", krule, ksum, kids, kprojs
    printf "  - Proposal: %s\n", kchange
    printf "  - Why: %s\n", kwhy
  }
  {
    if ($1 "\t" $2 != key) {
      emit()
      if ($1 != section) { if (section != "") print ""; print "## " $1; print ""; section = $1 }
      key = $1 "\t" $2; krule = $2; ksum = 0; kids = ""; kprojs = ""; kchange = $6; kwhy = $7
      delete seenproj
    }
    ksum += $3
    kids = (kids == "") ? $4 : kids ", " $4
    if (!($5 in seenproj)) { seenproj[$5] = 1; kprojs = (kprojs == "") ? $5 : kprojs ", " $5 }
  }
  END { emit() }
'
exit 0
