# Team Protocol

This file is the team map. Role-specific operating detail lives in `.agents/skills/team-<role>/SKILL.md`. The task template lives at `.agents/queue/tasks/TEMPLATE.md`; reports, reviews, releases, and state are created or updated by Make targets.

## Start

```bash
make team-identity
make inbox AGENT=<agent_id>
```

Use `TEAM_AGENT_ID`, `TEAM_AGENT_ROLE`, and `TEAM_ROOT` as the source of truth. Queue, state, report, review, strategy, architecture, release, and proposal artifacts are canonical under `TEAM_ROOT`.

Use `/tmp` for private scratch work. Use `.agents/queue/state/tmp/` only for temporary state that must be visible to the team.

For multi-line or quote-heavy messages, write the body to a file:

```bash
make team-send FROM=<from_id> TO=<to_id> TYPE=<message_type> TASK=<task_id> BODY_FILE=/tmp/message.md
```

If a pane shows an unsubmitted `inbox <agent_id>` prompt:

```bash
make team-submit AGENT=<agent_id>
```

## Roles

| Role | Owns | Detail |
| --- | --- | --- |
| Lead | human intent, acceptance, approvals, human escalation | `.agents/skills/team-lead/SKILL.md` |
| Manager | team operation, task graph, dispatch, done decisions, release bundles, execution state | `.agents/skills/team-manager/SKILL.md` |
| Strategist | focused analysis, deep debugging, option comparison, execution planning | `.agents/skills/team-strategist/SKILL.md` |
| Architect | technical direction and design consistency | `.agents/skills/team-architect/SKILL.md` |
| Reviewer | task-local supervision and review decision | `.agents/skills/team-reviewer/SKILL.md` |
| Release Captain | whole-system release readiness | `.agents/skills/team-release-captain/SKILL.md` |
| Worker | assigned implementation, verification, report | `.agents/skills/team-worker/SKILL.md` |

Project files are edited by workers. Lead, Manager, Strategist, Architect, Reviewer, and Release Captain operate through artifacts and messages unless a task explicitly assigns otherwise.

## Escalation

```text
Worker -> Reviewer -> Manager -> Lead -> Human
```

Side channels:

```text
Reviewer / Manager / Lead -> Architect
Reviewer / Manager / Architect / Lead -> Strategist
Release Captain -> Architect
```

- Worker asks the assigned reviewer first for blockers, uncertainty, low confidence, task boundary questions, or technical doubts.
- Reviewer handles task-local supervision and escalates task boundary, acceptance, blocker, cross-task impact, or supervision problems to Manager.
- Manager escalates only human approval, product intent, user-visible behavior, scope, priority, or trade-off decisions to Lead.
- Lead talks to the human and returns decisions to Manager.

## State And Memory

`.agents/state/STATE.md` is current truth, not a log.

- Lead owns Intent.
- Manager owns execution state.
- Other roles do not edit STATE.
- Keep completed task details in task, report, review, and release artifacts.
- Remove done tasks from Active Tasks.
- Keep Recent Decisions only while they affect current decisions.
- Make Next Actions name the next role and action.
- Compress STATE after task done, release result, or resolved escalation.

`.agents/state/MEMORY.md` stores medium/long-term rules, tips, pitfalls, and user preferences. Lead edits MEMORY after reviewing `.agents/queue/memory_proposals/`. Other roles propose memory changes instead of editing MEMORY.

## Work Sizing

Manager chooses the smallest coordination shape that preserves ownership, review quality, and verification clarity.

- `micro`: fold into the nearest active task, release fix, or manager note.
- `single-task`: use one worker/reviewer pair when the work has one natural owner and one coherent review surface.
- `parallel`: dispatch independent tasks in the same batch when they do not depend on each other's output and have clear file or behavior boundaries.
- `strategy/architecture`: ask Strategist or Architect before decomposition when the missing decision changes the task graph, technical direction, or verification boundary.

