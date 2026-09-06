# Coding standards card: C# / .NET

## Detect

- Files: `*.sln`, `*.csproj`, `Directory.Build.props`, `global.json`, `*.cs`.

## Toolchain

| Purpose | Command | Notes |
|---------|---------|-------|
| Format | `dotnet format --verify-no-changes` / `dotnet format` | Honors `.editorconfig`. |
| Lint | `dotnet build -warnaserror` if CI does; analyzers via `.editorconfig`/`Directory.Build.props` | |
| Build | `dotnet build <sln> -c Release` | Can be slow on large solutions — batch changes before building. |
| Test all | `dotnet test <sln> --no-build` | |
| Test one | `dotnet test <proj> --filter "FullyQualifiedName~Namespace.Class.Method"` | |
| Run | `dotnet run --project <path>` | |
| Install missing | `dotnet tool restore`; SDK version from `global.json` | |

## Layout

- One type per file, file name = type name; folders mirror namespaces; tests in `<Project>.Tests` mirroring source folders.

## Naming

- `PascalCase` for types/methods/properties/public fields, `camelCase` locals/parameters, `_camelCase` private fields, `I` prefix for interfaces, `Async` suffix on async methods.

## Errors

- Throw specific exceptions; never catch `Exception` except at the top-level boundary; preserve stack (`throw;`); no exceptions for expected control flow (use result types or the `Try` pattern).

## Concurrency

- `async` all the way: no `.Result`/`.Wait()`/`GetAwaiter().GetResult()`; `ConfigureAwait(false)` in libraries; pass `CancellationToken` through; `IAsyncEnumerable` for streams.

## Testing

- Repo's framework (xUnit/NUnit/MSTest) and mocking library (Moq/NSubstitute) — never introduce a second one; Arrange-Act-Assert; naming `Method_WhenCondition_ShouldOutcome` if the repo uses it.

## Dependencies

- Central package management if `Directory.Packages.props` exists; no floating versions; dependency-injection registrations next to the feature (extension method) per repo pattern.

## Security

- Parameterized queries or the data-access library's query API — no string-built SQL; authorization attribute/policy on every new endpoint; input validation at the boundary; secrets from configuration providers, never committed in settings files.

## Anti-patterns

- Service locator / `IServiceProvider` injected into business classes; static mutable state; God services; `async void` outside event handlers; repeated per-item queries inside loops caused by lazy loading.

## Review checks

1. `dotnet format --verify-no-changes` clean; build has no new warnings (or `-warnaserror` passes).
2. No sync-over-async (`.Result`, `.Wait()`); `CancellationToken` threaded through new async paths.
3. No string-built SQL; data-access queries include required related-data loading; no repeated per-item queries in loops.
4. New endpoint has an authorization attribute/policy and input validation.
5. Dependency-injection registration present for new services; lifetime appropriate (no scoped captured by singleton).
6. Tests with the repo's framework; Arrange-Act-Assert; no logic in test setup that duplicates production code.
7. One type per file; namespaces match folders.

## Sources

- Microsoft C# Coding Conventions; Framework Design Guidelines; .NET async guidance (David Fowler's AsyncGuidance).
