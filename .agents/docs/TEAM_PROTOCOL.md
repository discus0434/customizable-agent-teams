# Team Protocol

This file is the team map. Role-specific decisions and artifact formats live in `.agents/skills/team-<role>/SKILL.md`.

## Start

```bash
make team-identity
make inbox AGENT=<agent_id>
```

Use the reported identity and `TEAM_ROOT`. `make team-status` shows current implementation tasks, research requests, panes, and inboxes.

## Roles

```text
Human -> Lead -> Manager
                   |-> General Worker + General Reviewer
                   |-> Frontend Worker + Frontend Critic
                   `-> Release Captain

Lead / Manager / Strategist / Architect / Release Captain -> Research Worker pool
General Reviewer / Frontend Critic / Manager / Lead -> Architect or Strategist
```

- General Worker and General Reviewer are fixed one-to-one pairs.
- Frontend Worker and Frontend Critic are a fixed pair.
- An implementation worker holds one task until Manager marks it done.
- Research Workers have no Supervisor and do not edit project code.

## Implementation Tasks

Manager creates a task from `GENERAL_TEMPLATE.md` or `FRONTEND_TEMPLATE.md`, selects `Worker`, then runs:

```bash
make task-lint TASK=<task_id>
make dispatch TASK=<task_id>
```

Dispatch resolves the fixed `Supervisor` from config. The implementation flow is:

```text
task_assigned / supervision_assigned
-> implementation and supervision
-> report + ready_for_supervision
-> Supervisor OK / FIX / ASK_MANAGER
-> Manager done or manager_fix
```

Frontend tasks add a direction step before major UI implementation:

```text
view_direction_ready
-> PROCEED / REVISE / NOT_NEEDED / ASK_MANAGER
-> rendered implementation and visual iteration
-> final critique
```

Common commands:

```bash
make report TASK=<task_id> STATUS=needs_supervision
make direction-report TASK=<task_id> DECISION=<decision>
make supervision-report TASK=<task_id> DECISION=<OK|FIX|ASK_MANAGER>
make state-update TASK=<task_id> STATUS=done
```

## Research

Lead, Manager, Strategist, Architect, and Release Captain request the shared pool with:

```bash
make team-send TO=research-worker BODY_FILE=.agents/queue/state/tmp/research-request.md
```

The request is assigned FIFO to an available Research Worker. Each worker handles one active request. Results return directly to the caller; follow-up work is a new request and may go to any available worker. Queued, active, and waiting requests appear in `make team-status`.

Research Workers may ask their caller a clarification question. The caller may cancel its own request by replying to the request id with `TYPE=cancel`.

## Specialists And Escalation

Implementation Workers ask their fixed Supervisor first. Supervisors handle task-local questions and escalate task boundary, acceptance, cross-task impact, or unresolved blockers to Manager.

```bash
make team-send TO=strategist TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/strategy-request.md
make team-send TO=architect TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/architecture-request.md
```

Manager escalates human-facing decisions to Lead. Lead talks to the human and returns a decision.

## Release

Manager bundles done tasks:

```bash
make release-prepare BUNDLE=<bundle_id> TASKS="T-001 T-002"
make release-request BUNDLE=<bundle_id> TASKS="T-001 T-002"
```

Release Captain checks whole-system consistency, including representative visual evidence for frontend tasks, and records `SHIP`, `FIX`, or `BLOCKED`. After `SHIP`, Manager sends `completion_ready`; Lead reports to the human and sends `completion_ack`.

## State And Artifacts

- `STATE.md` contains only current intent, execution, blockers, bundles, and next actions.
- Completed detail belongs in task, report, review or critique, research, architecture, strategy, and release artifacts.
- `MEMORY.md` contains reusable medium/long-term knowledge, not progress.

| Path | Purpose |
| --- | --- |
| `.agents/queue/tasks/` | implementation contracts and templates |
| `.agents/queue/reports/` | implementation evidence |
| `.agents/queue/reviews/` | General Reviewer decisions |
| `.agents/queue/direction-critiques/` | frontend direction decisions |
| `.agents/queue/critiques/` | final frontend decisions |
| `.agents/queue/visuals/` | shared rendered evidence |
| `.agents/queue/research/` | research requests and results |
| `.agents/queue/strategy/` | Strategist artifacts |
| `.agents/queue/architecture/` | Architect notes |
| `.agents/queue/releases/` | release bundles and decisions |
| `.agents/queue/memory_proposals/` | proposed durable memory |
| `.agents/queue/skill_proposals/` | proposed project skills |
