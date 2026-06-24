# Team Protocol

## Artifacts

- `.agents/queue/tasks/<task_id>.md`: task body.
- `.agents/queue/inbox/<agent_id>.jsonl`: agent messages.
- `.agents/queue/reports/<task_id>_<agent_id>.md`: worker report.
- `.agents/queue/reviews/<task_id>_<agent_id>_review.md`: verifier result.
- `.agents/queue/integrations/<task_id>_<agent_id>.md`: lead integration result.
- `.agents/queue/state/tasks/<task_id>.json`: lifecycle state.
- `.agents/queue/state/processed/<agent_id>/<message_id>`: processed inbox marker.

All queue paths are canonical under `TEAM_ROOT`. All lead and worker panes start in the same repository root.
Private scratch files belong in `/tmp`. Team-visible temporary state belongs in `.agents/queue/state/tmp/`. Repository-root scratch files block clean-root dispatch, review, and integration gates.

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

Human users interact with the lead through the lead tmux pane.

Use the lead pane for:

- project requests
- bootstrap conversations
- scope decisions
- integration decisions

Use mailbox plus tmux nudge for:

- lead-to-worker task dispatch
- worker-to-lead questions
- verifier-to-worker review results
- direct lightweight requests that do not require integration

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

## Root Sharing

Implementation tasks run in the shared root checkout. `TYPE=task_assigned` dispatch creates task state and allows only one active implementation task at a time, so workers do not edit the same working tree concurrently.

Clean root is part of the lifecycle contract. Before task dispatch, review, or integration, remove local throwaway files or move them to `/tmp` or `.agents/queue/state/tmp/`.

## Lead Direct Work

Lead may work directly when the change is small, single-owner, and not worth a task/report/review cycle.

Direct work gate:

```bash
make post-change
make smoke
```

Run task-specific checks before `make post-change` when they exist.

## Task Dispatch

Create a task from `.agents/queue/tasks/TEMPLATE.md`.

Required fields:

- `Owner`
- `Allowed paths`
- `Do not modify`
- `Goal`
- `Acceptance`
- `Verification`
- `Report`

Send:

```bash
make team-send TO=<agent_id> TYPE=task_assigned TASK=<task_id>
make team-status
```

For direct lightweight requests without a task file, send `TYPE=note`, `TYPE=retro`, or another explicit type with `TASK=-`. The receiver follows the inbox body and does not commit, review, or integrate unless the body says to create a task.
After writing the requested artifact, the receiver marks the message processed with `make inbox AGENT=<agent_id> MARK=<message_id>`.

## Worker Lifecycle

Dispatch checks:

- task exists.
- `Owner` equals agent id.
- root checkout is clean.
- no other implementation task is active.

Work:

```bash
make post-change
make smoke
git add <changed-files>
git commit -m "<task_id>: <summary>"
make report TASK=<task_id> AGENT=<agent_id> STATUS=needs-review
# Edit .agents/queue/reports/<task_id>_<agent_id>.md with concrete verification evidence.
make review TASK=<task_id> AGENT=<agent_id>
```

The report must include summary, changed files, task-specific verification, `make post-change`, and `make smoke` evidence before review.

Review handling:

- `Decision: OK`: `make report TASK=<task_id> AGENT=<agent_id> STATUS=done`.
- `Decision: FIX`: fix, rerun checks, commit, report `needs-review`, and review again.
- `Decision: ASK_LEAD`: write the question in the report and notify lead.

After review, recheck inbox and mark the verifier notification when the review artifact has already been handled.

Review refuses dirty root state. The review target is the committed diff from task base commit to root `HEAD`. The review prompt embeds the task, report, git status, and committed diff; verifier agents should decide from that evidence.

`team.review.cli` supports:

- `claude`: runs `claude --print`.
- `codex`: runs `codex exec` and writes the final response to the review artifact.

`team.review.timeout_seconds` is required. A timed-out review fails instead of leaving the task in an invisible running state.

## Integration

Lead integrates only tasks shown by `make team-status` as `ready-to-integrate`.

```bash
make integrate TASK=<task_id> AGENT=<agent_id>
```

Integration checks:

- task owner matches the agent.
- report exists and has `Status: done`.
- review exists and has `Decision: OK`.
- root checkout is clean.
- root `HEAD` still equals report/state head commit.

Integration performs:

```bash
make post-change
make smoke
```

Result is written to:

```text
.agents/queue/integrations/<task_id>_<agent_id>.md
```

If checks fail, the task remains unintegrated. Lead fixes the root state or sends a follow-up task to the worker.

## Memory

Workers submit memory proposals. Lead edits `.agents/docs/MEMORY.md`.

Memory proposal path:

```text
.agents/queue/memory_proposals/<task_id>_<agent_id>_<short-slug>.md
```

Lead reviews proposals and edits `.agents/docs/MEMORY.md` only when the lesson is durable, sourced, non-secret, and not a duplicate.
