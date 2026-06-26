---
name: team-memory
description: Use by a lead agent when .agents/queue/memory_proposals contains proposed medium/long-term rules, tips, pitfalls, or user preferences to merge into .agents/state/MEMORY.md.
---

# team-memory

## Inputs

- `.agents/state/MEMORY.md`
- `.agents/queue/memory_proposals/*.md`
- proposal の source task / report / review / strategy / architecture / release

## Accept

- 次回以降の作業で再利用できる。
- 1 entry 1 lesson。
- source task / report / review / strategy / architecture / release / commit を追える。
- 既存 entry と重複しない。
- 秘密情報、raw log、未検証の推測を含まない。

## Process

```bash
make memory-list
```

1. proposal を読む。
2. `.agents/state/MEMORY.md` を検索して重複や supersede 対象を確認する。
3. 採択する内容だけを整形し、必要なら既存 entry を更新、置換、削除する。
4. 必要なら proposal file に対応済みであることを report に残す。

```bash
make memory-append PROPOSAL=<proposal_file>
```
