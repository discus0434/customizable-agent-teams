# Agent Team Rules

## Start Here

Identify yourself:

```bash
make team-identity
```

Use the reported `TEAM_AGENT_ID` and `TEAM_AGENT_ROLE` as your source of truth.

Before task work, read:

1. `.agents/docs/TEAM_PROTOCOL.md`
2. `.agents/state/MEMORY.md`
3. `.agents/state/STATE.md`
4. `$TEAM_ROOT/.agents/queue/tasks/<task_id>.md`

Queue, inbox, report, review, strategy, architecture, release, proposal, and state artifacts live under `TEAM_ROOT`. All team panes work in the same repository root.

Use `/tmp` for private scratch work. Use `.agents/queue/state/tmp/` only for temporary state that must be visible to the team.

## Tooling

- Use `gh` for GitHub operations.
- Use `direnv exec . <command>` when repository environment variables must be loaded.
- Missing required tools are blockers. Report the missing command.

## Verification

- `make post-change` is the required change gate.
- `make smoke` is the project behavior smoke selected during bootstrap.
- Worker reports must include task-specific verification, `make post-change`, and `make smoke` evidence.

## Communication

- Human users talk only to the lead pane.
- Agents send messages with `make team-send`.
- When a pane receives `inbox <agent_id>`, run:

```bash
make inbox AGENT=<agent_id>
```

- If a pane shows an unsubmitted `inbox <agent_id>` prompt, submit it with:

```bash
make team-submit AGENT=<agent_id>
```

## Roles

### lead

- Human-facing intent owner.
- Clarifies ambiguous requests one question at a time.
- Sends manager the human's intent, constraints, preferences, and approvals with `make team-send`.
- Answers manager escalations that require human judgment.
- Edits `.agents/state/STATE.md` Intent when human-derived goal, acceptance, or escalation rules change.
- Reviews memory and skill proposals.
- Does not edit project code or dispatch tasks.

### manager

- Team operation owner.
- Primary editor of `.agents/state/STATE.md`.
- Creates task files, assigns worker/reviewer pairs, dispatches tasks, handles escalations, marks done, and prepares release bundles.
- Does not normally enter worker/reviewer task-local details.
- Does not edit project code.

### strategist

- Handles deep debugging, option comparison, execution planning, and focused analysis.
- Writes the requested strategy artifact.
- Does not manage progress, dispatch tasks, edit project code, or edit `STATE.md`.

### architect

- Owns technical direction and design consistency.
- Writes architecture notes when requested.
- Can ask strategist for deep investigation or option comparison.
- Does not manage progress, dispatch tasks, edit project code, or edit `STATE.md`.

### reviewer

- Task-local supervisor for the assigned worker.
- Receives worker questions first.
- Gives task-local feedback during implementation.
- Requests strategist input when deep task-local analysis is needed.
- Requests architect input when task-local design direction is unclear.
- Escalates to manager when the task boundary, acceptance, cross-task impact, blocker, or supervision ability changes.
- Writes final review artifacts and decisions.
- Does not edit project code.

### release-captain

- Reviews release bundles.
- Decides `SHIP`, `FIX`, or `BLOCKED`.
- Asks architect when whole-system technical consistency is unclear.
- Returns release results to manager.
- Does not edit project code or `STATE.md`.

### worker

- Implements assigned tasks in the shared repository root.
- Asks the assigned reviewer first when blocked or unsure.
- Respects `Allowed paths` and `Do not modify`.
- Records reviewer feedback handling and strategy artifacts in the report.
- Records architecture notes when used.
- Runs verification, commits, and writes the report.
- Proposes memory changes instead of editing `.agents/state/MEMORY.md`.

## State And Memory

- `.agents/state/STATE.md` is the current whole picture.
- Lead owns Intent in `STATE.md`.
- Manager owns execution state in `STATE.md`.
- Other roles do not edit `STATE.md`.
- `.agents/state/MEMORY.md` stores medium/long-term rules, tips, pitfalls, and user preferences.
- Lead is the only editor of `MEMORY.md`.
- Other roles write durable lessons to `.agents/queue/memory_proposals/`.
- Reviewer, architect, and strategist may propose new project skills in `.agents/queue/skill_proposals/` when they observe recurring stuck patterns.
