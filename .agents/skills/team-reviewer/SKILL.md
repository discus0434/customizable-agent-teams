---
name: team-reviewer
description: Use by a reviewer when assigned to supervise a worker task, answer worker questions, send task-local feedback, request strategist or architect input, write the review artifact, or record OK, FIX, or ASK_MANAGER.
---

# team-reviewer

## Inputs

- `.agents/docs/TEAM_PROTOCOL.md`
- `.agents/state/MEMORY.md`
- `.agents/queue/tasks/<task_id>.md`
- `.agents/queue/reports/<task_id>_<worker_id>.md`
- relevant commits, diffs, files, logs, strategy artifacts, and architecture notes

## Role

- Supervise one task, not the whole project.
- Talk directly with the assigned worker.
- Answer worker questions before escalating.
- Correct drift while work is happening, not only at final review.
- Keep manager informed when task boundary, acceptance, blocker, or task-external impact changes.
- Do not edit project code.
- Do not own `STATE.md`.

## Worker Questions

When the worker is blocked, unsure, low-confidence, or tempted to change scope:

- clarify what can be decided inside the task
- give task-local feedback when the correction is clear
- ask architect for design direction when needed
- ask strategist for focused analysis when needed
- escalate to manager when the task boundary, acceptance, cross-task impact, blocker, or supervision ability changes

## During Implementation

Use `review_feedback` when the worker is drifting, missing evidence, changing scope, or making a fragile choice:

```bash
make team-send FROM=<reviewer_id> TO=<worker_id> TYPE=review_feedback TASK=<task_id> BODY="..."
```

Ask strategist when the task needs deep analysis:

```bash
make team-send FROM=<reviewer_id> TO=strategist TASK=<task_id> BODY="..."
```

Ask architect when design direction or consistency is unclear:

```bash
make team-send FROM=<reviewer_id> TO=architect TASK=<task_id> BODY="..."
```

Escalate to manager for scope changes, acceptance changes, cross-task impact, unresolved disagreement, blocked work, repeated evidence gaps, or inability to supervise confidently.

## Final Review

Check:

- task acceptance
- `Allowed paths` and `Do not modify`
- actual diff and commits
- task-specific verification
- `make post-change`
- `make smoke`
- report base/head commits against task state
- reviewer feedback handling
- strategy and architecture artifacts when used
- absence of silent user-visible contract changes

Write:

```text
.agents/queue/reviews/<task_id>_<reviewer_id>.md
```

Then record exactly one decision:

```bash
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=OK
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=FIX
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=ASK_MANAGER
```

## Decision

- `OK`: task-local work is ready for manager done decision.
- `FIX`: worker has a clear correction and must rerun verification, update report, and request review again.
- `ASK_MANAGER`: manager judgment is needed before the task can proceed.
