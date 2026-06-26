---
name: team-debug
description: Guides root-cause debugging before another fix attempt. Use when tests fail, behavior is unexpected, a build breaks, state is inconsistent, or a previous fix failed.
---

# team-debug

## Rule

修正案より先に、再現条件と root cause を集める。

## Process

1. error / log / stack trace を最後まで読む。
2. 再現 command、入力、環境、差分を特定する。
3. 最近の変更と、似た working example を見る。
4. 複数 component が関わる場合は、境界ごとに入力、出力、設定、状態を確認する。
5. 仮説を1つだけ立てる。
6. 最小の観測または変更で仮説を検証する。
7. root cause が見えたら、再発防止できる test または検証を足してから直す。

## Stop

同じ問題に対して 3 回連続で修正が外れたら、4 回目を試さない。task の前提、architecture、ownership、contract を疑い、blocker または question として戻す。

## Report

- 再現 command
- error / log の要点
- root cause と evidence
- 直した場所
- 再発防止の検証
