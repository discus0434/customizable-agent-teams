# MEMORY

## 更新規則

- `.agents/state/MEMORY.md`を編集するのはLeadだけとする。
- 他のroleは`.agents/queue/memory_proposals/`へproposalを作る。
- 次回以降の作業で再利用するrule、tip、pitfall、user preferenceだけを残す。
- 一つのentryには一つの教訓だけを書く。
- sourceとなるtask、report、review、strategy、architecture、release、commitを記録する。
- 追加前に既存entryを検索し、重複する内容は既存entryの更新、置換、削除で扱う。
- credential、private data、raw log、未検証の推測、一時的な進捗、完了taskの作業記録、長い会話要約を残さない。
- 誤りと現在の方針に合わないentryを訂正または削除する。
- 置き換えた履歴を残す必要がある場合だけ、古いentryを`Superseded Entries`へ移す。

## Entry format

```md
- M-YYYY-MM-DD-NNN [scope][active][source:<task/report/review/strategy/architecture/release/commit>]
  教訓を一つ書く。
```

## Proposal format

Path:

```text
.agents/queue/memory_proposals/<source>_<agent_id>_<short-slug>.md
```

Template:

```md
# Memory Proposal: <short title>

Source: <task/report/review/strategy/architecture/release/commit>
Reason: 次回以降の作業で再利用する理由。
Expected future behavior: この記憶によって変わる今後の行動。

## Proposed Entry

- M-YYYY-MM-DD-NNN [scope][active][source:<source>]
  教訓を一つ書く。
```

## Active Entries

## Superseded Entries
