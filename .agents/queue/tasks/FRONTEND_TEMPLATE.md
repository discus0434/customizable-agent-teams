# T-XXX: <title>

Worker: frontend-worker-1
Supervisor:
Architecture required: false

## Context

- 背景:
- 現在確認済みの事実:
- 関連 docs / artifacts:
- 既存 UI / design system:

## Allowed paths

- `path/to/frontend/file`

## Do not modify

- `.agents/state/STATE.md`
- `.agents/state/MEMORY.md`

Path bullets may be plain paths, path patterns, or backtick-wrapped paths, with optional text after the path.
Add task-specific protected paths when another task or role owns them.

## Goal

<この task で成立させる user-visible state>

## Acceptance

- <画面・操作・状態として観測できる成功条件>

## Constraints

- <design、platform、interaction、accessibility、既存 contract>

## View Direction

- 対象 surface:
- 伝えるべき優先順位:
- interaction / navigation:
- responsive / platform adaptation:
- critic が direction critique を不要と判断できる既存方針:

## Visual Verification

- Project guidance: `AGENTS.md` の Visual Verification を参照する。
- 確認する画面・状態:
- device / viewport:
- screenshot evidence: `.agents/queue/visuals/T-XXX/`

## Verification

- Task-specific: `<command>`
- `make post-change`
- `make smoke`

## Report Evidence

- summary、changed files、commit、task-specific verification、post-change、smoke を具体的に記録する。
- direction result、visual iterations、screenshot paths、critic feedback と対応を記録する。

## Supervision

- frontend-critic の direction response を受けてから主要 UI 実装へ進む。
- 実装中は実画面と screenshot を確認し、critic と visual iteration を行う。
- blocker、不確実さ、低い自信、scope 変更の誘惑があれば critic に相談する。
- 実装、検証、commit、report 更新後に `ready_for_supervision` を送る。

## Escalation

- task-local な判断は frontend-critic に相談する。
- task boundary、acceptance、cross-task impact、解消できない blocker は critic から Manager に上げる。

## Memory

中長期的に残すべき rules、tips、pitfalls、user preferences がある場合は、気づいた role が `.agents/queue/memory_proposals/` に proposal を作る。
