# Team Protocol

## Artifacts

- `.agents/state/STATE.md`: current whole picture.
- `.agents/state/MEMORY.md`: medium/long-term rules, tips, pitfalls, and user preferences.
- `.agents/queue/tasks/<task_id>.md`: task body.
- `.agents/queue/inbox/<agent_id>.jsonl`: agent messages.
- `.agents/queue/reports/<task_id>_<worker_id>.md`: worker report.
- `.agents/queue/reviews/<task_id>_<reviewer_id>.md`: reviewer result.
- `.agents/queue/strategy/*.md`: strategist artifact.
- `.agents/queue/state/tasks/<task_id>.json`: machine-readable task lifecycle state.
- `.agents/queue/state/processed/<agent_id>/<message_id>`: processed inbox marker.

All queue paths are canonical under `TEAM_ROOT`. All panes start in the same repository root.
Private scratch files belong in `/tmp`. Team-visible temporary state belongs in `.agents/queue/state/tmp/`.

tmux carries only short nudges:

```text
inbox <agent_id>
```

On receipt, the agent runs:

```bash
make inbox AGENT=<agent_id>
```

If the prompt is visible in a pane but has not submitted, run:

```bash
make team-submit AGENT=<agent_id>
```

## Human To Lead

Human users interact only with the lead pane.

Lead uses that focus for:

- intent clarification
- one-question-at-a-time narrowing
- approval requests
- translating manager escalations into human-facing choices

Lead sends actionable work to manager through the mailbox. Lead does not implement or dispatch.

## Identity

`make team-start` passes identity through environment variables and tmux pane metadata.

```bash
make team-identity
```

Expected fields:

- `TEAM_AGENT_ID`
- `TEAM_AGENT_ROLE`
- `TEAM_AGENT_CLI`
- `TEAM_AGENT_MODEL`
- `TEAM_SESSION`
- `TEAM_ROOT`
- `TEAM_CONFIG_FILE`

## Roles

### Lead

- Sole human-facing role.
- Clarifies ambiguous instructions.
- Sends manager `intake`, `approval`, or `decision` messages.
- May edit `.agents/state/STATE.md` only for important human-derived facts and decisions.
- Does not edit project files.
- Does not dispatch worker tasks.

### Manager

- Owns team operation.
- Primary editor of `.agents/state/STATE.md`.
- Creates task files, assigns worker/reviewer pairs, and dispatches tasks.
- Tracks reports, review decisions, blockers, and next actions.
- Requests strategist input when heavy analysis is useful.
- Intervenes in worker/reviewer pairs only for escalation, blockers, unusual strategy requests, and done decisions.
- Marks task state `done` after reviewer `OK`, `done_recommendation=true`, and sufficient report evidence.
- Escalates to lead when human judgment is needed.
- Does not edit project files.

### Strategist

- Receives strategy requests.
- Writes to the `Strategy artifact path:` in the request body.
- Notifies the requester with the artifact path.
- Does not edit project files, dispatch tasks, or edit `STATE.md`.

### Reviewer

- Receives `review_watch_assigned`.
- Acts as task-local supervisor for the assigned worker.
- Receives worker questions first.
- Sends `review_feedback` during implementation when task-local correction is useful.
- Sends scoped requests directly to strategist when deep task-local analysis is needed.
- When reviewer asks strategist, the task manager also receives the request.
- Escalates to manager for task scope changes, acceptance changes, cross-task impact, unresolved worker/reviewer disagreement, task-external strategy impact, stopped work, repeated evidence gaps, or inability to continue supervising.
- Writes `.agents/queue/reviews/<task_id>_<reviewer_id>.md`.
- Records `OK`, `FIX`, or `ASK_MANAGER` with `make review-report`.
- Does not edit project files.

### Worker

- Receives `task_assigned`.
- Implements in shared root.
- May work concurrently with other workers.
- Coordinates first with the assigned reviewer.
- Runs verification, commits, writes report, and asks reviewer for review.

## State And Memory

`STATE.md` is short-lived current state. Manager keeps it current and removes stale completed details.

Recommended shape:

```md
# STATE

## Current Goal

## Active Work

| Task | Owner | Reviewer | Status | Next Action |

## Decisions Needed

## Blockers

## Recent Changes

## Next Actions
```

`MEMORY.md` is medium/long-term agent memory. Lead edits it after reviewing proposals from `.agents/queue/memory_proposals/`.

## Strategy Requests

Lead, manager, or reviewer may send strategy requests.

```bash
make team-send FROM=reviewer-1 TO=strategist TASK=T-001 BODY="..."
```

Rules:

- Send strategist requests to the strategist agent.
- Lead, manager, and reviewer may ask strategist.
- Worker asks the assigned reviewer first.
- Reviewer strategist requests require `TASK=<task_id>`.
- When reviewer asks strategist, the task manager also receives the request.
- The request body includes `Strategy artifact path: <path>`.

