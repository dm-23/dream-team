# Coding standards card: JavaScript (browser and server, no type checker)

## Detect

- Files: `package.json` without a `typescript` dependency and without `tsconfig.json`; `*.js`/`*.mjs`/`*.cjs`; browser assets loaded by `<script>` tags in HTML.

## Toolchain

| Purpose | Command | Notes |
|---------|---------|-------|
| Format | `npx prettier --check .` / `--write` if `.prettierrc` or CI configures it; otherwise n/a | |
| Lint | `npx eslint .` if an ESLint config exists; otherwise `node --check <file>` per changed file (syntax only) | |
| Build | `npm run build` if the script exists; otherwise n/a (no build step) | |
| Test all | `npm test` if defined; otherwise `node --test` (built-in runner) | |
| Test one | `node --test path/to/file.test.mjs` | |
| Run | `npm start` / `node <entry>` / serve static files per README | |
| Install missing | `npm ci` (lockfile present) or `npm install` | Skip if the repo has no installed packages by design. |

## Layout

- One file per page/feature for browser code if the repo does so; shared helpers in a clearly named shared module.
- Respect the module system per file: classic `<script>` files use globals (`window.X`), ES modules use `import`/`export` — never mix inside one file; changing a file's kind requires updating every `<script>` tag that loads it.

## Naming

- `camelCase` for variables/functions, `PascalCase` for constructors/classes, `UPPER_SNAKE` for constants; file names in the repo's dominant style (kebab-case typical).
- DOM ids/classes in kebab-case; data attributes `data-*`.

## Errors

- `async` functions: every awaited call inside `try/catch` or the promise chain ends in `.catch`; surface errors to the user via the page's existing notification/error pattern.
- Never swallow: no empty `catch {}`; log with context at minimum.

## Concurrency

- Avoid overlapping requests for the same resource (in-flight guard or abort of the previous request); debounce user-driven refresh.
- Timers/intervals must be cleared when their owner is removed or the page state changes.

## Testing

- Built-in `node:test` + `node:assert/strict` unless the repo already uses another runner; test pure functions extracted from DOM code; no DOM emulation unless already present.
- File naming `<module>.test.mjs` next to the module (or the repo's existing convention).

## Dependencies

- No new runtime dependency for browser code without an explicit task requirement; externally hosted libraries pinned to an exact version.

## Security

- Never build HTML from untrusted strings via `innerHTML` without escaping; prefer `textContent`/DOM APIs or the repo's escape helper.
- Never store secrets in front-end code or browser storage.

## Anti-patterns

- Global mutable state added outside the page's existing state object.
- Copy-pasting markup blocks (e.g. navigation) across pages without updating all copies — treat repeated markup as a multi-file checklist.
- Adding `import`/`export` to a classic script (breaks every page that loads it).

## Review checks

1. `node --check` passes for every changed script; linter/formatter clean if configured.
2. Module kind unchanged per file (classic vs ES module) or every loader updated.
3. No `innerHTML` with unescaped dynamic data.
4. Every `await` has an error path; no empty `catch`.
5. Intervals/timers/listeners cleaned up where the owner is torn down.
6. State kept in the page's existing state object; no new globals.
7. Repeated markup (navigation, footers) updated in every page that has a copy.
8. New pure logic has a `node:test` (or repo runner) test.

## Sources

- MDN JavaScript Guide; Airbnb JavaScript Style Guide (naming/formatting); Node.js test runner documentation.
