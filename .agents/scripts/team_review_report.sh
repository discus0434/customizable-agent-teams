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
manager="$(team_task_state_field "$task_id" manager)"
assigned_reviewer="$(team_task_state_field "$task_id" reviewer)"
base_commit="$(team_task_state_field "$task_id" base_commit)"
head_commit="$(team_task_state_field "$task_id" head_commit)"
report_file="$(team_task_state_field "$task_id" report)"

[[ "$assigned_reviewer" == "$reviewer_id" ]] || die "task $task_id reviewer is $assigned_reviewer, not $reviewer_id"
[[ -n "$manager" ]] || die "task $task_id state is missing manager"
[[ -n "$owner" ]] || die "task $task_id state is missing owner"
[[ -n "$base_commit" ]] || die "task $task_id state is missing base_commit"
[[ -n "$head_commit" ]] || die "task $task_id state is missing head_commit; worker must run make report first"
[[ -n "$report_file" && -f "$report_file" ]] || die "report file not found for $task_id: $report_file"

review_file="$TEAM_QUEUE_DIR/reviews/${task_id}_${reviewer_id}.md"
case "$decision" in
  OK)
    done_recommendation="true"
    done_recommendation_text="yes"
    ;;
  FIX|ASK_MANAGER)
    done_recommendation="false"
    done_recommendation_text="no"
    ;;
esac

if [[ ! -f "$review_file" ]]; then
  cat > "$review_file" <<REPORT
# Review: $task_id by $reviewer_id

Decision: $decision
Done recommendation: $done_recommendation_text
Task: $TEAM_QUEUE_DIR/tasks/$task_id.md
Worker: $owner
Report: $report_file
Base commit: $base_commit
Head commit: $head_commit

## Summary

- 未記入

## Supervision Summary

- Worker questions:
- Review feedback sent:
- Strategy requests considered:

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
  team_update_markdown_field "$review_file" "Done recommendation" "$done_recommendation_text"
  team_update_markdown_field "$review_file" "Task" "$TEAM_QUEUE_DIR/tasks/$task_id.md"
  team_update_markdown_field "$review_file" "Worker" "$owner"
  team_update_markdown_field "$review_file" "Report" "$report_file"
  team_update_markdown_field "$review_file" "Base commit" "$base_commit"
  team_update_markdown_field "$review_file" "Head commit" "$head_commit"
fi

case "$decision" in
  OK)
    next_status="review_ok"
    target="$manager"
    message="Review Decision: OK. Done recommendation: yes. $review_file を確認し、global constraints に問題がなければ task を done にしてください。"
    ;;
  FIX)
    next_status="review_fix"
    target="$owner"
    message="Review Decision: FIX. Done recommendation: no. $review_file を確認し、修正、検証、commit、report 更新後に再度 reviewer に ready_for_review を送ってください。"
    ;;
  ASK_MANAGER)
    next_status="review_ask_manager"
    target="$manager"
    message="Review Decision: ASK_MANAGER. Done recommendation: no. $review_file を確認し、判断または Lead への escalation を行ってください。"
    ;;
esac

team_write_task_state \
  "$task_id" \
  "$manager" \
  "$owner" \
  "$reviewer_id" \
  "$next_status" \
  "$base_commit" \
  "$head_commit" \
  "$report_file" \
  "$review_file" \
  "$decision" \
  "$done_recommendation"

"$SCRIPT_DIR/team_send.sh" --from "$reviewer_id" --type review_result --task "$task_id" --done-recommendation "$done_recommendation" "$target" "$message" >/dev/null

echo "$review_file"
