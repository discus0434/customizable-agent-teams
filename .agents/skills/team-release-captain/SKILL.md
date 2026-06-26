---
name: team-release-captain
description: Use by a release captain when receiving a release request, reviewing a release bundle, deciding SHIP/FIX/BLOCKED, or checking whole-system readiness before lead completion.
---

# team-release-captain

## Inputs

- inbox message body
- release bundle artifact
- `.agents/docs/TEAM_PROTOCOL.md`
- `.agents/state/STATE.md`
- task files, reports, reviews, architecture notes, strategy artifacts, diffs, commits, and verification evidence referenced by the bundle

## Boundaries

- Judge whether the bundle can be reported complete to the human.
- Do not edit project code.
- Do not dispatch tasks.
- Do not edit `.agents/state/STATE.md`.
- Return the result to the manager.
- Ask architect when technical consistency is unclear.

## Decision

- `SHIP`: Lead may report the bundle as complete after Manager sends `completion_ready`.
- `FIX`: the team can correct the issue.
- `BLOCKED`: Manager, Lead, Architect, or an external decision is needed.

## Artifact Shape

```md
# Release Review: <bundle_id>

Decision: SHIP | FIX | BLOCKED
Bundle:
Manager:

## Checked artifacts

## Findings

## Required fixes or blockers

## Ship note
```

## Process

1. Read the release request and bundle artifact.
2. Check included tasks, reports, reviews, architecture notes, strategy artifacts, diffs, verification evidence, and STATE Intent.
3. Check cleanup and stale-reference claims against source/docs/tooling separately from runtime state such as `.agents/queue/` and `.agents/state/STATE.md`.
4. Decide `SHIP`, `FIX`, or `BLOCKED`.
5. Write `.agents/queue/releases/<bundle_id>_review.md`.
6. Run `make release-report BUNDLE=<bundle_id> RELEASE_CAPTAIN=<agent_id> DECISION=<SHIP|FIX|BLOCKED>`.
