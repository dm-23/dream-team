# Coding standards card: generic (fallback)

Use when no language card matches. Sections and order are mandatory for every card.

## Detect

- Files: (none — fallback)

## Toolchain

| Purpose | Command | Notes |
|---------|---------|-------|
| Format | (take from repo: CI config, README, task runner) | |
| Lint | (same) | |
| Build | (same) | |
| Test all | (same) | |
| Test one | (same) | |
| Run | (same) | |

## Layout

- Follow the repository's existing folder structure; new files go next to the closest existing sibling of the same kind.

## Naming

- Match the dominant naming style of the surrounding files (case style, prefixes, file naming) — read 3 neighbours before choosing a name.

## Errors

- Never swallow errors silently; propagate or log with context, following the pattern of the nearest existing handler.

## Concurrency

- Do not introduce background work, shared mutable state or locks unless an existing module already does it the same way.

## Testing

- Use the repository's existing test runner and assertion style (see TESTING-CONVENTIONS.md). Tests live where existing tests live.

## Dependencies

- No new third-party dependency without an explicit task requirement; prefer the standard library and what is already in the manifest.

## Security

- Parameterize all queries/commands; validate input at the boundary; never log secrets; never commit credentials.

## Anti-patterns

- Speculative abstractions (interface with one implementation, base class with one subclass).
- TODO/FIXME left in delivered code.
- "While I'm here" edits outside task scope.

## Review checks

1. Formatter applied (TOOLCHAIN → Format shows no diff).
2. Linter clean (TOOLCHAIN → Lint exit 0).
3. No new dependency outside the task.
4. Errors propagated with context, none swallowed.
5. Queries/commands parameterized; no string-built commands.
6. No TODO/FIXME/HACK.
7. No unrelated changes in the diff.

## Sources

- Repository conventions only.
