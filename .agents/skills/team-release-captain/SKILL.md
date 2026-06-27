---
name: team-release-captain
description: Guides release-captain whole-system readiness review and SHIP/FIX/BLOCKED decisions. Use when a release captain receives a release request, reviews a release bundle, or checks completion readiness.
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

## Process

1. Read the release request and bundle artifact.
2. Check included tasks, reports, reviews, architecture notes, strategy artifacts, diffs, verification evidence, and STATE Intent.
3. Refresh the release bundle, release state, included task state, referenced artifacts, and STATE immediately before the final decision.
4. Decide `SHIP`, `FIX`, or `BLOCKED`.
5. Fill `.agents/queue/releases/<bundle_id>_review.md` with decision, evidence, caveats, and required fixes.
6. Run `make release-report BUNDLE=<bundle_id> RELEASE_CAPTAIN=<agent_id> DECISION=<SHIP|FIX|BLOCKED>`.

Caveats must describe conditions that are still true in the refreshed final snapshot.
