---
name: team-bootstrap
description: Use by a lead agent when initializing a new project from this template, before asking manager to implement bootstrap, to decide product shape and stack through one-question-at-a-time collaboration.
---

# team-bootstrap

## Inspect

- `AGENTS.md`
- `README.md`
- `Makefile`
- `.agents/docs/TEAM_PROTOCOL.md`
- `.agents/state/STATE.md`
- `.agents/state/MEMORY.md`
- existing project files: `pyproject.toml`, `package.json`, `pnpm-workspace.yaml`, `src/`, `tests/`

## Ask

Ask one question at a time.

- 最初は「何を作るか」を1問だけ聞く。
- 回答を受けたら、分かったことを短く反映し、次に一番 narrowing value が高い1問だけ聞く。
- 既存 repo や user request から確定できることは採用し、聞かない。
- 質問は user が判断しやすい粒度にする。必要なら推奨案を添える。
- 一度に questionnaire を並べない。
- implementation や dispatch 依頼は、bootstrap contract が固まるまで行わない。

必要に応じて次を順番に狭める。

- 何を構築するか、誰が使うか。
- deliverable: library, CLI, service, app, package, or script。
- primary language/runtime and standard toolchain。
- package name, public entrypoints, and first user-visible behavior。
- `make smoke` で確認する代表的な利用者向け動作。
- `make post-change` に追加したい必須 contract。

十分に固まったら、project shape、stack、entrypoint、`make post-change`、`make smoke` を短くまとめてから初期化する。

## Contract

- `make post-change` は worker が code change 後に実行する 1 command。
- 対象 stack の標準的な package manager、formatter、linter、test runner、必要な build/package command を入れて初期化する。
- `make post-change` は format、lint、必要な type/package/build check、test、`git diff --check -- .` を含める。
- 既存の repo-level checks がある場合は `post-change` に残す。
- `make smoke` は代表的な利用者向け動作を短時間で実行する command にする。
- 選ばなかった言語や未使用 scaffold は残さない。
- `AGENTS.md` には選んだ stack の command だけを書く。
- 必要な package manager lockfile を作る。
- 必須 tool が無い場合は blocker として扱う。

## Initialize Template Surfaces

bootstrap 実装では、template の初期記述を実プロジェクトの contract に置き換える。

- `README.md`: project name、目的、install、run command、`make post-change`、`make smoke`、主要 entrypoint。
- `AGENTS.md`: 選んだ stack の command、package dir、test/smoke 期待値、ownership note。
- `Makefile`: project の `post-change` と `smoke`。
- package metadata: package name、version、description、entrypoint、build backend、lockfile。
- `.agents/config/agent-team.yaml`: default が合わない場合の team name、tmux session、model、command。

project-facing docs から、古い example、toy name、未使用 stack command、template 固有の文言を消す。

Python and TypeScript below are examples of this rule, not the only supported stacks.

## Python

Use:

- `uv`
- `ruff`
- `pytest`
- `pyproject.toml`
- `src/<package_name>/`
- `tests/`

`pyproject.toml`:

- `[project]` に name, version, description, requires-python。
- test/dev dependency group に `pytest` と `ruff`。
- library/package なら `hatchling` などの build backend を設定する。
- ruff config は `tool.ruff` と `tool.ruff.lint` に置く。

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
- 必須 command が無い場合は失敗させる。

Examples:

- Rust: `cargo fmt --all --check`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo test`, and `cargo build` when needed.
- Go: `gofmt`, `go vet ./...`, `go test ./...`, and `go build ./...` when needed.
- Ruby: `bundle`, `rubocop`, `rspec` or `minitest`, and gem/package build when needed.
- Java/Kotlin: Gradle or Maven wrapper, formatter/linter if selected, test, and build/package tasks.
- Swift: SwiftPM or Xcode build tooling, formatter/linter if selected, tests, and build.

## Multi-package

- Use explicit package dir variables such as `PY_PACKAGE_DIRS` and `TS_PACKAGE_DIRS`.
- For multiple stacks, define `post-change` once and depend on each selected subtarget.
- If selective execution is worth it, add one explicit changed-file selector script and call it from `post-change-*`.
- Declare package dirs explicitly.

```make
post-change: post-change-py post-change-ts
	@git diff --check -- .
```

## Finish

- Run `make post-change`.
- Run `make smoke`.
- package/app build が成果物に必要なら、build command が `make post-change` に含まれていることを確認する。
- Confirm `README.md`, `AGENTS.md`, `Makefile`, package metadata, and `.agents/config/agent-team.yaml` no longer contain stale template names or unused stack commands.
- Delete `.agents/skills/team-bootstrap/` after bootstrap is complete.
- Ask manager to create and dispatch implementation tasks after the bootstrap contract is clear.
