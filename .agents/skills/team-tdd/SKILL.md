---
name: team-tdd
description: Implementation Workerが期待する挙動を実装前にtestで表せるときに、bug fix、利用者に見える挙動、core logic、adapter、queue、state、境界条件をtest-firstで実装するために使う。
---

# team-tdd

## 適用対象

- bug fix。
- 利用者に見える挙動。
- core logic、parser、planner、adapter、queue、state管理。
- 境界条件と失敗時の挙動。

文書だけの変更、taskまたはreport、rename、comment修正では、変更に合う直接的な検証を選んでよい。

## Cycle

1. **RED**：期待する一つの挙動をtestで表す。
2. **RED確認**：test commandを実行し、意図した理由で失敗することを確認する。
3. **GREEN**：期待する挙動と影響する経路を満たす実装を行う。
4. **GREEN確認**：同じtest commandを実行し、成功することを確認する。
5. **REFACTOR**：重複、命名、責務境界を整え、挙動が変わっていないことを確認する。
6. **REGRESSION**：bug fixでは、追加したtestが修正前の問題を検出することを確認する。

## Testの選び方

- public contractと重要な境界を確認する。
- mockは、置き換えが必要な外部作用に限る。
- `sleep`とtimeoutへ依存する不安定なtestを避ける。
- 実装詳細より、外部から観測できる結果を優先する。
- 一つのtestでは一つの挙動を確認する。

## 検証記録

- REDのcommandと結果。
- GREENのcommandと結果。
- 追加または更新したtest file。
- test-firstを使わなかった場合の検証方法。
