#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_review_report.sh <task_id> <reviewer_id> <OK|FIX|ASK_MANAGER>" >&2
}

[[ $# -eq 3 ]] || { usage; exit 2; }

task_id="$1"
reviewer_id="$2"
decision="$3"

case "$decision" in
  OK|FIX|ASK_MANAGER) ;;
  *) die "invalid review decision: $decision" ;;
esac

if ! team_config_agent_record "$reviewer_id" >/dev/null; then
  die "unknown reviewer: $reviewer_id"
fi

reviewer_role="$(team_config_agent_field "$reviewer_id" role)"
[[ "$reviewer_role" == "reviewer" ]] || die "$reviewer_id is not a reviewer agent"

ensure_team_dirs

state_file="$(team_task_state_file "$task_id")"
[[ -f "$state_file" ]] || die "task is not dispatched: $task_id"

owner="$(team_task_state_field "$task_id" owner)"
assigned_reviewer="$(team_task_state_field "$task_id" reviewer)"
base_commit="$(team_task_state_field "$task_id" base_commit)"
head_commit="$(team_task_state_field "$task_id" head_commit)"
report_file="$(team_task_state_field "$task_id" report)"

[[ "$assigned_reviewer" == "$reviewer_id" ]] || die "task $task_id reviewer is $assigned_reviewer, not $reviewer_id"
[[ -n "$owner" ]] || die "task $task_id state is missing owner"
[[ -n "$base_commit" ]] || die "task $task_id state is missing base_commit"
[[ -n "$head_commit" ]] || die "task $task_id state is missing head_commit; worker must run make report first"
[[ -n "$report_file" && -f "$report_file" ]] || die "report file not found for $task_id: $report_file"

review_file="$TEAM_QUEUE_DIR/reviews/${task_id}_${reviewer_id}.md"

if [[ ! -f "$review_file" ]]; then
  cat > "$review_file" <<REPORT
# Review: $task_id by $reviewer_id

Decision: $decision
Task: $TEAM_QUEUE_DIR/tasks/$task_id.md
Worker: $owner
Report: $report_file
Base commit: $base_commit
Head commit: $head_commit

## Summary

- 未記入

## Findings

- Severity: Info
  File/path:
  Issue:
  Required worker action:

## Verification Evidence Reviewed

- 未記入

## Worker Coordination

- 未記入

## Manager Escalation

- 未記入
REPORT
else
  team_update_markdown_field "$review_file" "Decision" "$decision"
  team_update_markdown_field "$review_file" "Task" "$TEAM_QUEUE_DIR/tasks/$task_id.md"
  team_update_markdown_field "$review_file" "Worker" "$owner"
  team_update_markdown_field "$review_file" "Report" "$report_file"
  team_update_markdown_field "$review_file" "Base commit" "$base_commit"
  team_update_markdown_field "$review_file" "Head commit" "$head_commit"
fi

case "$decision" in
  OK)
    next_status="review_ok"
    target="manager"
    message="Review Decision: OK. $review_file を確認し、report evidence が十分なら task を done にしてください。"
    ;;
  FIX)
    next_status="review_fix"
    target="$owner"
    message="Review Decision: FIX. $review_file を確認し、修正、検証、commit、report 更新後に再度 reviewer に ready_for_review を送ってください。"
    ;;
  ASK_MANAGER)
    next_status="review_ask_manager"
    target="manager"
    message="Review Decision: ASK_MANAGER. $review_file を確認し、判断または Lead への escalation を行ってください。"
    ;;
esac

team_write_task_state \
  "$task_id" \
  "$owner" \
  "$reviewer_id" \
  "$next_status" \
  "$base_commit" \
  "$head_commit" \
  "$report_file" \
  "$review_file" \
  "$decision"

"$SCRIPT_DIR/team_send.sh" --from "$reviewer_id" "$target" review_result "$task_id" "$message" >/dev/null

echo "$review_file"
