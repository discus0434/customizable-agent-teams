---
name: team-memory
description: Leadが.agents/queue/memory_proposalsにある提案を審査し、中長期に再利用するrule、tip、pitfall、user preferenceの採否を決めてMEMORYを更新または整理するときに使う。
---

# team-memory

## 採択条件

- 次回以降の作業で再利用できる。
- 一つのentryに一つの教訓だけがある。
- sourceとなるtask、report、review、strategy、architecture、release、commitを追跡できる。
- credential、private data、raw log、未検証の推測を含まない。

## 審査

```bash
make memory-list
```

1. proposalとsourceを確認する。
2. `.agents/state/MEMORY.md`を検索し、重複、訂正、削除が必要なentryを確認する。
3. 採択する場合は、proposalの`## Proposed Entry`に一つのentryだけを残す。
4. 新規entryなら`make memory-append PROPOSAL=<proposal_file_or_basename>`で追加する。
5. 既存entryの訂正、置換、削除が必要な場合は、`MEMORY.md`を直接整理してproposalを削除する。

`memory-append`はentryを追加し、proposal fileを削除し、whitespaceを検証する。

`MEMORY.md`を直接編集した場合は、次のcommandを実行する。

```bash
git diff --check -- .agents/state/MEMORY.md
```

新しい内容を追記するだけで済ませず、重複したentryと現在の判断に合わないentryを削除または置換する。
