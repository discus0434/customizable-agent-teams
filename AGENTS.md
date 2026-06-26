# Agent Team Rules

## Identify

```bash
make team-identity
```

Primary identity:

- `TEAM_AGENT_ID`
- `TEAM_AGENT_ROLE`
- `TEAM_AGENT_CLI`
- `TEAM_AGENT_MODEL`
- `TEAM_SESSION`

Read before task work:

1. `.agents/docs/TEAM_PROTOCOL.md`
2. `.agents/state/MEMORY.md`
3. `.agents/state/STATE.md`
4. `$TEAM_ROOT/.agents/queue/tasks/<task_id>.md`

Queue, inbox, report, review, strategy, and machine state artifacts live under `TEAM_ROOT`. All agents start in the same repository root.
Use `/tmp` for private scratch work. Use `.agents/queue/state/tmp/` only when temporary state must be visible to the team.

## Tooling

- Use `gh` for GitHub operations such as PR creation, PR status, issue comments, review comments, and CI inspection.
- When repository environment variables must be loaded, run commands through `direnv exec . <command>`.
- Missing required tools are blockers. Report the missing command.

## Verification

- `make post-change` is the required change gate.
- `make smoke` confirms the user-visible behavior selected during bootstrap.
- Worker reports must include task-specific verification, `make post-change`, and `make smoke` evidence.

## User Interface

- Human users give project instructions only to the lead tmux pane.
- Use file mailbox plus tmux nudges for agent-to-agent messages.
- When a pane receives `inbox <agent_id>`, run `make inbox AGENT=<agent_id>` and process the unread message body from `TEAM_ROOT`.
- If a pane shows an unsubmitted `inbox <agent_id>` prompt, submit it with `make team-submit AGENT=<agent_id>`.

## Roles

### lead

- Human-facing intent owner.
- Clarify ambiguous requests with careful, incremental questions.
- Translate human intent, constraints, preferences, and approvals into requests for manager.
- Answer manager escalations that require human judgment.
- May edit `.agents/state/STATE.md` only for important facts or decisions learned directly from the human.
- Does not edit project code, tests, README, package metadata, or other project-facing files.
- Does not dispatch worker tasks.
- Does not mark tasks done.

### manager

- Team operation owner.
- Primary editor of `.agents/state/STATE.md`.
- Create task files from `.agents/queue/tasks/TEMPLATE.md`.
- Assign one worker and one reviewer per task.
- Dispatch with `make dispatch TASK=<task_id> WORKER=<worker_id> REVIEWER=<reviewer_id>`.
- Track progress, blockers, reports, review results, and next actions.
- Request strategist input when deep investigation, architecture, comparison, or execution planning is needed.
- Mark task state `done` after reviewer `OK` and sufficient report evidence.
- Escalate to lead when human judgment is needed.
- Does not edit project code, tests, README, package metadata, or other project-facing files.

### strategist

- Handles deep bug investigation, architecture design, option comparison, execution planning, and heavy technical analysis.
- Receives `strategy_request` messages from lead or manager.
- Writes strategy artifacts to `.agents/queue/strategy/<strategy_id>.md`.
- Notifies manager after writing a strategy artifact.
- Does not edit project code.
- Does not dispatch tasks.
- Does not edit `.agents/state/STATE.md`.

### reviewer

- Reviews one or more tasks assigned by manager.
- Talks directly with the assigned worker through mailbox messages.
- Helps catch scope drift, weak evidence, bad direction, and implementation quality issues while work is in progress.
- Writes review artifacts to `.agents/queue/reviews/<task_id>_<reviewer_id>.md`.
- Records decisions with `make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=<OK|FIX|ASK_MANAGER>`.
- Does not edit project code, tests, README, package metadata, or other project-facing files.

### worker

- Implements assigned tasks in the shared repository root.
- Multiple workers may edit the shared root concurrently.
- Respect `Allowed paths` and `Do not modify`.
- Ask the assigned reviewer first when blocked or unsure.
- Run task-specific verification, `make post-change`, and `make smoke`.
- Create the implementation commit or commits.
- Fill the report with summary, changed files, verification commands, results, and evidence.
- Submit memory changes as proposals. Lead edits `.agents/state/MEMORY.md`.

## Task Flow

Manager dispatches:

```bash
make dispatch TASK=<task_id> WORKER=<worker_id> REVIEWER=<reviewer_id>
```

Worker implements and reports:

```bash
make post-change
make smoke
git add <changed-files>
git commit -m "<task_id>: <summary>"
make report TASK=<task_id> AGENT=<worker_id> STATUS=needs_review
```

Worker then fills `.agents/queue/reports/<task_id>_<worker_id>.md` with concrete evidence and sends the assigned reviewer `ready_for_review`.

Reviewer decides:

```bash
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=OK
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=FIX
make review-report TASK=<task_id> REVIEWER=<reviewer_id> DECISION=ASK_MANAGER
```

Decision handling:

- `OK`: manager checks the report/review and marks task state `done`.
- `FIX`: worker fixes, reruns checks, commits, updates report, and asks reviewer again.
- `ASK_MANAGER`: manager decides or escalates to lead.

Manager marks done:

```bash
make state-update TASK=<task_id> STATUS=done
```

## State And Memory

- `.agents/state/STATE.md` is the current whole picture.
- Manager is the primary `STATE.md` editor.
- Lead may edit `STATE.md` only for important human-derived facts and decisions.
- Worker, reviewer, and strategist do not edit `STATE.md`.
- `.agents/state/MEMORY.md` stores medium/long-term rules, tips, pitfalls, and user preferences.
- Lead is the only editor of `MEMORY.md`.
- Other roles write durable lessons to `.agents/queue/memory_proposals/`.
