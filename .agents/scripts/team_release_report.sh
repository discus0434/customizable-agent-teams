#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_release_report.sh <bundle_id> <release_captain_id> <SHIP|FIX|BLOCKED>" >&2
}

[[ $# -eq 3 ]] || { usage; exit 2; }

bundle_id="$1"
release_captain_id="$2"
decision="$3"

case "$decision" in
  SHIP|FIX|BLOCKED) ;;
  *) die "invalid release decision: $decision" ;;
esac

ensure_team_dirs

state_file="$(team_release_state_file "$bundle_id")"
[[ -f "$state_file" ]] || die_rule \
  "release state not found: $bundle_id" \
  "release-report records a result for an existing release request" \
  "run make release-request BUNDLE=$bundle_id before release-report"

if ! team_config_agent_record "$release_captain_id" >/dev/null; then
  die "unknown release-captain: $release_captain_id"
fi
release_captain_role="$(team_config_agent_field "$release_captain_id" role)"
[[ "$release_captain_role" == "release-captain" ]] || die_rule \
  "release-report agent must be release-captain" \
  "$release_captain_id has role $release_captain_role in $TEAM_CONFIG_FILE" \
  "pass RELEASE_CAPTAIN=<agent_id> for the assigned release-captain"

manager="$(team_release_state_field "$bundle_id" manager)"
assigned_release_captain="$(team_release_state_field "$bundle_id" release_captain)"
bundle_file="$(team_release_state_field "$bundle_id" bundle_artifact)"
review_file="$(team_release_state_field "$bundle_id" review_artifact)"
tasks="$(team_release_state_field "$bundle_id" tasks)"

[[ "$assigned_release_captain" == "$release_captain_id" ]] || die_rule \
  "release-report agent mismatch for $bundle_id" \
  "release state release_captain is $assigned_release_captain, but reporter is $release_captain_id" \
  "report from $assigned_release_captain or create a new release request"
[[ -n "$manager" ]] || die_rule \
  "release state is missing manager for $bundle_id" \
  "release-report must notify the bundle manager" \
  "re-run release-request so manager is recorded"
[[ -n "$bundle_file" && -f "$bundle_file" ]] || die_rule \
  "release bundle artifact is missing for $bundle_id" \
  "release-report needs the bundle artifact as review input" \
  "restore $bundle_file or run release-request again"
[[ -n "$review_file" ]] || die_rule \
  "release state is missing review artifact for $bundle_id" \
  "release-report records .agents/queue/releases/<bundle_id>_review.md" \
  "re-run release-request so the review path is recorded"
[[ -f "$review_file" ]] || die_rule \
  "release review artifact is missing for $bundle_id" \
  "release-report records an existing release-captain review; it does not create the review body" \
  "write $review_file with decision, evidence, caveats, and required fixes, then rerun release-report"
if grep -q '未記入' "$review_file"; then
  die_rule \
    "release review artifact still has unfilled placeholders" \
    "$review_file contains 未記入, so the release evidence is incomplete" \
    "fill the release review evidence and remove placeholder lines before running release-report"
fi

case "$decision" in
  SHIP) status="ship" ;;
  FIX) status="fix" ;;
  BLOCKED) status="blocked" ;;
esac

require_no_placeholders() {
  local label="$1"
  local file="$2"

  if grep -q '未記入' "$file"; then
    die_rule \
      "$label still has unfilled placeholders" \
      "$file contains 未記入, so the release evidence is incomplete" \
      "fill $file with current evidence before recording SHIP"
  fi
}

require_release_task_ready() {
  local task_id="$1"
  local task_state_file
  local task_status
  local review_decision
  local done_recommendation
  local report_file
  local task_review_file
  local architecture_required
  local architecture

  task_state_file="$(team_task_state_file "$task_id")"
  [[ -f "$task_state_file" ]] || die_rule \
    "release task state is missing: $task_id" \
    "SHIP requires every included task to have current machine state" \
    "dispatch, review, and mark $task_id done before including it in $bundle_id"

  task_status="$(team_task_state_field "$task_id" status)"
  review_decision="$(team_task_state_field "$task_id" review_decision)"
  done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
  report_file="$(team_task_state_field "$task_id" report)"
  task_review_file="$(team_task_state_field "$task_id" review)"
  architecture_required="$(team_task_state_field "$task_id" architecture_required)"
  architecture="$(team_task_state_field "$task_id" architecture)"

  [[ "$task_status" == "done" ]] || die_rule \
    "release task is not done: $task_id" \
    "task state has status=$task_status, but SHIP requires status=done" \
    "manager must finish $task_id or remove it from release bundle $bundle_id"
  [[ "$review_decision" == "OK" ]] || die_rule \
    "release task review is not OK: $task_id" \
    "task state has review_decision=$review_decision, but SHIP requires review_decision=OK" \
    "reviewer must record OK before manager includes $task_id in release bundle $bundle_id"
  [[ "$done_recommendation" == "true" ]] || die_rule \
    "release task is not recommended done: $task_id" \
    "task state has done_recommendation=$done_recommendation, but SHIP requires done_recommendation=true" \
    "reviewer must recommend done before manager includes $task_id in release bundle $bundle_id"
  [[ -n "$report_file" && -f "$report_file" ]] || die_rule \
    "release task report is missing: $task_id" \
    "task state points to report=$report_file" \
    "worker must write the report before $task_id is included in release bundle $bundle_id"
  [[ -n "$task_review_file" && -f "$task_review_file" ]] || die_rule \
    "release task review artifact is missing: $task_id" \
    "task state points to review=$task_review_file" \
    "reviewer must write the review artifact before $task_id is included in release bundle $bundle_id"

  if [[ "$architecture_required" == "true" ]]; then
    [[ -n "$architecture" && -f "$TEAM_ROOT/$architecture" ]] || die_rule \
      "release task architecture note is missing: $task_id" \
      "task state has architecture_required=true and architecture=$architecture" \
      "architect must write the recorded architecture note before SHIP"
  fi
}

if [[ "$decision" == "SHIP" ]]; then
  require_no_placeholders "release bundle artifact" "$bundle_file"
  [[ -n "$tasks" ]] || die_rule \
    "release bundle has no tasks: $bundle_id" \
    "SHIP requires at least one included task in release state" \
    "create the release request with TASKS='<task ids>'"

  for task_id in $tasks; do
    require_release_task_ready "$task_id"
  done
fi

team_update_markdown_field "$review_file" "Decision" "$decision"
team_update_markdown_field "$review_file" "Bundle" "$bundle_file"
team_update_markdown_field "$review_file" "Manager" "$manager"
team_update_markdown_field "$review_file" "Release captain" "$release_captain_id"

team_update_markdown_field "$bundle_file" "Status" "$status"
team_update_markdown_field "$bundle_file" "Decision" "$decision"

team_write_release_state \
  "$bundle_id" \
  "$manager" \
  "$release_captain_id" \
  "$status" \
  "$decision" \
  "$bundle_file" \
  "$review_file" \
  "$tasks"

message="Release Decision: $decision. $review_file を確認してください。SHIP の場合、Manager が内容を確認して Lead に completion_ready を送ってください。"
team_send_with_body_file "$release_captain_id" release_result "" "$bundle_id" "$manager" "$message" >/dev/null

team_mark_inbox_processed "$release_captain_id" "" "$bundle_id"

echo "$review_file"
