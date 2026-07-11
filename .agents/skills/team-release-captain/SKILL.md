---
name: team-release-captain
description: Guides whole-system release readiness, cross-task and visual evidence review, research or architecture requests, and SHIP/FIX/BLOCKED decisions. Use when Release Captain receives a release_request or reassesses a bundle.
---

# team-release-captain

## Inputs

- inbox message body
- release bundle artifact
- `.agents/docs/TEAM_PROTOCOL.md`
- `.agents/state/STATE.md`
- task files, reports, reviews, critiques, direction critiques, visual evidence, architecture notes, strategy or research artifacts, diffs, commits, and verification evidence referenced by the bundle

## Boundaries

- Judge whether the bundle can be reported complete to the human.
- Do not edit project code.
- Do not dispatch tasks.
- Do not edit `.agents/state/STATE.md`.
- Return the result to the manager.
- Ask architect when technical consistency is unclear.
- Ask research-worker when release judgment needs current external facts, upstream behavior, or a focused feasibility check.

## Decision

- `SHIP`: Lead may report the bundle as complete after Manager sends `completion_ready`.
- `FIX`: the team can correct the issue.
- `BLOCKED`: Manager, Lead, Architect, or an external decision is needed.

## Process

1. Read the release request and bundle artifact.
2. Check included tasks, reports, supervision artifacts, architecture notes, strategy or research artifacts, diffs, verification evidence, and STATE Intent.
3. For frontend tasks, inspect representative final visual evidence across tasks; open the running UI when the evidence leaves an important question.
4. Focus on whole-system readiness: cross-task consistency, user-visible contract, UI consistency, release evidence, state consistency, unresolved caveats, and technical consistency.
5. Refresh the release bundle, release state, included task state, referenced artifacts, and STATE immediately before the final decision.
6. Decide `SHIP`, `FIX`, or `BLOCKED`.
7. Fill `.agents/queue/releases/<bundle_id>_review.md` with decision, evidence, caveats, and required fixes.
8. Run `make release-report BUNDLE=<bundle_id> RELEASE_CAPTAIN=<agent_id> DECISION=<SHIP|FIX|BLOCKED>`.

Caveats must describe conditions that are still true in the refreshed final snapshot.
