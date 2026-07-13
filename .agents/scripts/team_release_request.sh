#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  cat >&2 <<'USAGE'
usage: team_release_request.sh [--manager <manager_id>] <bundle_id> <task_id>...
USAGE
}

manager_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manager)
      [[ $# -ge 2 ]] || die "--manager requires a value"
      manager_id="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    --*)
      die "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -ge 2 ]] || { usage; exit 2; }

bundle_id="$1"
shift

[[ "$bundle_id" != */* ]] || die "bundle_id must not contain '/': $bundle_id"

ensure_team_dirs
team_config_validate

if [[ -z "$manager_id" ]]; then
  [[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
    "manager is required for release-request" \
    "release requests record the bundle manager, but this shell has no TEAM_AGENT_ID" \
    "run release-request inside a manager team pane or pass MANAGER=<manager_id>"
  manager_id="$TEAM_AGENT_ID"
fi

release_captain_id="$(team_config_role_agent_ids release-captain)"

if ! team_config_agent_record "$manager_id" >/dev/null; then
  die "unknown manager: $manager_id"
fi
if ! team_config_agent_record "$release_captain_id" >/dev/null; then
  die "unknown release-captain: $release_captain_id"
fi

manager_role="$(team_config_agent_field "$manager_id" role)"
release_captain_role="$(team_config_agent_field "$release_captain_id" role)"
[[ "$manager_role" == "manager" ]] || die_rule \
  "release-request manager must be a manager agent" \
  "$manager_id has role $manager_role in $TEAM_CONFIG_FILE" \
  "run release-request from a manager pane or pass MANAGER=<manager_id> for a manager agent"
[[ "$release_captain_role" == "release-captain" ]] || die_rule \
  "release-request target must be a release-captain agent" \
  "$release_captain_id has role $release_captain_role in $TEAM_CONFIG_FILE" \
  "correct the release-captain entry in $TEAM_CONFIG_FILE"

tasks=""
for task_id in "$@"; do
  [[ "$task_id" != */* ]] || die "task_id must not contain '/': $task_id"
  task_file="$TEAM_QUEUE_DIR/tasks/$task_id.md"
  task_state_file="$(team_task_state_file "$task_id")"
  [[ -f "$task_file" ]] || die_rule \
    "release-request task file not found: $task_id" \
    "release bundle tasks must exist before release review is requested" \
    "create .agents/queue/tasks/$task_id.md or remove the task from TASKS"
  [[ -f "$task_state_file" ]] || die_rule \
    "release-request task state not found: $task_id" \
    "release bundle tasks must be dispatched before release review is requested" \
    "dispatch $task_id before including it in a release bundle"
  if [[ -z "$tasks" ]]; then
    tasks="$task_id"
  else
    tasks="$tasks $task_id"
  fi
done

bundle_file="$(team_release_bundle_file "$bundle_id")"
review_file="$(team_release_review_file "$bundle_id")"
bundle_rel="$(team_relative_path "$bundle_file")"
review_rel="$(team_relative_path "$review_file")"
state_file="$(team_release_state_file "$bundle_id")"

[[ -f "$state_file" && -f "$bundle_file" && -f "$review_file" ]] || die_rule \
  "release bundle is not prepared: $bundle_id" \
  "release-request notifies the release-captain only after the release bundle and review draft exist" \
  "run make release-prepare BUNDLE=$bundle_id TASKS='<task ids>', fill $bundle_rel, then rerun make release-request"

state_manager="$(team_release_state_field "$bundle_id" manager)"
state_release_captain="$(team_release_state_field "$bundle_id" release_captain)"
state_tasks="$(team_release_state_field "$bundle_id" tasks)"
[[ "$state_manager" == "$manager_id" ]] || die_rule \
  "release-request manager mismatch for $bundle_id" \
  "release state manager is $state_manager, but sender is $manager_id" \
  "run release-request from $state_manager or prepare a new bundle"
[[ "$state_release_captain" == "$release_captain_id" ]] || die_rule \
  "release-request release-captain mismatch for $bundle_id" \
  "release state release_captain is $state_release_captain, but target is $release_captain_id" \
  "send to $state_release_captain or prepare a new bundle"
[[ "$state_tasks" == "$tasks" ]] || die_rule \
  "release-request task list mismatch for $bundle_id" \
  "release state tasks are '$state_tasks', but request tasks are '$tasks'" \
  "use the same TASKS list or prepare a new bundle"

team_require_no_placeholders "release bundle artifact" "$bundle_file"
for task_id in "$@"; do
  team_require_release_task_ready "$bundle_id" "$task_id"
done

team_update_markdown_field "$bundle_file" "Status" "requested"
team_update_markdown_field "$bundle_file" "Manager" "$manager_id"
team_update_markdown_field "$bundle_file" "Release captain" "$release_captain_id"
team_update_markdown_field "$bundle_file" "Review" "$review_rel"
team_update_markdown_field "$bundle_file" "Decision" "none"

acquire_team_lock "release-$bundle_id"
team_write_release_state \
  "$bundle_id" \
  "$manager_id" \
  "$release_captain_id" \
  "requested" \
  "" \
  "$bundle_file" \
  "$review_file" \
  "$tasks"

for task_id in "$@"; do
  task_owner="$(team_task_state_field "$task_id" owner)"
  worker="$(team_task_state_field "$task_id" worker)"
  supervisor="$(team_task_state_field "$task_id" supervisor)"
  status="$(team_task_state_field "$task_id" status)"
  base_commit="$(team_task_state_field "$task_id" base_commit)"
  task_commits="$(team_task_state_field "$task_id" task_commits)"
  report_file="$(team_task_state_field "$task_id" report)"
  supervision_artifact="$(team_task_state_field "$task_id" supervision_artifact)"
  supervision_decision="$(team_task_state_field "$task_id" supervision_decision)"
  done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
  architecture_required="$(team_task_state_field "$task_id" architecture_required)"
  architecture="$(team_task_state_field "$task_id" architecture)"
  direction_status="$(team_task_state_field "$task_id" direction_status)"
  direction_artifact="$(team_task_state_field "$task_id" direction_artifact)"
  team_write_task_state \
    "$task_id" \
    "$task_owner" \
    "$worker" \
    "$supervisor" \
    "$status" \
    "$base_commit" \
    "$task_commits" \
    "$report_file" \
    "$supervision_artifact" \
    "$supervision_decision" \
    "$done_recommendation" \
    "$architecture_required" \
    "$architecture" \
    "$bundle_id" \
    "$direction_status" \
    "$direction_artifact"
done
release_team_lock

body="Release bundle ${bundle_id}を確認してください。"
team_send_with_body_file "$manager_id" release_request "" "$bundle_id" "$release_captain_id" "$body" >/dev/null

printf 'bundle=%s\n' "$bundle_rel"
printf 'review=%s\n' "$review_rel"
printf 'state=%s\n' "$state_file"
