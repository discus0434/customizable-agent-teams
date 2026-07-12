# Agent Team Rules

## Start

```bash
make team-identity
```

Use the reported agent id, role, and team root as the source of truth. Before team work, read:

1. `.agents/docs/TEAM_PROTOCOL.md`
2. `.agents/state/MEMORY.md`
3. `.agents/state/STATE.md`

Implementation workers also read `.agents/queue/tasks/<task_id>.md`.

All panes use the same repository root. Shared artifacts live under `.agents/queue/`. Use `/tmp` for private scratch work and `.agents/queue/state/tmp/` for temporary content another agent must read.

## Tooling And Verification

- Use `gh` for GitHub operations.
- Use `direnv exec . <command>` when repository environment variables are required.
- Missing required tools are blockers; report the exact command.
- `make post-change` is the required change gate.
- `make smoke` checks representative project behavior.
- Implementation reports include task-specific checks, `make post-change`, and `make smoke` evidence.

## Communication

Human users talk only to Lead. Agents communicate with `make team-send` and `make team-reply`.

```bash
make inbox AGENT=<agent_id>
make team-send TO=<agent_id> TYPE=<message_type> TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/message.md
make team-reply IN_REPLY_TO=<message_id> TYPE=<message_type> BODY_FILE=.agents/queue/state/tmp/reply.md
```

- `inbox <agent_id>: 0 pending` means no action is waiting.
- `TYPE=note` is a record and does not enter the attention queue.
- `supervision_assigned` and `supervision_checkpoint` close when read.
- Use `supervision_feedback` when an implementation worker must act.
- Task and release commands close the related action messages.
- Use `MARK=<message_id>` only after handling a pending item that needs no reply.
- Use `make team-status` for current tasks, research work, agent panes, and inboxes.
- If an inbox prompt remains unsubmitted in a pane, run `make team-submit AGENT=<agent_id>`.

Request research without choosing an individual worker:

```bash
make team-send TO=research-worker BODY_FILE=.agents/queue/state/tmp/research-request.md
```

## Ownership

| Role | Owns | Skill |
| --- | --- | --- |
| Lead | human intent, acceptance, approvals, human escalation | `team-lead` |
| Manager | execution, task graph, assignments, STATE, done, release bundles | `team-manager` |
| Strategist | deep focused analysis and option comparison | `team-strategist` |
| Architect | technical direction and design consistency | `team-architect` |
| General Worker | primary implementation | `team-general-worker` |
| Hard Task Worker | difficult implementation and debugging | `team-hard-task-worker` |
| General Reviewer | general-worker and hard-task-worker supervision and final review | `team-general-reviewer` |
| Research Worker | codebase, feasibility, and external evidence | `team-research-worker` |
| Frontend Worker | rendered frontend implementation | `team-frontend-worker` |
| Frontend Critic | view direction and complete frontend supervision | `team-frontend-critic` |
| Release Captain | whole-system readiness | `team-release-captain` |

General Workers, Hard Task Workers, and Frontend Workers edit project code. Research Workers use `/tmp` for experiments and do not edit project code. Supervisors, Lead, Manager, Strategist, Architect, and Release Captain operate through messages and artifacts.

## Escalation

```text
General Worker -> General Reviewer -> Manager -> Lead -> Human
Hard Task Worker -> General Reviewer -> Manager -> Lead -> Human
Frontend Worker -> Frontend Critic -> Manager -> Lead -> Human
```

General Reviewer and Frontend Critic may ask Architect or Strategist. Manager, Lead, Architect, Strategist, and Release Captain may request Research Workers. Manager escalates only human-facing intent, scope, priority, approval, user-visible behavior, or trade-offs to Lead.

## State, Memory, And Skills

- `STATE.md` is current truth, not a log. Lead owns Intent; Manager owns execution state.
- `MEMORY.md` stores medium/long-term rules, tips, pitfalls, and user preferences. Lead is its only editor.
- Any role may write a memory proposal.
- General Reviewer, Frontend Critic, Architect, Strategist, and Research Worker may write project skill proposals for recurring domain procedures.
- Lead reviews memory and skill proposals. Use the agent environment's built-in skill creation guidance when editing skills.
