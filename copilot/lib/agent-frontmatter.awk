# Rewrites a Claude Code agent's frontmatter for GitHub Copilot: tools become
# the aliases both VS Code and the Copilot CLI accept, model: inherit and the
# experimental block go (an absent model already means inherit), and
# user-invocable: false keeps the role out of the agent picker while leaving it
# callable as a subagent. The body is untouched.
# Exit 2 = no frontmatter, 3 = no tools line, 4 = a tool with no alias.
BEGIN {
  alias["Read"] = "read"; alias["Grep"] = "search"; alias["Glob"] = "search"
  alias["Write"] = "edit"; alias["Edit"] = "edit"; alias["Bash"] = "execute"
  q = "\047"; rc = 0
}
{ sub(/\r$/, "") }
NR == 1 { if ($0 != "---") { rc = 2; exit rc } ; print; fm = 1; next }
fm && /^---[ \t]*$/ {
  if (!tools) { rc = 3; exit rc }
  print "user-invocable: false"; print; fm = 0; next
}
fm && /^tools:/ {
  n = split(substr($0, 7), part, ",")
  out = ""; split("", seen)
  for (i = 1; i <= n; i++) {
    t = part[i]; gsub(/^[ \t]+|[ \t]+$/, "", t)
    if (t == "") continue
    if (!(t in alias)) { print "unknown tool: " t > "/dev/stderr"; rc = 4; exit rc }
    a = alias[t]
    if (a in seen) continue
    seen[a] = 1; out = out (out == "" ? "" : ", ") q a q
  }
  print "tools: [" out "]"; tools = 1; next
}
fm && /^model:[ \t]*inherit[ \t]*$/ { next }
fm && /^experimental:/ { skip = 1; next }
fm && skip && /^[ \t]/ { next }
fm { skip = 0; print; next }
{ print }
END { if (!rc && fm) exit 2; exit rc }
