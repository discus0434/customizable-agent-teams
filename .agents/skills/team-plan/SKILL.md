---
name: team-plan
description: Use by a lead after the goal is understood and worker delegation is worthwhile, before creating task files that define owner, acceptance, verification, review, and integration order.
---

# team-plan

## Inputs

- `.agents/docs/TEAM_PROTOCOL.md`
- `.agents/docs/MEMORY.md`
- `.agents/queue/tasks/TEMPLATE.md` if needed

## Split Rules

- 小さい変更は task 化せず lead が直接行う。
- 1 task = 1 natural owner。
- 同じ file を複数 worker が同時に触らない。
- `Allowed paths` と `Do not modify` を必ず書く。
- task file だけで着手できる背景、関連 path、制約を含める。
- acceptance は report だけで判定できる形にする。
- verification は担当 agent が実行可能な command にする。
- worker completion gate として `make post-change`, `make smoke`, `make review` を含める。
- `make review` 前に report へ summary、changed files、verification result/evidence を書く gate を含める。
- dependency / integration order があれば明記する。

## Required Fields

- Context
- Owner
- Allowed paths
- Do not modify
- Goal
- Acceptance
- Verification
- Post-change / smoke / review gate
- Report path
- Report evidence requirement
- Memory proposal policy

## Quality Check

- `TBD`、`TODO`、未確定 acceptance がない。
- 重要 requirement が task か acceptance に対応している。
- ownership が重ならない。
- 各 task が検証 command または未検証理由を持つ。
- report evidence が review 前 gate として明記されている。
- scope が user request と acceptance に対応している。
