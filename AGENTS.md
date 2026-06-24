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
2. `.agents/docs/MEMORY.md`
3. `$TEAM_ROOT/.agents/queue/tasks/<task_id>.md`

Queue, inbox, report, review, and integration artifacts live under `TEAM_ROOT`. All agents start in the same repository root.
Use `/tmp` for private scratch work. Use `.agents/queue/state/tmp/` only when temporary state must be visible to the team. Do not create scratch files in the repository root.

## Tooling

- Use `gh` for GitHub operations such as PR creation, PR status, issue comments, review comments, and CI inspection.
- When repository environment variables must be loaded, run commands through `direnv exec . <command>`.
- Missing required tools are blockers. Report the missing command.

## Verification

- `make post-change` is the required change gate.
- `make smoke` confirms the user-visible behavior selected during bootstrap.

## User Interface

- Human users give project instructions directly in the lead tmux pane.
- Use file mailbox plus tmux nudges for agent-to-agent messages, including lead-to-worker dispatch and worker-to-lead questions.
- When a pane receives `inbox <agent_id>`, run `make inbox AGENT=<agent_id>` and process the unread message body from `TEAM_ROOT`.
- If a pane shows an unsubmitted `inbox <agent_id>` prompt, submit it with `make team-submit AGENT=<agent_id>`.

## Roles

### lead

- Do small, single-agent changes directly.
- Create task files for delegated work.
- Dispatch tasks with `make team-send`.
- Decide worker questions after review.
- Integrate only `done` reports with `OK` reviews.
- Edit `.agents/docs/MEMORY.md` after reviewing memory proposals.

Direct work is allowed when ownership is clear, the change is small, and lead can run the relevant task-specific checks plus:

```bash
make post-change
make smoke
```

Use workers when separate context, review follow-up, or explicit ownership is useful.

### worker

- Read inbox and task file.
- Work in `TEAM_ROOT`; only one implementation task may be active at a time.
- Respect `Allowed paths` and `Do not modify`.
- Run task-specific verification, `make post-change`, and `make smoke`.
- Commit the finished root change before review.
- Fill the report with summary, changed files, verification commands, results, and evidence before review.
- Run noninteractive review and handle the result.
- Report blockers, questions, verification gaps, and memory proposals.
- Submit memory changes as proposals. Lead edits `.agents/docs/MEMORY.md`.

Direct lightweight requests without a task file, such as `TYPE=retro` or `TYPE=note`, do not use commit, review, or integration. Follow the inbox body, write the requested artifact, and mark the message processed.

### verifier

- Runs only through `make review`.
- Reviews task, report, committed diff, and verification evidence.
- Returns `Decision: OK`, `Decision: FIX`, or `Decision: ASK_LEAD`.
- Does not edit files.

## Worker Flow

When lead dispatches `TYPE=task_assigned`, task state is created from the current clean root `HEAD`. Do not start implementation if another implementation task is active.

After implementation:

```bash
make post-change
make smoke
git add <changed-files>
git commit -m "<task_id>: <summary>"
make report TASK=<task_id> AGENT=<agent_id> STATUS=needs-review
# Edit .agents/queue/reports/<task_id>_<agent_id>.md with concrete verification evidence.
make review TASK=<task_id> AGENT=<agent_id>
```

Handle review:

- `OK`: update the report to `done`.
- `FIX`: fix, rerun checks, commit, report `needs-review`, and review again.
- `ASK_LEAD`: write the question in the report and notify lead.

Finish:

```bash
make report TASK=<task_id> AGENT=<agent_id> STATUS=done
make inbox AGENT=<agent_id>
make inbox AGENT=<agent_id> MARK=<message_id>
```

After review, recheck inbox and mark any review notification already handled through the review artifact.

## Lead Integration

Check status:

```bash
make team-status
```

Integrate only tasks shown as `ready-to-integrate`:

```bash
make integrate TASK=<task_id> AGENT=<agent_id>
```

Integration requires:

- report `Status: done`
- review `Decision: OK`
- clean root
- unchanged root `HEAD` since report

`make integrate` records the reviewed root commit, runs `make post-change` and `make smoke`, and writes `.agents/queue/integrations/<task_id>_<agent_id>.md`.

## Memory

- Lead is the only editor of `.agents/docs/MEMORY.md`.
- Workers write durable lessons to `.agents/queue/memory_proposals/`.
- Store only lessons that will change future agent behavior.
