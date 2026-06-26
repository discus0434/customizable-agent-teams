#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  cat >&2 <<'USAGE'
usage: team_release_request.sh [--manager <manager_id>] [--release-captain <agent_id>] <bundle_id> <task_id>...
USAGE
}

manager_id=""
release_captain_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manager)
      [[ $# -ge 2 ]] || die "--manager requires a value"
      manager_id="$2"
      shift 2
      ;;
    --release-captain)
      [[ $# -ge 2 ]] || die "--release-captain requires a value"
      release_captain_id="$2"
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

if [[ -z "$manager_id" ]]; then
  [[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
    "manager is required for release-request" \
    "release requests record the bundle manager, but this shell has no TEAM_AGENT_ID" \
    "run release-request inside a manager team pane or pass MANAGER=<manager_id>"
  manager_id="$TEAM_AGENT_ID"
fi

if [[ -z "$release_captain_id" ]]; then
  release_captains="$(team_config_role_agent_ids release-captain)"
  release_captain_count="$(printf '%s\n' "$release_captains" | sed '/^$/d' | wc -l | tr -d ' ')"
  case "$release_captain_count" in
    1)
      release_captain_id="$(printf '%s\n' "$release_captains" | sed -n '1p')"
      ;;
    0)
      die_rule \
        "release-captain is not configured" \
        "release-request needs exactly one release-captain or an explicit RELEASE_CAPTAIN" \
        "add a release-captain to .agents/config/agent-team.yaml or pass RELEASE_CAPTAIN=<agent_id>"
      ;;
    *)
      die_rule \
        "multiple release-captains are configured" \
        "release-request cannot infer which release-captain owns this bundle" \
        "pass RELEASE_CAPTAIN=<agent_id>"
      ;;
  esac
fi

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
  "pass RELEASE_CAPTAIN=<agent_id> for a release-captain agent"

tasks=""
task_list_markdown=""
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
  task_list_markdown="$task_list_markdown"$'\n'"- $task_id"
done

bundle_file="$(team_release_bundle_file "$bundle_id")"
review_file="$(team_release_review_file "$bundle_id")"
bundle_rel="$(team_relative_path "$bundle_file")"
review_rel="$(team_relative_path "$review_file")"
state_file="$(team_release_state_file "$bundle_id")"

if [[ ! -f "$bundle_file" ]]; then
  cat > "$bundle_file" <<BUNDLE
# Release Bundle: $bundle_id

Status: requested
Manager: $manager_id
Release captain: $release_captain_id
Review: $review_rel
Decision: none

## Goal

- 未記入

## Included tasks
$task_list_markdown

## Evidence summary

- 未記入

## Known issues

- 未記入

## Requested decision

- SHIP / FIX / BLOCKED を判断してください。
BUNDLE
else
  team_update_markdown_field "$bundle_file" "Status" "requested"
  team_update_markdown_field "$bundle_file" "Manager" "$manager_id"
  team_update_markdown_field "$bundle_file" "Release captain" "$release_captain_id"
  team_update_markdown_field "$bundle_file" "Review" "$review_rel"
fi

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
  task_manager="$(team_task_state_field "$task_id" manager)"
  owner="$(team_task_state_field "$task_id" owner)"
  reviewer="$(team_task_state_field "$task_id" reviewer)"
  status="$(team_task_state_field "$task_id" status)"
  base_commit="$(team_task_state_field "$task_id" base_commit)"
  head_commit="$(team_task_state_field "$task_id" head_commit)"
  report_file="$(team_task_state_field "$task_id" report)"
  task_review_file="$(team_task_state_field "$task_id" review)"
  review_decision="$(team_task_state_field "$task_id" review_decision)"
  done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
  architecture_required="$(team_task_state_field "$task_id" architecture_required)"
  architecture="$(team_task_state_field "$task_id" architecture)"
  team_write_task_state \
    "$task_id" \
    "$task_manager" \
    "$owner" \
    "$reviewer" \
    "$status" \
    "$base_commit" \
    "$head_commit" \
    "$report_file" \
    "$task_review_file" \
    "$review_decision" \
    "$done_recommendation" \
    "$architecture_required" \
    "$architecture" \
    "$bundle_id"
done
release_team_lock

body="Release bundle $bundle_id を確認してください。"
"$SCRIPT_DIR/team_send.sh" --from "$manager_id" --type release_request --bundle "$bundle_id" "$release_captain_id" "$body" >/dev/null

printf 'bundle=%s\n' "$bundle_rel"
printf 'review=%s\n' "$review_rel"
printf 'state=%s\n' "$state_file"
