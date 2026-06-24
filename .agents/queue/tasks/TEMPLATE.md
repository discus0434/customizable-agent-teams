# T-XXX: Task title

Owner: worker-1

## Context

- 背景:
- 現在確認済みの事実:
- 関連 docs:

## Allowed paths

- `path/to/file`

## Do not modify

- `.agents/docs/MEMORY.md`
- 他 worker の ownership に入る file

## Goal

この task で達成することを書く。

## Acceptance

- [ ] 受け入れ条件を書く。

## Verification

- `command`
- `make post-change`
- `make smoke`
- report に summary、changed files、各 command の result/evidence を記録する。
- `make review TASK=T-XXX AGENT=worker-1`

## Report

完了時は `.agents/queue/reports/T-XXX_worker-1.md` に report を書く。
`make review` の前に、summary、changed files、verification、post-change、smoke の result/evidence を埋める。
review 結果は `.agents/queue/reviews/T-XXX_worker-1_review.md` を読む。
review artifact を処理した後、review 通知が inbox に残っていれば `make inbox AGENT=worker-1 MARK=<message_id>` で処理済みにする。
統合は lead が `make integrate TASK=T-XXX AGENT=worker-1` で行う。

## Memory

永続化すべき教訓がある場合は、`.agents/queue/memory_proposals/` に proposal を作る。
