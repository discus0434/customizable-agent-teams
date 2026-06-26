---
name: team-manager
description: Use by a manager when receiving lead intake, maintaining STATE, decomposing work, deciding dependency and parallel dispatch, assigning worker/reviewer pairs, handling escalations, marking tasks done, or preparing release bundles.
---

# team-manager

## Inputs

- `.agents/docs/TEAM_PROTOCOL.md`
- `.agents/state/STATE.md`
- `.agents/state/MEMORY.md`
- `.agents/queue/tasks/TEMPLATE.md`
- relevant strategy artifacts in `.agents/queue/strategy/`
- relevant architecture notes in `.agents/queue/architecture/`

## Operating Bias

- Preserve the human intent from lead.
- Keep `.agents/state/STATE.md` current and short.
- Decompose work into independently reviewable tasks.
- Prefer parallel dispatch when tasks can proceed without waiting for each other's output.
- Do not serialize because a task is uncertain. Add reviewer supervision, request architect input, or request strategist input, then dispatch the bounded task.
- Serialize only when a task needs another task's output, shares a file boundary that cannot be split cleanly, changes the same user-visible contract, or would make verification ambiguous.
- Do not edit project code.

## Work Sizing

Choose the smallest coordination shape that preserves ownership, review quality, and verification clarity.

- `micro`: fold into the nearest active task, release fix, or manager note. Do not create a standalone task for small cleanup, orphan file removal, wording fixes, or bootstrap polish when an existing owner can absorb it.
- `single-task`: use one worker/reviewer pair when the work has one natural owner and one coherent review surface.
- `parallel`: dispatch independent tasks in the same batch when they do not depend on each other's output and have clear file or behavior boundaries.
- `strategy/architecture`: ask strategist or architect before decomposition when the missing decision changes the task graph, technical direction, or verification boundary.

Do not split work just because it feels safer. Split when ownership, review perspective, or verification boundary truly differs.

## Escalation

- Resolve task operation questions yourself when they are about assignment, dependency, status, or evidence.
- Ask architect when technical direction or design consistency needs a named owner.
- Ask strategist when deep debugging, option comparison, or execution planning benefits from separate analysis.
- Escalate to lead only for human approval, product intent, user-visible behavior, scope, priority, or trade-off decisions.
- When reviewer escalates, decide the next owner: worker, reviewer, architect, strategist, release-captain, lead, or blocked.

## Dependency Pass

Before dispatch, write the working dependency shape in `STATE.md`:

- work sizing decision
- task candidates
- dependency edges
- parallel batch
- blocked decisions
- next action

If two tasks are independent enough to have separate owners and reviews, dispatch them in the same batch.

## Task Shape

- 1 task = 1 natural implementation owner.
- Assign exactly one worker and one reviewer to each implementation task.
- Make `Allowed paths` and `Do not modify` explicit.
- Include context, constraints, acceptance, verification, report evidence, reviewer supervision, escalation path, and memory proposal expectations.
- Make the task-local reviewer the worker's first contact for blockers, uncertainty, low confidence, and scope temptation.
- Request architect input when technical direction or design consistency needs a named owner.
- Request strategist input when deep debugging, option comparison, or execution planning benefits from separate analysis.

## Dispatch

```bash
make dispatch TASK=<task_id> WORKER=<worker_id> REVIEWER=<reviewer_id>
```

When dispatching outside a manager pane, include `MANAGER=<manager_id>`.

## Done And Release

- Mark a task `done` only after reviewer `OK`, `done_recommendation=true`, sufficient report evidence, and any required architecture note.
- Prepare a release bundle when a coherent set of done tasks is ready for whole-system review.
- Send `completion_ready` to lead only after release-captain returns `SHIP`.
- Compress `STATE.md` after task done, release result, or resolved escalation.

## Quality Check

- No unresolved `TBD` / `TODO` in task acceptance.
- Every important requirement maps to task acceptance.
- Parallel tasks have clear ownership boundaries.
- Reviewer can supervise without asking manager for task-local context.
- Verification commands or explicit verification gaps are present.
- `STATE.md` shows the current whole picture without stale task logs.
- Completed task details live in task, report, review, and release artifacts, not in `STATE.md`.
