---
name: team-strategy
description: Use by a strategist when receiving a strategy_request for deep debugging, architecture design, option comparison, or execution planning.
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
- Write a strategy artifact to `.agents/queue/strategy/<strategy_id>.md`.
- Notify manager with the artifact path and a short summary.

## Artifact Shape

```md
# Strategy: <title>

Source:
Requested by:

## Situation

## Options

## Recommendation

## Execution Plan

## Risks / Unknowns

## Questions For Manager
```

## Process

1. Read the request and current state.
2. Inspect only the relevant repo/docs/scripts.
3. Separate facts, assumptions, trade-offs, and recommendation.
4. Write an artifact that manager can turn into task files.
5. Send manager a `strategy_result` message with the artifact path.
