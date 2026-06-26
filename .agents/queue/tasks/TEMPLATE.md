# T-XXX: Task title

Owner: worker-1
Reviewer: reviewer-1

## Context

- 背景:
- 現在確認済みの事実:
- 関連 docs:
- 関連 strategy artifact:

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

## Worker Flow

1. この task と `.agents/docs/TEAM_PROTOCOL.md` を読む。
2. 実装中に迷ったら担当 reviewer に相談する。
3. 実装、検証、commit を行う。
4. `make report TASK=T-XXX AGENT=worker-1 STATUS=needs_review` を実行する。
5. report の未記入欄を埋める。
6. reviewer に `ready_for_review` を送る。

## Reviewer Flow

担当 reviewer は `.agents/queue/reviews/T-XXX_reviewer-1.md` に review artifact を書き、次を実行する。

```bash
make review-report TASK=T-XXX REVIEWER=reviewer-1 DECISION=OK
```

decision は `OK` / `FIX` / `ASK_MANAGER` のいずれか。

## Report

完了時は `.agents/queue/reports/T-XXX_worker-1.md` に report を書く。
summary、changed files、verification、post-change、smoke の result/evidence を埋める。

## Memory

中長期的に残すべき rules、tips、pitfalls、user preferences がある場合は、`.agents/queue/memory_proposals/` に proposal を作る。
