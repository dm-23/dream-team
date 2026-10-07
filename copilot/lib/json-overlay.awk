# Replaces or deletes one top-level key of team-manifest.json.
#   -v key  the key
#   -v ov   overlay file: the replacement lines ("  \"key\": ...", no trailing
#           comma), or the single word delete
# The manifest's layout is relied on: a top-level key starts at exactly two
# spaces of indent, and a multi-line value closes on a line holding only "  }"
# or "  ]", with an optional comma.
# Exit 10 = key absent, 11 = more than once, 12 = no closing line,
# 13 = delete of the last key (it would leave a trailing comma behind).
{ sub(/\r$/, ""); line[NR] = $0 }
END {
  hits = 0
  for (i = 1; i <= NR; i++) if (index(line[i], "  \"" key "\": ") == 1) { hits++; start = i }
  if (hits == 0) exit 10
  if (hits > 1) exit 11
  stop = start
  if (line[start] ~ /[[{][ \t]*$/) {
    stop = 0
    for (i = start + 1; i <= NR; i++) if (line[i] ~ /^  []}],?[ \t]*$/) { stop = i; break }
    if (!stop) exit 12
  }
  comma = (line[stop] ~ /,[ \t]*$/)
  n = 0
  while ((getline l < ov) > 0) { sub(/\r$/, "", l); if (l !~ /^[ \t]*$/) rep[++n] = l }
  close(ov)
  del = (n == 1 && rep[1] == "delete")
  if (del && !comma) exit 13
  for (i = 1; i < start; i++) print line[i]
  if (!del) {
    sub(/,[ \t]*$/, "", rep[n])
    for (i = 1; i <= n; i++) print rep[i] ((i == n && comma) ? "," : "")
  }
  for (i = stop + 1; i <= NR; i++) print line[i]
}
