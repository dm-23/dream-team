# Coding standards card: Go

## Detect

- Files: `go.mod` at repo root or in a subdirectory; `*.go`.

## Toolchain

| Purpose | Command | Notes |
|---------|---------|-------|
| Format | `gofmt -l .` (report) / `gofmt -w <files>` (apply) | Zero output from `-l` is mandatory. `goimports` if the repo's tools or CI mention it. |
| Lint | `go vet ./...`; `golangci-lint run` if `.golangci.yml` or CI uses it | Pin the same version CI uses. |
| Build | `go build ./...` | Cheap (seconds) — safe to run often. |
| Test all | `go test ./...` | Add `-race` when CI does. |
| Test one | `go test ./path/to/pkg/... -run '^TestName$' -v` | |
| Run | `go run ./cmd/<name>` | |
| Install missing | `go install github.com/golangci/golangci-lint/cmd/golangci-lint@<CI version>` | Only if CI uses it. |

## Layout

- `cmd/<binary>/main.go` for entry points; `internal/` for non-exported packages; one package per directory; package name = directory name (short, lower-case, no underscores).
- Tests colocated: `foo.go` ↔ `foo_test.go`, same package (white-box) unless the repo uses `_test` packages.
- No `util`/`common`/`helpers` packages; name by what the package provides.

## Naming

- `MixedCaps`/`mixedCaps`; acronyms keep case (`HTTPServer`, `userID`, `sqlDB`).
- Getters without `Get` prefix; interfaces with one method end in `-er` (`Reader`).
- Receiver names short and consistent per type (`s *Server`), never `this`/`self`.
- Exported identifiers have doc comments starting with the identifier name.

## Errors

- Return `error` as the last value; check every error; never `_ = err` except documented deferred closes.
- Wrap with context: `fmt.Errorf("loading config: %w", err)`; compare with `errors.Is`/`errors.As`, never string matching.
- Sentinel errors as `var ErrX = errors.New(...)`; custom types only when callers need fields.
- No `panic` for expected failures; `log.Fatal` only in `main`.

## Concurrency

- Every goroutine has a clear owner and exit path; pass `context.Context` as the first parameter to anything that blocks or does I/O.
- Guard shared state with `sync.Mutex` or channels — never both for the same state; document which.
- Prefer `errgroup`/`sync.WaitGroup` over ad-hoc `done` channels; never leak goroutines in tests.

## Testing

- Standard `testing` package; table-driven tests with `t.Run(name, ...)`; `t.Helper()` in helpers.
- `t.Fatalf` for setup failures, `t.Errorf` for assertions that can continue; message format `got X, want Y`.
- Handler tests via the framework's in-process test client or `net/http/httptest`; external HTTP via `httptest.NewServer`.
- Mocks are hand-written structs satisfying the interface; no mocking framework unless the repo already has one.

## Dependencies

- `go.mod` is the manifest; `go mod tidy` must produce no diff; no replace directives to local paths in committed code.
- Prefer stdlib (`net/http`, `encoding/json`, `database/sql`) unless the repo already standardizes on a library.

## Security

- SQL only with placeholders (`$1`, `?`) — never `fmt.Sprintf` into a query string; build dynamic WHERE clauses by appending placeholder fragments and an args slice.
- Validate and bound all request input (page sizes, IDs, enum values) at the handler boundary.
- Secrets only from environment/secret store; never in source or logs; `crypto/rand` for anything security-relevant.

## Anti-patterns

- Interfaces defined next to the implementation "for the future" — define interfaces where they are consumed, when a second implementation exists.
- `init()` with side effects; package-level mutable state.
- Ignoring `rows.Close()`/`resp.Body.Close()`; not checking `rows.Err()`.
- Positional `SELECT ... Scan(...)` drift: adding a column to one side and not the other.
- Copy-pasted SQL between two code paths that must stay identical (e.g. bulk sync vs single refresh) without a shared builder or a test pinning both.

## Review checks

1. `gofmt -l` prints nothing for changed files.
2. `go vet ./...` and (if present) `golangci-lint run` exit 0.
3. Every returned `error` is checked or explicitly documented as ignored.
4. Errors wrapped with `%w` and context; no string comparison of error text.
5. No `fmt.Sprintf`/concatenation building SQL or shell commands; placeholders and args slice only.
6. Every `SELECT` column list change has a matching `Scan` change (and vice versa) in all readers of that row shape.
7. New goroutine → has context/cancellation and a shutdown path.
8. `context.Context` first parameter on new I/O functions.
9. Table-driven test present for new pure logic; handler test present for new endpoint (per TESTING-CONVENTIONS.md).
10. `go mod tidy` produces no diff.
11. Exported identifiers have doc comments.
12. No package-level mutable state introduced.

## Sources

- Effective Go; Go Code Review Comments (golang/go wiki); Google Go Style Guide; Uber Go Style Guide.
