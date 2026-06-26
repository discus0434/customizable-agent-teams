# Team Protocol

## Artifacts

- `.agents/state/STATE.md`: current whole picture.
- `.agents/state/MEMORY.md`: medium/long-term rules, tips, pitfalls, and user preferences.
- `.agents/queue/tasks/<task_id>.md`: task body.
- `.agents/queue/inbox/<agent_id>.jsonl`: agent messages.
- `.agents/queue/reports/<task_id>_<worker_id>.md`: worker report.
- `.agents/queue/reviews/<task_id>_<reviewer_id>.md`: reviewer result.
- `.agents/queue/strategy/<strategy_id>.md`: strategist artifact.
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
- Marks task state `done` after reviewer `OK` and sufficient report evidence.
- Escalates to lead when human judgment is needed.
- Does not edit project files.

### Strategist

- Receives `strategy_request` messages.
- Writes `.agents/queue/strategy/<strategy_id>.md`.
- Notifies manager with the artifact path.
- Does not edit project files, dispatch tasks, or edit `STATE.md`.

### Reviewer

- Receives `review_watch_assigned`.
- Communicates directly with the assigned worker.
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

Lead or manager may send:

```bash
make team-send FROM=manager TO=strategist TYPE=strategy_request TASK=- BODY="..."
```

Strategist writes:

```text
.agents/queue/strategy/<strategy_id>.md
```

Then strategist notifies manager with the path and a short summary.

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
- `Report`
- `Memory`

Dispatch:

```bash
make dispatch TASK=<task_id> WORKER=<worker_id> REVIEWER=<reviewer_id>
```

Dispatch writes task state with:

- owner
- reviewer
- status `dispatched`
- base commit

Dispatch sends:

- `task_assigned` to worker
- `review_watch_assigned` to reviewer

Multiple workers can work in the shared root at the same time. Manager, task ownership, reviewer coordination, and reports define the working boundary.

Task state status values:

- `dispatched`: manager assigned worker and reviewer.
- `needs_review`: worker report is ready for reviewer.
- `review_fix`: reviewer requested worker changes.
- `review_ask_manager`: reviewer needs manager judgment.
- `review_ok`: reviewer returned `OK`; manager has not marked done yet.
- `done`: manager accepted the report and review.
- `blocked`: task cannot continue without external action.

## Worker Lifecycle

Worker reads the task file and talks to the assigned reviewer when blocked or unsure.

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

- `OK`: report and implementation evidence are sufficient.
- `FIX`: worker must fix and repeat verification/report/review.
- `ASK_MANAGER`: reviewer or worker needs manager judgment.

## Done

Manager marks a task done after reviewer `OK` and sufficient report evidence:

```bash
make state-update TASK=<task_id> STATUS=done
```

Manager also updates `.agents/state/STATE.md` so the whole picture stays current.

The worker commit is the shared-root result. Manager records completion after the review and report are sufficient.

## Memory

Proposal path:

```text
.agents/queue/memory_proposals/<source>_<agent_id>_<short-slug>.md
```

Lead reviews proposals and edits `.agents/state/MEMORY.md` only when the lesson is durable, sourced, non-secret, and not a duplicate.
