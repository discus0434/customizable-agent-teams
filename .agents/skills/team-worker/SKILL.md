---
name: team-worker
description: Guides worker task implementation, reviewer coordination, uncertainty handling, verification evidence, report writing, and review requests. Use when a worker receives a task assignment or ready-to-implement task.
---

# team-worker

## Inputs

- `.agents/docs/TEAM_PROTOCOL.md`
- `.agents/state/MEMORY.md`
- `.agents/queue/tasks/<task_id>.md`
- reviewer feedback, strategy artifacts, and architecture notes relevant to the task

## Role

- Own the implementation for the assigned task.
- Work inside `Allowed paths`, `Do not modify`, acceptance, and verification.
- Coordinate first with the assigned reviewer when blocked, unsure, low-confidence, or tempted to change scope.
- Do not route task-local uncertainty directly to lead, manager, strategist, or architect.
- Do not silently widen user-visible behavior, compatibility behavior, fallback behavior, or file ownership.
- Keep the change easy to review and report.

## Before Editing

- Read the task file and relevant source.
- Identify owner, reviewer, acceptance, verification, allowed paths, and escalation path.
- Ask reviewer before guessing product intent, widening scope, or changing a boundary.
- Ask reviewer to involve architect or strategist when technical direction or analysis is unclear.

## Implementation

- Use `team-tdd` for behavior changes, bug fixes, core logic, adapters, queue/state, or tests when the contract can be expressed first.
- Make the smallest coherent change that satisfies the task, then refactor when it improves clarity without adding behavior.
- Run task-specific checks while working.
- Record reviewer feedback and how it was handled.

## Report And Review

Before reporting, use `team-verify`.

Run:

```bash
make post-change
make smoke
git add <changed-files>
git commit -m "<task_id>: <summary>"
make report TASK=<task_id> AGENT=<worker_id> STATUS=needs_review
```

Fill the report with:

- summary
- changed files
- commit information
- task-specific verification
- `make post-change`
- `make smoke`
- reviewer coordination
- reviewer feedback and response
- strategy or architecture artifacts when used
- blockers, questions, and memory proposals

Then request review:

```bash
make team-send FROM=<worker_id> TO=<reviewer_id> TYPE=ready_for_review TASK=<task_id> BODY="..."
```

If reviewer returns `FIX`, fix, rerun verification, commit, update the report, and request review again.
If reviewer returns `ASK_MANAGER`, wait for manager direction through reviewer or manager message.