Split work when ownership, review perspective, or verification boundary truly differs.

## Lifecycle

Human talks to Lead. Lead sends Manager `intake`, `approval`, or `decision`.

Manager creates tasks from:

```text
.agents/queue/tasks/TEMPLATE.md
```

Manager dispatches:

```bash
make dispatch TASK=<task_id> WORKER=<worker_id> REVIEWER=<reviewer_id>
```

Worker implements, verifies, commits, and reports:

```bash
make post-change
make smoke
git add <changed-files>
git commit -m "<task_id>: <summary>"
make report TASK=<task_id> AGENT=<worker_id> STATUS=needs_review
```

Worker fills the generated report and sends `ready_for_review` to the assigned Reviewer.

Reviewer supervises during implementation with `review_feedback` when useful, then records one decision:

```bash
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=OK
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=FIX
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=ASK_MANAGER
```

Manager marks a task done only after reviewer `OK`, `done_recommendation=true`, sufficient report evidence, and any required architecture note:

```bash
make state-update TASK=<task_id> STATUS=done
```

Manager requests whole-system release review:

```bash
make release-request BUNDLE=<bundle_id> TASKS="T-001 T-002"
```

Release Captain writes the release review and records:

```bash
make release-report BUNDLE=<bundle_id> RELEASE_CAPTAIN=<release_captain_id> DECISION=SHIP
make release-report BUNDLE=<bundle_id> RELEASE_CAPTAIN=<release_captain_id> DECISION=FIX
make release-report BUNDLE=<bundle_id> RELEASE_CAPTAIN=<release_captain_id> DECISION=BLOCKED
```

After `SHIP`, Manager sends Lead `completion_ready` with summary, evidence, release review path, and caveats.

## Specialist Requests

Use `make team-send`; the scripts create artifact paths and notify the relevant Manager when needed.

```bash
make team-send FROM=<requester_id> TO=strategist TASK=<task_id> BODY_FILE=/tmp/strategy-request.md
make team-send FROM=<requester_id> TO=architect TASK=<task_id> BODY_FILE=/tmp/architecture-request.md
make team-send FROM=<requester_id> TO=architect BUNDLE=<bundle_id> BODY_FILE=/tmp/architecture-request.md
```

Workers route specialist needs through the assigned Reviewer.

## Artifacts

| Path | Purpose |
| --- | --- |
| `.agents/state/STATE.md` | current truth |
| `.agents/state/MEMORY.md` | medium/long-term rules, tips, pitfalls, preferences |
| `.agents/queue/tasks/<task_id>.md` | task contract |
| `.agents/queue/inbox/<agent_id>.jsonl` | messages |
| `.agents/queue/reports/<task_id>_<worker_id>.md` | worker report |
| `.agents/queue/reviews/<task_id>_<reviewer_id>.md` | reviewer result |
| `.agents/queue/strategy/*.md` | strategist artifact |
| `.agents/queue/architecture/*.md` | architect note |
| `.agents/queue/releases/<bundle_id>.md` | release bundle |
| `.agents/queue/releases/<bundle_id>_review.md` | release-captain result |
| `.agents/queue/memory_proposals/*.md` | memory proposal |
| `.agents/queue/skill_proposals/*.md` | project skill proposal |
| `.agents/queue/state/tasks/<task_id>.json` | task machine state |
| `.agents/queue/state/releases/<bundle_id>.json` | release machine state |
| `.agents/queue/state/processed/<agent_id>/<message_id>` | processed inbox marker |

Task and release action commands mark related inbox messages processed. Use `make inbox AGENT=<agent_id> MARK=<message_id>` only for lightweight notes that have no task or release command.

## Proposals

Memory proposals describe durable future behavior and are reviewed by Lead.

Skill proposals are for recurring project or domain procedures. Reviewer, Architect, and Strategist may propose them under `.agents/queue/skill_proposals/`; Lead reviews accepted proposals using the agent environment's built-in skill creation guidance.
