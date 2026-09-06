# Coding standards card: TypeScript

## Detect

- Files: `tsconfig.json`; a `typescript` dependency in `package.json`; `*.ts`/`*.tsx`.

## Toolchain

| Purpose | Command | Notes |
|---------|---------|-------|
| Format | `npx prettier --check .` / `--write` | Or the repo's configured formatter (biome, dprint). |
| Lint | `npx eslint .`; `npx tsc --noEmit` (type check) | Both must pass; CI is authoritative. |
| Build | `npm run build` | |
| Test all | `npm test` (`vitest run` / `jest` per repo) | |
| Test one | `npx vitest run path/to/file.test.ts` or `npx jest path/to/file.test.ts` | |
| Run | `npm run dev` / `npm start` | |
| Install missing | `npm ci` (or `pnpm i --frozen-lockfile` / `yarn --immutable` per lockfile) | |

## Layout

- Feature-first folders if the repo uses them; colocate tests (`x.test.ts`) or `__tests__/` per existing convention.
- Barrel files only where they already exist.

## Naming

- `camelCase` variables/functions, `PascalCase` types/classes/components, `UPPER_SNAKE` constants; no `I` prefix on interfaces unless the repo does it; type-only imports via `import type`.

## Errors

- Never `any` in catch; narrow with `instanceof`/type guards; typed error results (`Result`/discriminated unions) if the repo uses them.
- Async boundaries handle rejection; no floating promises (`no-floating-promises` rule if ESLint has it).

## Concurrency

- Cancel stale async work (AbortController) in UI code; effects/subscriptions cleaned up on teardown.

## Testing

- Repo's runner (vitest/jest); test behavior via the public API; UI tests query by role/text, not by implementation details; no snapshot tests for logic.

## Dependencies

- Lockfile committed and updated by the package manager only; runtime vs development dependency placement correct; no duplicate libraries for the same purpose.

## Security

- No `dangerouslySetInnerHTML`/`innerHTML` with unescaped data; validate external data at the boundary (a schema validation library if present); secrets only via build-time environment with a public-prefix policy.

## Anti-patterns

- `any`, `as unknown as`, non-null `!` to silence the compiler; `@ts-ignore` without a linked reason.
- Enum for string unions when the repo prefers union types (or vice versa).
- Default exports where the repo uses named exports.

## Review checks

1. `tsc --noEmit` and ESLint exit 0; formatter clean.
2. No new `any`, `!`, `as unknown as`, `@ts-ignore`.
3. No floating promises; async errors handled.
4. Effects/subscriptions/timers cleaned up.
5. Types imported with `import type`; public functions fully typed.
6. Tests for new logic with the repo's runner; UI tests query by role/text.
7. Lockfile updated only through the package manager; dependency placed in the correct section.

## Sources

- TypeScript Handbook; typescript-eslint recommended rules; Google TypeScript Style Guide.
