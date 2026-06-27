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
release_status="$(team_release_state_field "$bundle_id" status)"

[[ "$assigned_release_captain" == "$release_captain_id" ]] || die_rule \
  "release-report agent mismatch for $bundle_id" \
  "release state release_captain is $assigned_release_captain, but reporter is $release_captain_id" \
  "report from $assigned_release_captain or create a new release request"
[[ "$release_status" == "requested" ]] || die_rule \
  "release is not ready for release-report: $bundle_id" \
  "release state has status=$release_status, but release-report requires status=requested" \
  "manager must run make release-request BUNDLE=$bundle_id TASKS='<task ids>' before release-captain records a decision"
[[ -n "$manager" ]] || die_rule \
  "release state is missing manager for $bundle_id" \
  "release-report must notify the bundle manager" \
  "re-run release-request so manager is recorded"
[[ -n "$bundle_file" && -f "$bundle_file" ]] || die_rule \
  "release bundle artifact is missing for $bundle_id" \
  "release-report needs the bundle artifact as review input" \
  "restore $bundle_file or prepare a new release bundle"
[[ -n "$review_file" ]] || die_rule \
  "release state is missing review artifact for $bundle_id" \
  "release-report records .agents/queue/releases/<bundle_id>_review.md" \
  "prepare a new release bundle so the review path is recorded"
[[ -f "$review_file" ]] || die_rule \
  "release review artifact is missing for $bundle_id" \
  "release-report records an existing release-captain review; it does not create the review body" \
  "write $review_file with decision, evidence, caveats, and required fixes, then rerun release-report"
team_require_no_placeholders "release review artifact" "$review_file"

case "$decision" in
  SHIP) status="ship" ;;
  FIX) status="fix" ;;
  BLOCKED) status="blocked" ;;
esac

if [[ "$decision" == "SHIP" ]]; then
  team_require_no_placeholders "release bundle artifact" "$bundle_file"
  [[ -n "$tasks" ]] || die_rule \
    "release bundle has no tasks: $bundle_id" \
    "SHIP requires at least one included task in release state" \
    "create the release request with TASKS='<task ids>'"

  for task_id in $tasks; do
    team_require_release_task_ready "$bundle_id" "$task_id"
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
