#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_integrate.sh <task_id> <agent_id>" >&2
}

[[ $# -eq 2 ]] || { usage; exit 2; }

task_id="$1"
agent_id="$2"

[[ "$task_id" != */* ]] || die "task_id must not contain '/': $task_id"
[[ "$agent_id" != */* ]] || die "agent_id must not contain '/': $agent_id"

if ! team_config_agent_record "$agent_id" >/dev/null; then
  die "unknown agent: $agent_id"
fi

agent_role="$(team_config_agent_field "$agent_id" role)"
[[ "$agent_role" == "worker" ]] || die "$agent_id is not a worker agent"

ensure_team_dirs

task_file="$TEAM_QUEUE_DIR/tasks/$task_id.md"
state_file="$(team_task_state_file "$task_id")"
report_file="$TEAM_QUEUE_DIR/reports/${task_id}_${agent_id}.md"

[[ -f "$task_file" ]] || die "task file not found: $task_file"
[[ -f "$state_file" ]] || die "task state not found: $state_file"
[[ -f "$report_file" ]] || die "report file not found: $report_file"

owner="$(team_task_state_field "$task_id" owner)"
status="$(team_task_state_field "$task_id" status)"
base_commit="$(team_task_state_field "$task_id" base_commit)"
head_commit="$(team_task_state_field "$task_id" head_commit)"
previous_integration_commit="$(team_task_state_field "$task_id" integration_commit)"
review_file="$(team_task_state_field "$task_id" review)"
review_decision="$(team_task_state_field "$task_id" review_decision)"

[[ "$owner" == "$agent_id" ]] || die "task $task_id is owned by $owner, not $agent_id"
[[ -n "$base_commit" ]] || die "task $task_id state is missing base_commit"
[[ -n "$head_commit" ]] || die "task $task_id state is missing head_commit"
[[ -n "$review_file" ]] || die "task $task_id state is missing review"
[[ -f "$review_file" ]] || die "review file not found: $review_file"

report_status="$(team_report_field "$report_file" Status)"
[[ "$report_status" == "done" ]] || die "report Status must be done before integration: $report_status"

parsed_review_decision="$(team_review_decision "$review_file")"
[[ "$parsed_review_decision" == "OK" ]] || die "review Decision must be OK before integration: $parsed_review_decision"
[[ "$review_decision" == "OK" ]] || die "task state review_decision must be OK before integration: $review_decision"

if ! team_git_is_clean "$TEAM_ROOT"; then
  team_git_dirty_summary "$TEAM_ROOT" >&2
  die "team root must be clean before integration: $TEAM_ROOT"
fi

actual_head="$(git -C "$TEAM_ROOT" rev-parse HEAD)"
[[ "$actual_head" == "$head_commit" ]] || die "team root HEAD changed after report: state=$head_commit actual=$actual_head"

integration_file="$TEAM_QUEUE_DIR/integrations/${task_id}_${agent_id}.md"
post_change_log="$TEAM_QUEUE_DIR/integrations/${task_id}_${agent_id}_post-change.log"
smoke_log="$TEAM_QUEUE_DIR/integrations/${task_id}_${agent_id}_smoke.log"
integration_commit="${previous_integration_commit:-$actual_head}"

post_change_status=0
smoke_status=0

make -C "$TEAM_ROOT" post-change > "$post_change_log" 2>&1 || post_change_status=$?
if [[ "$post_change_status" -eq 0 ]]; then
  make -C "$TEAM_ROOT" smoke > "$smoke_log" 2>&1 || smoke_status=$?
else
  printf '%s\n' "skipped because make post-change failed" > "$smoke_log"
  smoke_status=125
fi

if [[ "$post_change_status" -eq 0 && "$smoke_status" -eq 0 ]]; then
  integration_status="integrated"
else
  integration_status="integration-failed"
fi

cat > "$integration_file" <<REPORT
# Integration: $task_id by $agent_id

Status: $integration_status
Task base commit: $base_commit
Task head commit: $head_commit
Integration commit: $integration_commit
Report: $report_file
Review: $review_file

## Checks

- Command: make post-change
- Status: $post_change_status
- Log: $post_change_log

- Command: make smoke
- Status: $smoke_status
- Log: $smoke_log
REPORT

team_update_markdown_field "$report_file" "Integration" "$integration_file"
team_write_task_state \
  "$task_id" \
  "$agent_id" \
  "$integration_status" \
  "$base_commit" \
  "$head_commit" \
  "$integration_commit" \
  "$report_file" \
  "$review_file" \
  "$integration_file" \
  "$review_decision"

if [[ "$integration_status" != "integrated" ]]; then
  die "integration checks failed. See $integration_file"
fi

echo "$integration_file"
