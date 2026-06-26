# Team Protocol

## Artifacts

- `.agents/state/STATE.md`: current whole picture.
- `.agents/state/MEMORY.md`: medium/long-term rules, tips, pitfalls, and user preferences.
- `.agents/queue/tasks/<task_id>.md`: task body.
- `.agents/queue/inbox/<agent_id>.jsonl`: agent messages.
- `.agents/queue/reports/<task_id>_<worker_id>.md`: worker report.
- `.agents/queue/reviews/<task_id>_<reviewer_id>.md`: reviewer result.
- `.agents/queue/strategy/*.md`: strategist artifact.
- `.agents/queue/architecture/*.md`: architect note.
- `.agents/queue/releases/<bundle_id>.md`: release bundle.
- `.agents/queue/releases/<bundle_id>_review.md`: release-captain result.
- `.agents/queue/skill_proposals/*.md`: project skill proposal.
- `.agents/queue/state/tasks/<task_id>.json`: task state.
- `.agents/queue/state/releases/<bundle_id>.json`: release state.
- `.agents/queue/state/processed/<agent_id>/<message_id>`: processed inbox marker.

All queue paths are canonical under `TEAM_ROOT`. All panes start in the same repository root.
Private scratch files belong in `/tmp`. Team-visible temporary state belongs in `.agents/queue/state/tmp/`.

When a pane receives `inbox <agent_id>`, the agent runs:

```bash
make inbox AGENT=<agent_id>
```

If the prompt is visible in a pane but has not submitted, run:

```bash
make team-submit AGENT=<agent_id>
```

Task and release action commands mark the related inbox messages processed. Use manual `MARK=<message_id>` only for lightweight notes that have no task or release command.

For multi-line or quote-heavy messages, write the body to a file and send:

```bash
make team-send FROM=<from_id> TO=<to_id> TYPE=<message_type> TASK=<task_id> BODY_FILE=/tmp/message.md
```

## Human To Lead

Human users interact only with the lead pane.

Lead uses that focus for:

- intent clarification
- one-question-at-a-time narrowing
- approval requests
- maintaining Goal, Acceptance, and Human escalation rules in `STATE.md`
- translating manager escalations into human-facing choices

Lead sends actionable work to manager with `make team-send`. Lead does not implement or dispatch.
Before sending a follow-up nudge, lead checks `make team-status` and `.agents/state/STATE.md`.

## Escalation

Escalation follows the narrowest role that can decide:

```text
Worker -> Reviewer -> Manager -> Lead -> Human
```

Side channels:

```text
Reviewer / Manager / Lead -> Architect
Reviewer / Manager / Architect / Lead -> Strategist
Release Captain -> Architect
```

Rules:

- Worker asks the assigned reviewer first for blockers, uncertainty, low confidence, task boundary questions, or technical doubts.
- Reviewer answers task-local questions, gives feedback, asks architect or strategist when useful, and escalates to manager when task scope, acceptance, cross-task impact, blocker, or supervision ability changes.
- Manager owns decomposition, dispatch, status, dependency order, done decisions, and release bundle preparation.
- Manager escalates to lead only for human approval, product intent, user-visible behavior, scope, priority, or trade-off decisions.
- Lead talks to the human and returns a decision to manager.
- Architect decisions normally settle technical direction. If a technical direction conflicts with human intent, lead resolves it with the human.
- Strategist artifacts inform the requester. The requester decides how to apply them within that requester's role boundary.
- Release Captain returns `SHIP`, `FIX`, or `BLOCKED` to manager. Manager decides the next owner or escalates to lead when human judgment is needed.

## Identity

`make team-start` provides each pane with an identity.

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

This section is the role boundary map. Role-specific operating detail belongs in `.agents/skills/team-<role>/SKILL.md`; lifecycle commands are defined in the sections below.

### Lead

- Sole human-facing role.
- Owns intent, acceptance, approvals, and human escalation.
- Sends manager `intake`, `approval`, or `decision`.
- Does not edit project files or dispatch worker tasks.

### Manager

- Owns team operation, task graph, dispatch, done decisions, release bundles, and execution state.
- Chooses work sizing before task creation and dispatches independent tasks in the same batch.
- Routes technical uncertainty to architect or strategist; escalates human judgment to lead.
- Does not edit project files.

