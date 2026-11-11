# Rule file

A rule a person authored is one file, `<knowledge dir>/rules/<slug>.md`. It is never a line
inside a generated file: two branches that each add a rule add two files and do not
conflict. A rule is cited as `rule:<slug>`.

`<slug>` is the title under the entry-slug transform of `learnings-entry.md` (lower-case,
runs of other characters become one hyphen, cut to 60 characters); a name already taken
gets `-2`, `-3` and so on.

```
# <title>
- Kind: rule | critical-zone | exception
- Rule: <one imperative sentence>
- Check: <what a reviewer verifies in a diff, or the TOOLCHAIN.md row that runs it>
- Zone: <path or glob> — <category>
- Exception: <path> · "<cited line>" · <rule> — accepted YYYY-MM-DD: "<words>" (<run> F-<n>)
- Belongs with: <knowledge file name>
- Reachable: <sequence of events, each step with path:line>
- Source: learnings <date> <title> | user | proposal <file name>
- Added: YYYY-MM-DD
```

- The first line is the title, starting `# `. One `- Kind:` line, with one of the three values.
- The field the kind requires: `rule` needs `- Rule:`, `critical-zone` needs `- Zone:`,
  `exception` needs `- Exception:`. Use the other fields only where the comment says:
  `Check` and `Belongs with` for a rule, `Reachable` for a rule about a risk.
- `- Source:` and `- Added:` are always present.
- At most `ruleMaxLines` lines (`knowledge.budgets` in the manifest); a rules directory holds at
  most `rulesMaxFiles` files. A rule that needs more is two rules.
- Keep the file to its fields: no prose, no history. The sentence is the rule; the reviewer reads it.

`checks/verify-knowledge-shape.sh` verifies the shape.
