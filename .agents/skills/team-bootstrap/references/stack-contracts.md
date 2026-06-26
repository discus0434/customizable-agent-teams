# Stack Contracts

## Contents

- Python
- TypeScript
- Other Stack

Python and TypeScript are examples of the general rule, not the only supported stacks.

## Python

Use:

- `uv`
- `ruff`
- `pytest`
- `pyproject.toml`
- `src/<package_name>/`
- `tests/`

`pyproject.toml`:

- `[project]` has name, version, description, requires-python.
- test/dev dependency group has `pytest` and `ruff`.
- library/package deliverables use a build backend such as `hatchling`.
- ruff config lives under `tool.ruff` and `tool.ruff.lint`.

`make post-change` path:

```make
PY_PACKAGE_DIRS := .

post-change: post-change-py
	@git diff --check -- .

post-change-py:
	@set -e; \
	for dir in $(PY_PACKAGE_DIRS); do \
		echo "==> $$dir"; \
		(cd $$dir && uv run ruff format .); \
		(cd $$dir && uv run ruff check . --fix); \
		(cd $$dir && uv run --group test pytest -q); \
	done
```

For a package build contract, add `uv build` to `post-change-py`.

## TypeScript

Use:

- `pnpm`
- `typescript`
- `biome`
- `vitest`
- `package.json`
- `tsconfig.json`
- `src/`
- `tests/`

`package.json` scripts:

- `format`: `biome format --write .`
- `lint`: `biome check .`
- `typecheck`: `tsc --noEmit`
- `test`: `vitest`
- `build`: project-specific package/app build when needed

`make post-change` path:

```make
PNPM ?= pnpm
TS_PACKAGE_DIRS := .

post-change: post-change-ts
	@git diff --check -- .

post-change-ts:
	@set -e; \
	for dir in $(TS_PACKAGE_DIRS); do \
		echo "==> $$dir"; \
		(cd $$dir && $(PNPM) -s format); \
		(cd $$dir && $(PNPM) -s lint); \
		(cd $$dir && $(PNPM) -s typecheck); \
		(cd $$dir && $(PNPM) -s test -- --run); \
	done
```

For a package/app build contract, add `$(PNPM) -s build` to `post-change-ts`.

## Other Stack

- Choose the stack's normal package manager, formatter, linter, test runner, and build/package command.
- Initialize real project metadata, dependency files, source layout, tests, and lockfiles for that stack.
- Wire the selected tools into `make post-change`.
- Define `make smoke` as a short user-visible behavior check.
- Update `AGENTS.md` and `README.md` with the actual selected commands.
- Keep only examples and scaffold for the selected stack.
- Treat a missing required command as a blocker.

Examples:

- Rust: `cargo fmt --all --check`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test`, and `cargo build` when needed.
- Go: `gofmt`, `go vet ./...`, `go test ./...`, and `go build ./...` when needed.
- Ruby: `bundle`, `rubocop`, `rspec` or `minitest`, and gem/package build when needed.
- Java/Kotlin: Gradle or Maven wrapper, formatter/linter if selected, test, and build/package tasks.
- Swift: SwiftPM or Xcode build tooling, formatter/linter if selected, tests, and build.
