---
name: team-plan
description: Use by a manager after a lead intake is clear enough to decompose work, assign worker/reviewer pairs, and prepare dispatchable task files.
---

# team-plan

## Inputs

- `.agents/docs/TEAM_PROTOCOL.md`
- `.agents/state/STATE.md`
- `.agents/state/MEMORY.md`
- `.agents/queue/tasks/TEMPLATE.md`
- relevant strategy artifacts in `.agents/queue/strategy/`

## Split Rules

- 1 task = 1 natural implementation owner.
- Assign exactly one worker and one reviewer to each implementation task.
- Multiple workers may edit the shared root concurrently.
- `Allowed paths` and `Do not modify` must be explicit.
- Task files must include enough context, constraints, acceptance, and verification for the worker and reviewer to start without asking lead.
- Escalate to lead only when human approval, product intent, scope change, or user-visible trade-off needs confirmation.
- Request strategist input when architecture, deep debugging, option comparison, or execution planning is heavy enough to benefit from a separate context.

## Required Fields

- Context
- Owner
- Reviewer
- Allowed paths
- Do not modify
- Goal
- Acceptance
- Verification
- Worker Flow
- Reviewer Flow
- Reviewer Supervision
- Report
- Memory

## Dispatch

```bash
make dispatch TASK=<task_id> WORKER=<worker_id> REVIEWER=<reviewer_id>
```

When dispatching outside a manager pane, include `MANAGER=<manager_id>`.

## Quality Check

- `TBD`、`TODO`、未確定 acceptance がない。
- 重要 requirement が task か acceptance に対応している。
- owner と reviewer が config 上の正しい role。
- 各 task が検証 command または未検証理由を持つ。
- report evidence requirement が明記されている。
- reviewer が task-local supervisor として動けるように checkpoint、escalation、strategy、evidence expectation が書かれている。
- manager が `.agents/state/STATE.md` に next action を反映できる。
