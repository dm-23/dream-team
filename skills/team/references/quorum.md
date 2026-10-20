# Quorum (Brainstorm ×3)

Always launch three Brainstorm instances in parallel with lenses `minimalism`, `risk`, `reuse`. Agreement of 2 of 3 on a point → accepted. When proposals differ in complexity, prefer the simpler unless the complex one solves a stated problem the simple one does not.

**Reconcile round.** The three lenses again, in the phase the workflow used, with `inputs`: the path they read before, the items below (verbatim, or named by section for trigger 2), the learnings lines. Quorum per item; every resolution goes to status.md → "Decisions log". Three triggers, each counted from an output, never weighed:

1. Three different answers on a point → one round with all three outputs; still split → AskUserQuestion with the options.
2. `Decision marks: N` with N > 0 in the pointer block of an open-facts pass → one round; the handoff names the section (`### Answers to open facts` or `## Answers to open facts`) and the lenses, which read the file in full, resolve its `decision` entries. At most one such round per run; a later `decision` mark goes to the user through AskUserQuestion with the entry's options, and that entry is the one section of the report you read.
3. (Full Feature) the Architect returns `Design decision needed:` → one round over its question and options; append each resolution to the draft plan's `## Approach`, then the Architect again. At most one such round per run; a second request goes to the user the same way.

An entry marked `decision` is never resolved by you. You count marks; you do not pick between the options they list.

**Evidence route.** After any `solution` or `diagnosis` quorum, read the `### Missing Evidence` section of each lens. When every lens says `none`, nothing runs. Otherwise one handoff → ResearcherExplorer, `mode: targeted`, `inputs`: the union of the lines (in Full Feature, plus the files the quorum's `## Approach` names), `expected output`: `### Answers to open facts` appended to `plans/draft-plan.md` (Full Feature) or `## Answers to open facts` appended to `research/exploration.md` (every other workflow). Then apply trigger 2 to its pointer block. The lenses never read the answers unless trigger 2 fires; the Architect, or the inline plan you present, consumes them.
