#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_report.sh <task_id> <agent_id> <needs_review|blocked>" >&2
}

[[ $# -eq 3 ]] || { usage; exit 2; }

task_id="$1"
agent_id="$2"
status="$3"

case "$status" in
  needs_review|blocked) ;;
  *) die "invalid report status: $status" ;;
esac

if ! team_config_agent_record "$agent_id" >/dev/null; then
  die "unknown agent: $agent_id"
fi

agent_role="$(team_config_agent_field "$agent_id" role)"
[[ "$agent_role" == "worker" ]] || die "$agent_id is not a worker agent"

ensure_team_dirs
report_file="$TEAM_QUEUE_DIR/reports/${task_id}_${agent_id}.md"
state_file="$(team_task_state_file "$task_id")"
[[ -f "$state_file" ]] || die "task is not dispatched: $task_id"

owner="$(team_task_state_field "$task_id" owner)"
manager="$(team_task_state_field "$task_id" manager)"
reviewer="$(team_task_state_field "$task_id" reviewer)"
base_commit="$(team_task_state_field "$task_id" base_commit)"
review_file="$(team_task_state_field "$task_id" review)"
review_decision="$(team_task_state_field "$task_id" review_decision)"
done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
architecture_required="$(team_task_state_field "$task_id" architecture_required)"
architecture="$(team_task_state_field "$task_id" architecture)"
release_bundle="$(team_task_state_field "$task_id" release_bundle)"

[[ "$owner" == "$agent_id" ]] || die "task $task_id is owned by $owner, not $agent_id"
[[ -n "$manager" ]] || die "task $task_id state is missing manager"
[[ -n "$reviewer" ]] || die "task $task_id state is missing reviewer"
[[ -n "$base_commit" ]] || die "task $task_id state is missing base_commit"

head_commit="$(git -C "$TEAM_ROOT" rev-parse HEAD)"
commits="$(git -C "$TEAM_ROOT" log --oneline "$base_commit..$head_commit" -- 2>/dev/null || true)"

if [[ "$status" == "needs_review" || "$status" == "blocked" ]]; then
  review_file=""
  review_decision=""
  done_recommendation="false"
fi

if [[ ! -f "$report_file" ]]; then
  cat > "$report_file" <<REPORT
# Report: $task_id by $agent_id

Status: $status
Reviewer: $reviewer
Base commit: $base_commit
Head commit: $head_commit
Review: ${review_file:-none}
Review decision: ${review_decision:-none}
Done recommendation: ${done_recommendation:-false}
Architecture required: ${architecture_required:-false}
Architecture: ${architecture:-none}
Release bundle: ${release_bundle:-none}

## Summary

- 未記入

## Files changed

- 未記入

## Commits

$(if [[ -n "$commits" ]]; then printf '%s\n' "$commits" | sed 's/^/- /'; else printf '%s\n' "- none"; fi)

## Verification

- Command:
- Result:
- Evidence:

## Post-change

- Command: make post-change
- Result:
- Evidence:

## Smoke

- Command: make smoke
- Result:
- Evidence:

## Reviewer coordination

- Assigned reviewer: $reviewer
- Ready for review message:

## Reviewer supervision

- Checkpoints:
- Feedback received:
- Feedback response:

## Strategy artifacts

- Artifact path:
- Adoption decision:
- Task-external impact:

## Architecture

- Required: ${architecture_required:-false}
- Artifact path: ${architecture:-none}
- Adoption decision:

## Blockers

- 未記入

## Questions for reviewer

- 未記入

## Escalation for manager

- 未記入

## Memory proposals

- 未記入
REPORT
else
  team_update_markdown_field "$report_file" "Status" "$status"
  team_update_markdown_field "$report_file" "Reviewer" "$reviewer"
  team_update_markdown_field "$report_file" "Base commit" "$base_commit"
  team_update_markdown_field "$report_file" "Head commit" "$head_commit"
  team_update_markdown_field "$report_file" "Review" "${review_file:-none}"
  team_update_markdown_field "$report_file" "Review decision" "${review_decision:-none}"
  team_update_markdown_field "$report_file" "Done recommendation" "${done_recommendation:-false}"
  team_update_markdown_field "$report_file" "Architecture required" "${architecture_required:-false}"
  team_update_markdown_field "$report_file" "Architecture" "${architecture:-none}"
  team_update_markdown_field "$report_file" "Release bundle" "${release_bundle:-none}"
fi

team_write_task_state \
  "$task_id" \
  "$manager" \
  "$agent_id" \
  "$reviewer" \
  "$status" \
  "$base_commit" \
  "$head_commit" \
  "$report_file" \
  "$review_file" \
  "$review_decision" \
  "${done_recommendation:-false}" \
  "${architecture_required:-false}" \
  "$architecture" \
  "$release_bundle"

team_mark_inbox_processed "$agent_id" "$task_id" ""

echo "$report_file"
