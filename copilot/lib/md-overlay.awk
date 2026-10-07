# Replaces one block of a Markdown file with the body of an overlay file.
#   -v anchor  the overlay's first line, exactly as the block starts in the source
#   -v ov      the overlay file; its lines 2..n replace the block
# Anchor kinds:
#   heading    "## Title"             the exact line; the block ends at the next
#                                     heading of the same or a higher level
#   list item  "5. **X.**", "   - **X.**"   a line starting with it; the block
#                                     ends at the next list item indented no
#                                     deeper, or at any heading
#   paragraph  anything else          a line starting with it; the block ends
#                                     at the next blank line
# Lines inside ``` fences never match and never end a block. Trailing blank
# lines of the overlay are dropped; a heading block is followed by one blank
# line before what comes next.
# Exit 10 = anchor not found, 11 = found more than once.
{ sub(/\r$/, ""); line[NR] = $0 }
END {
  if (anchor ~ /^#+ /) { kind = "h"; match(anchor, /^#+/); alevel = RLENGTH }
  else if (anchor ~ /^ *([0-9]+\.|-) /) { kind = "li"; match(anchor, /^ */); aindent = RLENGTH }
  else kind = "p"
  fence = 0; hits = 0
  for (i = 1; i <= NR; i++) {
    if (line[i] ~ /^ *```/) { fence = !fence; code[i] = 1; continue }
    code[i] = fence
    if (fence) continue
    if (kind == "h") { if (line[i] == anchor) { hits++; start = i } }
    else if (index(line[i], anchor) == 1) { hits++; start = i }
  }
  if (hits == 0) exit 10
  if (hits > 1) exit 11
  stop = NR + 1
  for (i = start + 1; i <= NR; i++) {
    if (code[i]) continue
    if (kind == "li" && line[i] ~ /^[ \t]*$/) {
      # A blank line ends the item when prose that is not a continuation
      # follows: the next non-blank line is no deeper than the anchor.
      for (j = i + 1; j <= NR && line[j] ~ /^[ \t]*$/; j++) ;
      if (j <= NR && !code[j]) {
        match(line[j], /^ */)
        if (RLENGTH <= aindent && line[j] !~ /^ *([0-9]+\.|-) / && line[j] !~ /^#+ /) { stop = i; break }
      }
      continue
    }
    if (kind == "p") { if (line[i] ~ /^[ \t]*$/) { stop = i; break } ; continue }
    if (match(line[i], /^#+ /)) {
      if (kind == "li" || RLENGTH - 1 <= alevel) { stop = i; break }
      continue
    }
    if (kind == "li" && line[i] ~ /^ *([0-9]+\.|-) /) {
      match(line[i], /^ */)
      if (RLENGTH <= aindent) { stop = i; break }
    }
  }
  # Blank lines at the end of a list item stay outside the block.
  if (kind == "li") while (stop - 1 > start && line[stop - 1] ~ /^[ \t]*$/) stop--
  n = 0
  while ((getline l < ov) > 0) { sub(/\r$/, "", l); rep[++n] = l }
  close(ov)
  while (n > 1 && rep[n] ~ /^[ \t]*$/) n--
  for (i = 1; i < start; i++) print line[i]
  for (i = 2; i <= n; i++) print rep[i]
  # A heading block owns its trailing blank lines (it runs up to the next
  # heading), so exactly one is put back before what follows.
  if (kind == "h" && stop <= NR) print ""
  for (i = stop; i <= NR; i++) print line[i]
}
