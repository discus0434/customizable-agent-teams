#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_report.sh <task_id> <agent_id> <done|blocked|needs-review>" >&2
}

[[ $# -eq 3 ]] || { usage; exit 2; }

task_id="$1"
agent_id="$2"
status="$3"

case "$status" in
  done|blocked|needs-review) ;;
  *) die "invalid status: $status" ;;
esac

if ! team_config_agent_record "$agent_id" >/dev/null; then
  die "unknown agent: $agent_id"
fi

ensure_team_dirs
report_file="$TEAM_QUEUE_DIR/reports/${task_id}_${agent_id}.md"
state_file="$(team_task_state_file "$task_id")"
[[ -f "$state_file" ]] || die "task is not assigned: $task_id"

owner="$(team_task_state_field "$task_id" owner)"
current_status="$(team_task_state_field "$task_id" status)"
base_commit="$(team_task_state_field "$task_id" base_commit)"
integration_commit="$(team_task_state_field "$task_id" integration_commit)"
review_file="$(team_task_state_field "$task_id" review)"
integration_file="$(team_task_state_field "$task_id" integration)"
review_decision="$(team_task_state_field "$task_id" review_decision)"

[[ "$owner" == "$agent_id" ]] || die "task $task_id is owned by $owner, not $agent_id"
[[ "$current_status" != "integrated" ]] || die "task $task_id is already integrated"
[[ -n "$base_commit" ]] || die "task $task_id state is missing base_commit"

if [[ "$status" != "blocked" ]] && ! team_git_is_clean "$TEAM_ROOT"; then
  team_git_dirty_summary "$TEAM_ROOT" >&2
  die "team root must be clean before report Status $status"
fi

head_commit="$(git -C "$TEAM_ROOT" rev-parse HEAD)"

if [[ "$status" == "done" && "$review_decision" != "OK" ]]; then
  die "report Status done requires review Decision OK"
fi

if [[ ! -f "$report_file" ]]; then
  cat > "$report_file" <<REPORT
# Report: $task_id by $agent_id

Status: $status
Base commit: $base_commit
Head commit: $head_commit
Review: ${review_file:-none}
Integration: ${integration_file:-none}

## Summary

- 未記入

## Files changed

- 未記入

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

## Review

- Command: make review TASK=$task_id AGENT=$agent_id
- Result: pending
- Evidence: update this section after reading ${review_file:-the review artifact}.

## Integration

- Command: make integrate TASK=$task_id AGENT=$agent_id
- Result: not run by worker
- Evidence: integration is lead-owned after report Status done and review Decision OK.

## Blockers

- 未記入

## Questions for lead

- 未記入

## Memory proposals

- 未記入
REPORT
else
  team_update_markdown_field "$report_file" "Status" "$status"
  team_update_markdown_field "$report_file" "Base commit" "$base_commit"
  team_update_markdown_field "$report_file" "Head commit" "$head_commit"
  team_update_markdown_field "$report_file" "Review" "${review_file:-none}"
  team_update_markdown_field "$report_file" "Integration" "${integration_file:-none}"
fi

team_write_task_state \
  "$task_id" \
  "$agent_id" \
  "$status" \
  "$base_commit" \
  "$head_commit" \
  "$integration_commit" \
  "$report_file" \
  "$review_file" \
  "$integration_file" \
  "$review_decision"

echo "$report_file"