Strategist writes:

```text
the path shown after `Strategy artifact path:`
```

Then strategist notifies the requester with the path and a short summary.

## Task Dispatch

Manager creates a task from `.agents/queue/tasks/TEMPLATE.md`.

Required fields:

- `Context`
- `Owner`
- `Reviewer`
- `Allowed paths`
- `Do not modify`
- `Goal`
- `Acceptance`
- `Verification`
- `Worker Flow`
- `Reviewer Flow`
- `Reviewer Supervision`
- `Report`
- `Memory`

Dispatch:

```bash
make dispatch TASK=<task_id> WORKER=<worker_id> REVIEWER=<reviewer_id>
```

Inside a manager pane, dispatch records that pane's `TEAM_AGENT_ID` as task manager.
From a repo shell, pass `MANAGER=<manager_id>`:

```bash
make dispatch MANAGER=manager TASK=<task_id> WORKER=<worker_id> REVIEWER=<reviewer_id>
```

Dispatch writes task state with:

- manager
- owner
- reviewer
- status `dispatched`
- base commit
- done recommendation `false`

Dispatch sends:

- `task_assigned` to worker
- `review_watch_assigned` to reviewer

Multiple workers can work in the shared root at the same time. Manager, task ownership, reviewer coordination, and reports define the working boundary.

Task state status values:

- `dispatched`: manager assigned worker and reviewer.
- `needs_review`: worker report is ready for reviewer.
- `review_fix`: reviewer requested worker changes.
- `review_ask_manager`: reviewer needs manager judgment.
- `review_ok`: reviewer returned `OK` with `done_recommendation=true`; manager has not marked done yet.
- `done`: manager accepted the report and review.
- `blocked`: task cannot continue without external action.

## Worker Lifecycle

Worker reads the task file and talks to the assigned reviewer when blocked or unsure.

Worker sends task-local questions to the assigned reviewer first.
Worker records reviewer feedback handling in the report.

After implementation:

```bash
make post-change
make smoke
git add <changed-files>
git commit -m "<task_id>: <summary>"
make report TASK=<task_id> AGENT=<worker_id> STATUS=needs_review
```

The report must include:

- summary
- changed files
- commit information
- task-specific verification command/result/evidence
- `make post-change` result/evidence
- `make smoke` result/evidence
- reviewer coordination
- reviewer supervision feedback and response
- strategy artifact path, adoption decision, and task-external impact when used
- blockers or questions

Worker sends the assigned reviewer:

```bash
make team-send FROM=<worker_id> TO=<reviewer_id> TYPE=ready_for_review TASK=<task_id> BODY="..."
```

## Reviewer Lifecycle

Reviewer reads:

- task file
- worker report
- relevant diff/commits
- verification evidence
- worker questions or checkpoint messages

Reviewer sends intermediate task-local feedback:

```bash
make team-send FROM=<reviewer_id> TO=<worker_id> TYPE=review_feedback TASK=<task_id> BODY="Observation: ... Required change: ... Evidence expected: ..."
```

The body is free-form. The example shape is a useful default, not a required parser contract.
`review_feedback` is not a final review decision. Worker records how it was handled in the report's `Reviewer supervision` section.

Reviewer may request strategist input directly:

```bash
make team-send FROM=<reviewer_id> TO=strategist TASK=<task_id> BODY="..."
```

Manager receives reviewer strategy requests too. Manager does not approve them first, but may intervene if the request looks wrong for the task or the artifact affects task-external scope.

Reviewer writes:

```text
.agents/queue/reviews/<task_id>_<reviewer_id>.md
```

Then records the decision:

```bash
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=OK
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=FIX
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=ASK_MANAGER
```

Decision meaning:

- `OK`: report and implementation evidence are sufficient; `done_recommendation=true`.
- `FIX`: worker must fix and repeat verification/report/review; `done_recommendation=false`.
- `ASK_MANAGER`: reviewer or worker needs manager judgment.

Final decisions are delivered as `review_result` messages by `make review-report`.

## Done

Manager marks a task done after reviewer `OK`, `done_recommendation=true`, and sufficient report evidence:

```bash
make state-update TASK=<task_id> STATUS=done
```

If a rule is violated, harness scripts print:

```text
error: <message>
reason: <why>
required action: <how to fix>
```

Manager also updates `.agents/state/STATE.md` so the whole picture stays current.

The worker commit is the shared-root result. Manager records completion after the review and report are sufficient.

## Memory

Proposal path:

```text
.agents/queue/memory_proposals/<source>_<agent_id>_<short-slug>.md
```

Lead reviews proposals and edits `.agents/state/MEMORY.md` only when the lesson is durable, sourced, non-secret, and not a duplicate.
