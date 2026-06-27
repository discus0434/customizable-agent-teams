---
name: team-bootstrap
description: Guides one-question-at-a-time project bootstrap from this template. Use when a lead initializes a new project, chooses product shape and stack, defines post-change and smoke contracts, and prepares manager intake for bootstrap implementation.
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

For stack-specific defaults and Makefile examples, read [references/stack-contracts.md](references/stack-contracts.md) after the stack is known or when manager needs concrete bootstrap commands.

## Multi-package

- Use explicit package dir variables such as `PY_PACKAGE_DIRS` and `TS_PACKAGE_DIRS`.
- For multiple stacks, define `post-change` once and depend on each selected subtarget.
- If selective execution is worth it, add one explicit changed-file selector script and call it from `post-change-*`.
- Declare package dirs explicitly.

```make
post-change: post-change-py post-change-ts
	@git diff --check -- .
```

## Manager Handoff

When the bootstrap contract is clear, send manager an `intake` message that includes:

- project name, goal, and first user-visible behavior
- selected stack and required package/tool commands
- entrypoint and package metadata
- `make post-change` contract
- `make smoke` behavior
- README and AGENTS updates required for the initialized project
- cleanup required after bootstrap implementation
- that manager may task, dispatch, and release-review the bootstrap work inside this contract without another human approval
- what must return to lead before manager proceeds

Tell the human to detach from tmux and run:

```bash
make bootstrap-team
```

This keeps the lead pane alive and starts the remaining roles.

## Bootstrap Implementation Done

Manager owns this work after intake.

Done means:

- `make post-change` passes.
- `make smoke` passes.
- package/app build is included in `make post-change` when the deliverable needs it.
- `README.md`, `AGENTS.md`, `Makefile`, package metadata, and `.agents/config/agent-team.yaml` describe the initialized project.
- selected stack files, source layout, tests, and lockfiles exist.
- unused scaffold, unused stack commands, and placeholder project names are gone.
- `.agents/skills/team-bootstrap/` is removed.
- bootstrap-only Make targets are removed.
- `.agents/scripts/team_bootstrap.sh` and `.agents/scripts/team_bootstrap_team.sh` are removed.
- `.agents/harness.mk` and `.agents/tests/` are removed unless the initialized project intentionally keeps template self-tests.
- no references remain to removed bootstrap scripts, bootstrap targets, or template self-tests.
