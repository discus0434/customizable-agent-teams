---
name: team-review
description: Use by a reviewer while assigned to a task, or by a manager when handling ASK_MANAGER, to decide OK, FIX, or escalation from worker evidence and task constraints.
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

## Manager Handling

- For `OK`, confirm report/review evidence is sufficient, then mark task state `done`.
- For `FIX`, ensure the worker has a clear next action.
- For `ASK_MANAGER`, decide whether to answer directly, request strategist input, split scope, or escalate to lead.

## Review Criteria

- Task acceptance is satisfied.
- `Allowed paths` and `Do not modify` are respected.
- Verification evidence is concrete and current.
- `make post-change` and `make smoke` results are recorded.
- The worker did not silently change user-visible scope or contract.
- Follow-up action is clear.
