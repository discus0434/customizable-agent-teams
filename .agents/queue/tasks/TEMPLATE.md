# T-XXX: Task title

Owner: worker-1
Reviewer: reviewer-1
Architecture required: false

## Context

- 背景:
- 現在確認済みの事実:
- 関連 docs:
- 関連 strategy artifact:
- 関連 architecture note:

## Allowed paths

- `path/to/file`

## Do not modify

- `.agents/state/STATE.md`
- `.agents/state/MEMORY.md`
- 他 task の ownership に入る file

## Goal

この task で達成することを書く。

## Acceptance

- [ ] 受け入れ条件を書く。

## Verification

- `command`
- `make post-change`
- `make smoke`
- report に summary、changed files、各 command の result/evidence を記録する。

## Reviewer Supervision

- Checkpoints: worker が相談したい節目。大きい task では具体的に書く。小さい task は `worker initiated`。
- Escalation: task 固有の manager escalation 条件。共通条件は AGENTS.md / TEAM_PROTOCOL.md に従う。
- Strategy: strategist に相談すべき task 固有の条件。
- Architecture: architect に相談すべき task 固有の条件。不要なら `none`。
- Evidence expectation: reviewer が `OK` を出すために必要な evidence。

## Worker Flow

1. この task と `.agents/docs/TEAM_PROTOCOL.md` を読む。
2. 実装中に迷ったら担当 reviewer に相談する。
3. 実装、検証、commit を行う。
4. `make report TASK=T-XXX AGENT=worker-1 STATUS=needs_review` を実行する。
5. report の未記入欄を埋め、reviewer feedback と strategy artifact の扱いも記録する。
6. reviewer に `ready_for_review` を送る。

## Reviewer Flow

担当 reviewer は `.agents/queue/reviews/T-XXX_reviewer-1.md` に review artifact を書き、次を実行する。

```bash
make review-report TASK=T-XXX REVIEWER=reviewer-1 DECISION=OK
```

decision は `OK` / `FIX` / `ASK_MANAGER` のいずれか。
`OK` は task-local scope について done 推薦を含む。

## Report

完了時は `.agents/queue/reports/T-XXX_worker-1.md` に report を書く。
summary、changed files、verification、post-change、smoke、reviewer supervision、strategy artifacts、architecture の result/evidence を埋める。

## Memory

中長期的に残すべき rules、tips、pitfalls、user preferences がある場合は、`.agents/queue/memory_proposals/` に proposal を作る。
