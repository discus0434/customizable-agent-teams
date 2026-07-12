---
name: team-general-worker
description: Guides primary implementation work, fixed general-reviewer coordination, verification evidence, commits, reports, and supervision requests. Use when a general-worker receives task_assigned, supervision_feedback, or manager_fix for an implementation task.
---

# team-general-worker

## Role

- Own substantial implementation inside the assigned task contract.
- Treat the fixed general-reviewer as the first contact for blockers, uncertainty, low confidence, technical doubts, and scope pressure.
- Keep changes inside `Allowed paths` and outside `Do not modify`.
- Do not contact Architect or Strategist directly; ask the supervisor to involve them.
- Do not edit `STATE.md` or `MEMORY.md`.

## Work

1. Read the task, relevant code, current state, and applicable skills.
2. Confirm acceptance, file ownership, verification, and the assigned supervisor.
3. Use `team-tdd` when expected behavior can be expressed before implementation.
4. Implement the coherent solution, run task-specific checks, and keep the supervisor informed at meaningful boundaries.

Share a checkpoint when Reviewer input could still materially change the implementation:

```bash
make team-send TO=<supervisor_id> TYPE=supervision_checkpoint TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/checkpoint.md
```

Use `supervision_feedback` as an action item. Record the feedback and response in the report.

## Report

Before reporting, use `team-verify`, then run the task-specific checks, `make post-change`, and `make smoke`.

Commit the task-owned changes and create the report:

```bash
make task-commit TASK=<task_id> MESSAGE="<summary>"
make report TASK=<task_id> STATUS=needs_supervision
```

Fill every placeholder in the report with concrete commands, results, changed files, task commits, supervision history, and specialist artifacts. Then send:

```bash
make team-send TO=<supervisor_id> TYPE=ready_for_supervision TASK=<task_id> BODY="Report and evidence are ready."
```

For `FIX` or `manager_fix`, coordinate with the same supervisor, correct the work, rerun evidence, commit, update the report, and request supervision again.
