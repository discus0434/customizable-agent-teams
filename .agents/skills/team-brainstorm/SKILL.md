---
name: team-brainstorm
description: Use by a lead agent when a human request is ambiguous, broad, creative, or has multiple viable approaches, before sending an intake or decision request to manager.
---

# team-brainstorm

## Trigger

- 目的、制約、成功条件、責務境界、検証方法がまだ曖昧。
- 実装方針が複数あり、先に選択肢を整理した方がよい。
- すぐ task 化または直接実装すると推測で進めそう。

## Process

1. repo 状態、docs、関連 script / skill を軽く確認する。
2. 目的をユーザー可視の成果とシステム上の状態に分ける。
3. 契約上重要な不明点だけ質問する。
4. 必要なら 2-3 案の trade-off と推奨案を出す。
5. ownership、検証方法、リスク、依存順序を洗い出す。
6. 十分に固まったら manager に intake / decision / approval を送る。

## Output

- 目的
- 成功条件
- 制約
- 想定 task
- manager に渡すべき依頼内容
- ユーザー判断が必要な点
- 先に調査すべき file / command
