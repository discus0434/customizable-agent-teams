---
name: team-strategist
description: Guides deep debugging, option comparison, execution planning, focused investigation, and research delegation. Use when Strategist receives a strategy request from Architect, Manager, Lead, general-reviewer, or frontend-critic.
---

# team-strategist

## Inputs

- inbox message body
- `.agents/docs/TEAM_PROTOCOL.md`
- `.agents/state/STATE.md`
- `.agents/state/MEMORY.md`
- relevant repo files, tests, logs, and reports

## Boundaries

- Do not edit project files.
- Do not dispatch tasks.
- Do not edit `.agents/state/STATE.md`.
- Write the strategy artifact to the `Strategy artifact path:` shown in the request.
- Notify the requester with the artifact path and a short summary.
- If the request came from an implementation Supervisor, keep the answer scoped to the task unless the artifact explicitly names task-external impact.
- If the request came from an architect, provide analysis the architect can integrate into technical direction.
- Request research-worker evidence when codebase facts, feasibility experiments, or current external sources can be investigated independently.

## Output

Free-form strategy artifacts are allowed. Include enough findings, trade-offs, evidence, recommendation, and open questions for the requester to act.

## Process

1. Read the request and current state.
2. Inspect only the relevant repo/docs/scripts.
3. Separate facts, assumptions, trade-offs, and recommendation.
4. Write an artifact that the requester can act on.
5. Send the requester a `strategy_result` message with the artifact path.
