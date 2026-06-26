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

Queue, inbox, report, review, strategy, and machine state artifacts live under `TEAM_ROOT`. All team panes work in the same repository root.

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
- Agents use file mailbox plus tmux nudges.
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
- Sends manager the human's intent, constraints, preferences, and approvals.
- Answers manager escalations that require human judgment.
- May edit `.agents/state/STATE.md` only for important human-derived facts and decisions.
- Does not edit project code or dispatch tasks.

### manager

- Team operation owner.
- Primary editor of `.agents/state/STATE.md`.
- Creates task files, assigns worker/reviewer pairs, dispatches tasks, handles escalations, and marks done.
- Does not normally enter worker/reviewer task-local details.
- Does not edit project code.

### strategist

- Handles deep debugging, architecture design, option comparison, and execution planning.
- Writes the requested strategy artifact.
- Does not manage progress, dispatch tasks, edit project code, or edit `STATE.md`.

### reviewer

- Task-local supervisor for the assigned worker.
- Receives worker questions first.
- Gives task-local feedback during implementation.
- Requests strategist input when deep task-local analysis is needed.
- Escalates to manager when the task boundary, acceptance, cross-task impact, blocker, or supervision ability changes.
- Writes final review artifacts and decisions.
- Does not edit project code.

### worker

- Implements assigned tasks in the shared repository root.
- Asks the assigned reviewer first when blocked or unsure.
- Respects `Allowed paths` and `Do not modify`.
- Records reviewer feedback handling and strategy artifacts in the report.
- Runs verification, commits, and writes the report.
- Proposes memory changes instead of editing `.agents/state/MEMORY.md`.

## State And Memory

- `.agents/state/STATE.md` is the current whole picture.
- Manager is the primary `STATE.md` editor.
- Lead may edit `STATE.md` only for important human-derived facts and decisions.
- Worker, reviewer, and strategist do not edit `STATE.md`.
- `.agents/state/MEMORY.md` stores medium/long-term rules, tips, pitfalls, and user preferences.
- Lead is the only editor of `MEMORY.md`.
- Other roles write durable lessons to `.agents/queue/memory_proposals/`.
