# MEMORY

## Update Rules

- `.agents/state/MEMORY.md` は lead だけが編集する。
- worker / reviewer / strategist は `.agents/queue/memory_proposals/` に proposal を作る。
- 次回以降の作業で再利用できる rules、tips、pitfalls、user preferences だけを残す。
- 1 entry = 1 lesson。
- source task / report / review / strategy / commit を必ず付ける。
- 追加前に既存 entry を検索し、重複する場合は更新または supersede する。
- credential、private data、raw log、未検証の推測、一時的な進捗は書かない。
- 誤りを見つけた場合は訂正し、必要なら old entry を superseded に移す。

## Entry Format

```md
- M-YYYY-MM-DD-NNN [scope][active][source:<task/report/review/strategy/commit>]
  教訓を1つだけ書く。
```

## Proposal Format

Path:

```text
.agents/queue/memory_proposals/<source>_<agent_id>_<short-slug>.md
```

Template:

```md
# Memory Proposal: <short title>

Source: <task/report/review/strategy/commit>
Reason: 次回以降の作業で再利用できるため。

## Proposed Entry

- M-YYYY-MM-DD-NNN [scope][active][source:<source>]
  教訓を1つだけ書く。
```

## Active Entries

## Superseded Entries
