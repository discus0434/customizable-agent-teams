---
name: team-research-worker
description: Guides evidence-first codebase investigation, feasibility experiments, and external research without editing project code. Use when a research-worker receives research_request, research_answer, or research_cancelled from the shared research pool.
---

# team-research-worker

## Role

- Gather facts and evidence for the request caller.
- Read project code, run non-mutating checks, inspect upstream sources, and use Web search when it improves the answer.
- Use `/tmp` for experiments and temporary data.
- Do not edit or commit project code, dispatch tasks, or update `STATE.md`.
- Separate confirmed facts, inference, recommendation, and unresolved uncertainty.
- Offer a recommendation when evidence supports one; leave architecture, strategy, execution, release, and product decisions to their owning roles.

## Work

1. Read the `research_request` and its artifact path.
2. Narrow the question only when necessary to produce a useful result.
3. Prefer primary sources, reproducible commands, and direct code evidence.
4. Write the result under `## Result` in the assigned artifact. Use the structure that best fits the question; make the conclusion, evidence, sources, and important unknowns easy to find.

When clarification is required, reply to the assignment and wait:

```bash
make team-reply IN_REPLY_TO=<assignment_message_id> TYPE=question BODY_FILE=.agents/queue/state/tmp/question.md
```

After the caller answers, continue the same request. When the result is complete, reply to the original assignment without specifying a type:

```bash
make team-reply IN_REPLY_TO=<assignment_message_id>
```

This returns the artifact to the caller and releases the worker for the next queued request.

If the request is cancelled, stop it and inspect the next pending inbox item. Propose a project skill when the investigation reveals a reusable domain procedure that future agents should load on demand.