### Strategist

- Owns focused analysis: deep debugging, option comparison, and execution planning.
- Writes strategy artifacts for the requester.
- Does not edit project files, dispatch tasks, or edit `STATE.md`.

### Architect

- Owns technical direction and design consistency.
- Writes architecture notes and may ask strategist for supporting analysis.
- Does not edit project files, dispatch tasks, manage progress, or edit `STATE.md`.

### Reviewer

- Acts as task-local supervisor for the assigned worker.
- Receives worker questions first and gives task-local feedback.
- Requests strategist or architect input when task-local work needs it.
- Records `OK`, `FIX`, or `ASK_MANAGER`.
- Does not edit project files.

### Release Captain

- Reviews release bundles for whole-system readiness.
- Decides `SHIP`, `FIX`, or `BLOCKED`.
- Asks architect when whole-system technical consistency is unclear.
- Returns release results to manager.
- Does not edit project files, dispatch tasks, manage progress, or edit `STATE.md`.

### Worker

- Implements assigned tasks in shared root.
- Coordinates first with the assigned reviewer when blocked, unsure, low-confidence, or tempted to change scope.
- Runs verification, commits, writes report, and asks reviewer for review.

## State And Memory

`STATE.md` is current truth, not a log. Manager keeps only the information needed for the next decision and removes stale completed details.

Shape:

```md
# STATE

## Intent

### Goal

### Acceptance

### Human escalation rules

## Execution

## Active Tasks

| Task | Owner | Reviewer | Status | Next action |

## Bundles

## Blockers

## Recent Decisions

## Next Actions
```

STATE is not append-only. When updating it:

- remove done tasks from Active Tasks
- keep completed task details in task, report, review, and release artifacts
- keep Recent Decisions only while they affect current decisions
- move durable lessons to memory proposals instead of leaving them in STATE
- make Next Actions name the next role and action
- compress STATE after task done, release result, or resolved escalation

`MEMORY.md` is medium/long-term agent memory. Lead edits it after reviewing proposals from `.agents/queue/memory_proposals/`.

Memory stores medium/long-term behavior rules, user preferences, recurring pitfalls, tips, and project-specific judgment criteria. It does not store current progress, completed task logs, one-off decisions, unverified hypotheses, or long conversation summaries.

## Strategy Requests

Lead, manager, architect, or reviewer may send strategy requests.

```bash
make team-send FROM=reviewer-1 TO=strategist TASK=T-001 BODY="..."
```

Rules:

- Send strategist requests to the strategist agent.
- Lead, manager, architect, and reviewer may ask strategist.
- Worker asks the assigned reviewer first.
- Reviewer strategist requests require `TASK=<task_id>`.
- When reviewer asks strategist, the task manager also receives the request.
- The request body includes `Strategy artifact path: <path>`.

Strategist writes:

```text
the path shown after `Strategy artifact path:`
```

Then strategist notifies the requester with the path and a short summary.

## Architecture Requests

Lead, manager, reviewer, or release-captain may send architecture requests.

```bash
make team-send FROM=reviewer-1 TO=architect TASK=T-001 BODY="..."
```

Rules:

- Worker asks the assigned reviewer first.
- Reviewer architecture requests require `TASK=<task_id>`.
- Release-captain architecture requests require `BUNDLE=<bundle_id>`.
- Reviewer and release-captain architecture requests are visible to the relevant manager.
- The request body includes `Architecture artifact path: <path>`.

Architect writes:

```text
the path shown after `Architecture artifact path:`
```

Then architect notifies the requester with the path and a short summary.

Architecture note shape:

```md
# Architecture: <title>

Source:
Requested by:
Task or bundle:

## Decision

## Rationale

## Constraints

## Affected areas

## Test expectations
```

## Task Dispatch

### Work Sizing

Manager chooses the smallest coordination shape that preserves ownership, review quality, and verification clarity:

- `micro`: fold into the nearest active task, release fix, or manager note. Do not create a standalone task for small cleanup, orphan file removal, wording fixes, or bootstrap polish when an existing owner can absorb it.
- `single-task`: use one worker/reviewer pair when the work has one natural owner and one coherent review surface.
- `parallel`: dispatch independent tasks in the same batch when they do not depend on each other's output and have clear file or behavior boundaries.
- `strategy/architecture`: ask strategist or architect before decomposition when the missing decision changes the task graph, technical direction, or verification boundary.

