# Stackごとの初期値

PythonとTypeScriptは例であり、対応するstackをこの二つに限定しない。

## Python

標準構成として次を使う。

- package manager：`uv`。
- formatterとlinter：`ruff`。
- test runner：`pytest`。
- metadata：`pyproject.toml`。
- source：`src/<package_name>/`。
- test：`tests/`。

`pyproject.toml`には、project名、version、description、対応Python versionを記載する。

test用dependency groupには`pytest`と`ruff`を含める。

libraryまたはpackageでは、`hatchling`などのbuild backendを設定する。

`ruff`の設定は`tool.ruff`と`tool.ruff.lint`へ置く。

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

packageのbuildが必要な場合は、`post-change-py`へ`uv build`を加える。

## TypeScript

標準構成として次を使う。

- package manager：`pnpm`。
- language：`typescript`。
- formatterとlinter：`biome`。
- test runner：`vitest`。
- metadata：`package.json`。
- compiler設定：`tsconfig.json`。
- source：`src/`。
- test：`tests/`。

`package.json`には、実際に使うscriptだけを定義する。

- `format`：`biome format --write .`。
- `lint`：`biome check .`。
- `typecheck`：`tsc --noEmit`。
- `test`：`vitest`。
- `build`：deliverableに必要なbuild command。

```make
TS_PACKAGE_DIRS := .

post-change: post-change-ts
	@git diff --check -- .

post-change-ts:
	@set -e; \
	for dir in $(TS_PACKAGE_DIRS); do \
		echo "==> $$dir"; \
		(cd $$dir && pnpm -s format); \
		(cd $$dir && pnpm -s lint); \
		(cd $$dir && pnpm -s typecheck); \
		(cd $$dir && pnpm -s test -- --run); \
	done
```

applicationまたはpackageのbuildが必要な場合は、`post-change-ts`へ`pnpm -s build`を加える。

## その他のstack

- そのecosystemで通常使われるpackage manager、formatter、linter、test runner、build commandを選ぶ。
- 実際のmetadata、dependency file、source、test、lockfileを作る。
- 選んだtoolを`make post-change`から実行する。
- `make smoke`には代表的な利用者向けの挙動を設定する。
- `AGENTS.md`と`README.md`には、実際に使うcommandだけを書く。

代表例は次のとおり。

- Rust：`cargo fmt --all --check`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test`、必要な`cargo build`。
- Go：`gofmt`、`go vet ./...`、`go test ./...`、必要な`go build ./...`。
- Ruby：`bundle`、`rubocop`、`rspec`または`minitest`、必要なpackage build。
- JavaまたはKotlin：Gradle WrapperまたはMaven Wrapper、選んだformatterとlinter、test、build。
- Swift：SwiftPMまたはXcode build tool、選んだformatterとlinter、test、build。
