---
name: team-tdd
description: Guides test-first implementation for behavior changes, bug fixes, core logic, adapters, queues, state, and tests. Use when an implementation worker can express the expected contract before implementation.
---

# team-tdd

## Use For

- bug fix
- user-visible behavior
- core logic、parser、planner、adapter、queue、state 管理
- 境界条件や失敗時挙動

Docs、task/report、rename、コメント修正では薄くしてよい。省く場合は代替検証を report に書く。

## Cycle

1. RED: 1つの期待動作を示すテストを書く。
2. RED確認: test command を実行し、期待した失敗であることを確認する。
3. GREEN: 最小実装で通す。
4. GREEN確認: 同じ test command を実行し、通ることを確認する。
5. REFACTOR: 重複、命名、責務境界を整える。挙動は増やさない。
6. REGRESSION: bug fix では、可能なら修正を一時的に戻してテストが落ちることも確認する。

## Test Shape

- public contract と重要な境界を見る。
- mock は必要な外部副作用に限定する。
- sleep / timeout に頼る flaky test を避ける。
- 実装詳細より外から観測できる結果を優先する。
- 1 test = 1 behavior。

## Report

- RED command と結果。
- GREEN command と結果。
- 追加・更新した test file。
- 省いた検証があれば理由。
