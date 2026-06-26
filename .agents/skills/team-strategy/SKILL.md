---
name: team-strategy
description: Use by a strategist when receiving a strategy request for deep debugging, architecture design, option comparison, or execution planning.
---

# team-strategy

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
- If the request came from a reviewer, keep the answer scoped to the task unless the artifact explicitly names task-external impact.

## Artifact Shape

```md
# Strategy: <title>

Source:
Requested by:
Task:

## Situation

## Options

## Recommendation

## Execution Plan

## Risks / Unknowns

## Task-External Impact

## Questions
```

## Process

1. Read the request and current state.
2. Inspect only the relevant repo/docs/scripts.
3. Separate facts, assumptions, trade-offs, and recommendation.
4. Write an artifact that the requester can act on.
5. Send the requester a `strategy_result` message with the artifact path.
