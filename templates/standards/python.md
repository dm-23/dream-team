# Coding standards card: Python

## Detect

- Files: `pyproject.toml`, `setup.py`, `setup.cfg`, `requirements*.txt`, `Pipfile`, `*.py`.

## Toolchain

| Purpose | Command | Notes |
|---------|---------|-------|
| Format | `ruff format --check .` / `ruff format .`; or `black --check .` if configured | Use whichever `pyproject.toml`/CI configures. |
| Lint | `ruff check .`; `mypy .` if `[tool.mypy]` or CI has it | |
| Build | `python -m build` (packages) or n/a (apps) | |
| Test all | `python -m pytest -q` | Use the repo's virtualenv interpreter path if README/CI names one. |
| Test one | `python -m pytest path/to/test_x.py::test_name -q` | |
| Run | `python -m <package>` or the entry point from `pyproject.toml [project.scripts]` | |
| Install missing | `python -m pip install -e ".[dev]"` or `pip install -r requirements-dev.txt` | |

## Layout

- `src/<package>/` layout preferred if the repo uses it; otherwise top-level package. Tests in `tests/` mirroring package modules (`tests/test_<module>.py`).
- One module per concern; `__init__.py` re-exports only the public API.

## Naming

- `snake_case` for functions/variables/modules, `PascalCase` for classes, `UPPER_SNAKE` for constants; leading `_` for internal.
- Boolean names read as predicates (`is_ready`, `has_items`).

## Errors

- Raise specific exceptions (subclass a project base exception if one exists); never bare `except:`; catch the narrowest class.
- Preserve cause: `raise NewError(...) from err`.
- No exceptions for control flow in hot paths; return values/`Optional` where the caller expects absence.

## Concurrency

- Async code never calls blocking I/O (`time.sleep`, sync DB drivers) inside `async def`; use the async counterpart or `run_in_executor`.
- Shared state across threads/processes goes through queues or explicit locks; prefer process pools for CPU-bound work.

## Testing

- `pytest`; plain `assert` with descriptive expressions; fixtures over setup methods; `parametrize` for tables.
- Test files `test_*.py`, functions `test_<behavior>`; mock at the boundary (`monkeypatch`, `unittest.mock`) — never mock the unit under test.
- Deterministic: fixed seeds, frozen time, no network.

## Dependencies

- Declared in `pyproject.toml` (or `requirements*.txt` if that's the repo's choice); pinned in a lock file if one exists; dev tools in the dev extra.
- Prefer stdlib (`pathlib`, `dataclasses`, `json`, `logging`).

## Security

- Parameterized DB queries (driver placeholders), never f-strings into SQL.
- `subprocess.run([...], check=True)` with list args, never `shell=True` with user input.
- No `pickle`/`eval` on untrusted data; secrets from environment.

## Anti-patterns

- Mutable default arguments; `from module import *`; catching `Exception` to "keep going".
- Business logic in `__init__.py` or in notebooks that production imports.
- Type hints missing on new public functions when the repo uses them.

## Review checks

1. `ruff format --check` (or the configured formatter) clean for changed files.
2. `ruff check` (and `mypy` if configured) exit 0.
3. No bare `except`; exceptions re-raised with `from`.
4. Type hints on new/changed public function signatures (if repo uses hints).
5. No blocking I/O inside `async def`.
6. SQL/subprocess calls parameterized; no `shell=True` with dynamic input.
7. New logic has a `pytest` test; parametrized when there are ≥3 cases.
8. No mutable default arguments.
9. New dependency declared in the project manifest and justified by the task.

## Sources

- PEP 8, PEP 20, PEP 484/PEP 604 typing; Google Python Style Guide; pytest good practices.