Do not split work just because it feels safer. Split when ownership, review perspective, or verification boundary truly differs.

Manager creates a task from `.agents/queue/tasks/TEMPLATE.md`.

Required fields:

- `Context`
- `Owner`
- `Reviewer`
- `Architecture required`
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
- architecture required
- architecture note path when one has been requested
- release bundle when assigned

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

Worker reads the task file and talks to the assigned reviewer when blocked, unsure, low-confidence, or tempted to change scope.

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
- architecture note path and adoption decision when used
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

Reviewer may request architect input directly:

```bash
make team-send FROM=<reviewer_id> TO=architect TASK=<task_id> BODY="..."
```

Manager receives reviewer architecture requests too. Manager does not approve them first, but may intervene if the request looks wrong for the task or the note affects task-external scope.

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
`make review-report` also checks that the report's recorded base/head commits match task state.

## Done

Manager marks a task done after reviewer `OK`, `done_recommendation=true`, sufficient report evidence, and any required architecture note:

```bash
make state-update TASK=<task_id> STATUS=done
```

If a rule is violated, commands print:

```text
error: <message>
reason: <why>
required action: <how to fix>
```

Manager also updates `.agents/state/STATE.md` so the whole picture stays current.

The worker commit is the shared-root result. Manager records completion after the review and report are sufficient.

## Release

Manager prepares a release bundle after task-local work is ready for whole-system review.

```bash
make release-request BUNDLE=<bundle_id> TASKS="T-001 T-002"
```

`release-request` creates `.agents/queue/releases/<bundle_id>.md` if it does not already exist, records release state, and notifies release-captain. It checks that listed task files and task states exist. It does not require tasks to be `done`.

Release bundle shape:

```md
# Release Bundle: <bundle_id>

Status:
Manager:
Release captain:
Review:
Decision:

## Goal

## Included tasks

## Evidence summary

## Known issues

## Requested decision
```

Release-captain writes `.agents/queue/releases/<bundle_id>_review.md`, then records:

```bash
make release-report BUNDLE=<bundle_id> RELEASE_CAPTAIN=<release_captain_id> DECISION=SHIP
make release-report BUNDLE=<bundle_id> RELEASE_CAPTAIN=<release_captain_id> DECISION=FIX
make release-report BUNDLE=<bundle_id> RELEASE_CAPTAIN=<release_captain_id> DECISION=BLOCKED
```

Decision meaning:

- `SHIP`: manager may send `completion_ready` to lead.
- `FIX`: team can correct the issue; manager decides the owner.
- `BLOCKED`: manager decides the blocker owner; if human judgment is needed, manager escalates to lead.

Release review shape:

```md
# Release Review: <bundle_id>

Decision: SHIP | FIX | BLOCKED
Bundle:
Manager:

## Checked artifacts

## Findings

## Required fixes or blockers

## Ship note
```

After `SHIP`, manager sends lead:

```bash
make team-send FROM=<manager_id> TO=lead TYPE=completion_ready BODY="..."
```

Include user-facing summary, evidence summary, release review path, and unresolved caveats.
Lead checks memory and skill proposals before reporting completion to the human.

## Memory

Proposal path:

```text
.agents/queue/memory_proposals/<source>_<agent_id>_<short-slug>.md
```

Lead reviews proposals and edits `.agents/state/MEMORY.md` only when the lesson is durable, sourced, non-secret, and not a duplicate.

Proposal includes:

- proposed memory
- reason
- source artifact
- expected future behavior

Lead edits, replaces, or deletes existing memory entries as needed. MEMORY is not append-only.

## Skill Proposals

Proposal path:

```text
.agents/queue/skill_proposals/<source>_<agent_id>_<short-slug>.md
```

Reviewer, architect, and strategist may propose a project skill when they observe the same kind of stuck pattern, rule, or domain procedure recurring.

Proposal includes:

- trigger
- observed stuck pattern
- proposed instruction
- example task

Lead reviews proposals. If accepted, lead uses the agent environment's built-in skill creation guidance and creates or updates the skill under `.agents/skills/`.
