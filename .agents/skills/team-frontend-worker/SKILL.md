---
name: team-frontend-worker
description: Guides frontend implementation with an assigned frontend-critic, view-direction review, rendered UI iteration, visual evidence, verification, commits, reports, and final supervision. Use when a frontend-worker receives task_assigned, view_direction_result, supervision_feedback, or manager_fix.
---

# team-frontend-worker

## Role

- Own the frontend surface and directly supporting client-side code in the assigned task.
- Use the fixed frontend-critic as the first contact for direction, visual quality, interaction, accessibility, uncertainty, and scope pressure.
- Split substantive backend, database, domain, or infrastructure changes into a general-worker task through Manager.
- Do not edit `STATE.md` or `MEMORY.md`.

## View Direction

Before major UI implementation, send the critic a concise direction proposal covering information priority, composition, interaction, states, and platform adaptation. Add wireframes, references, or existing screenshots only when they improve the decision.

```bash
make team-send TO=<critic_id> TYPE=view_direction_ready TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/view-direction.md
```

Wait for `PROCEED` or `NOT_NEEDED`. For `REVISE`, update the direction and resubmit. For `ASK_MANAGER`, wait for the resolved task contract.

## Implementation

- Follow the project's Visual Verification guidance in `AGENTS.md` and the task's target states.
- Inspect the rendered result throughout implementation; do not rely on code inspection alone.
- Store shared evidence under `.agents/queue/visuals/<task_id>/`.
- Check representative devices, viewports, windows, states, interaction, accessibility, loading, empty, and error behavior as relevant.
- Send `supervision_checkpoint` when visual or interaction feedback would prevent rework.

## Report

Run task-specific checks, `make post-change`, and `make smoke`, then commit task-owned files and create the report:

```bash
make report TASK=<task_id> STATUS=needs_supervision
```

Fill every placeholder, including direction result, screenshot paths, inspected states, critic feedback, and verification. Send `ready_for_supervision` to the critic. For `FIX` or `manager_fix`, iterate with the same critic and refresh all affected visual evidence before requesting supervision again.
