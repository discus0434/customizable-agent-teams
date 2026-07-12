# T-XXX: <title>

Worker: general-worker-1
Supervisor:
Architecture required: false

## Context

- 背景:
- 現在確認済みの事実:
- 関連 docs / artifacts:

## Allowed paths

- `path/to/file`

## Do not modify

- `.agents/state/STATE.md`
- `.agents/state/MEMORY.md`

Path bullets may be plain paths, path patterns, or backtick-wrapped paths, with optional text after the path.
`Allowed paths` is the task commit whitelist. Add specific sensitive or externally owned paths under `Do not modify`; keep the two sections non-overlapping.

## Goal

<この task で成立させる状態>

## Acceptance

- <観測可能な成功条件>

## Constraints

- <守るべき境界や既存 contract>

## Verification

- Task-specific: `<command>`
- `make post-change`
- `make smoke`

## Report Evidence

- summary、changed files、task commits、task-specific verification、post-change、smoke を具体的に記録する。
- supervisor との相談、feedback、strategy / architecture artifact の扱いを記録する。

## Supervision

- blocker、不確実さ、低い自信、scope 変更の誘惑があれば固定 supervisor に相談する。
- reviewer の入力が実装を有意に変え得る時は `supervision_checkpoint` で相談する。
- 実装、検証、task commit、report 更新後に `ready_for_supervision` を送る。

## Escalation

- task-local な判断は supervisor に相談する。
- task boundary、acceptance、cross-task impact、解消できない blocker は supervisor から Manager に上げる。

## Memory

中長期的に残すべき rules、tips、pitfalls、user preferences がある場合は、気づいた role が `.agents/queue/memory_proposals/` に proposal を作る。
