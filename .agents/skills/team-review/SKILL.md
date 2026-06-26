---
name: team-review
description: Use by a reviewer while supervising an assigned task, or by a manager when handling ASK_MANAGER, to decide feedback, OK, FIX, or escalation from worker evidence and task constraints.
---

# team-review

## Inputs

- `.agents/queue/tasks/<task_id>.md`
- `.agents/queue/reports/<task_id>_<worker_id>.md`
- `.agents/queue/reviews/<task_id>_<reviewer_id>.md`
- `.agents/state/MEMORY.md`
- relevant commits / diffs / files

## Reviewer Handling

- Talk directly with the assigned worker.
- Act as task-local supervisor.
- Answer task-local worker questions first.
- Send `review_feedback` during implementation when correction is useful.
- Ask strategist directly when task-local deep analysis is needed.
- Ask architect directly when task-local design direction is unclear.
- Escalate to manager for scope changes, acceptance changes, cross-task impact, unresolved disagreement, task-external strategy impact, stopped work, repeated evidence gaps, or inability to continue supervising.
- Check acceptance, explicit constraints, changed files, verification evidence, and scope discipline.
- Do not edit project files.
- Write `.agents/queue/reviews/<task_id>_<reviewer_id>.md`.
- Record one decision:
  - `OK`
  - `FIX`
  - `ASK_MANAGER`

```bash
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=<OK|FIX|ASK_MANAGER>
```

`OK` means the task-local work is ready for manager done decision.

Use `review_feedback` for intermediate supervision feedback:

```bash
make team-send FROM=<reviewer_id> TO=<worker_id> TYPE=review_feedback TASK=<task_id> BODY="..."
```

Use strategist for scoped deep analysis:

```bash
make team-send FROM=<reviewer_id> TO=strategist TASK=<task_id> BODY="..."
```

Use architect for scoped design direction:

```bash
make team-send FROM=<reviewer_id> TO=architect TASK=<task_id> BODY="..."
```

## Manager Handling

- For `OK`, confirm report/review evidence, any required architecture note, and `done_recommendation=true`, then mark task state `done`.
- For `FIX`, ensure the worker has a clear next action.
- For `ASK_MANAGER`, decide whether to answer directly, request strategist or architect input, split scope, or escalate to lead.

## Review Criteria

- Task acceptance is satisfied.
- `Allowed paths` and `Do not modify` are respected.
- Verification evidence is concrete and current.
- `make post-change` and `make smoke` results are recorded.
- The worker did not silently change user-visible scope or contract.
- Reviewer feedback, strategy artifacts, and architecture notes are reflected in the report when used.
- Follow-up action is clear.
