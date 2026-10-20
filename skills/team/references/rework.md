# Rework loop

If Reviewer returns `manual` findings or `needs rework`: handoff → Developer with the findings, then Reviewer again (max 2 cycles, then escalate to the user).

Any change made after the batch review — a finding, a user decision — goes back through the Reviewer before the gate; the final review never stands in for it.
