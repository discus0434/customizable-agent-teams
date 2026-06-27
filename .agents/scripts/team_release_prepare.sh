#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_release_prepare.sh [--manager <manager_id>] [--release-captain <agent_id>] <bundle_id> <task_id>..." >&2
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
    "manager is required for release-prepare" \
    "release bundles record the manager, but this shell has no TEAM_AGENT_ID" \
    "run release-prepare inside a manager team pane or pass MANAGER=<manager_id>"
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
        "release-prepare needs exactly one release-captain or an explicit RELEASE_CAPTAIN" \
        "add a release-captain to .agents/config/agent-team.yaml or pass RELEASE_CAPTAIN=<agent_id>"
      ;;
    *)
      die_rule \
        "multiple release-captains are configured" \
        "release-prepare cannot infer which release-captain owns this bundle" \
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
  "release-prepare manager must be a manager agent" \
  "$manager_id has role $manager_role in $TEAM_CONFIG_FILE" \
  "run release-prepare from a manager pane or pass MANAGER=<manager_id> for a manager agent"
[[ "$release_captain_role" == "release-captain" ]] || die_rule \
  "release-prepare target must be a release-captain agent" \
  "$release_captain_id has role $release_captain_role in $TEAM_CONFIG_FILE" \
  "pass RELEASE_CAPTAIN=<agent_id> for a release-captain agent"

bundle_file="$(team_release_bundle_file "$bundle_id")"
review_file="$(team_release_review_file "$bundle_id")"
bundle_rel="$(team_relative_path "$bundle_file")"
review_rel="$(team_relative_path "$review_file")"
state_file="$(team_release_state_file "$bundle_id")"

[[ ! -f "$bundle_file" && ! -f "$review_file" && ! -f "$state_file" ]] || die_rule \
  "release bundle already exists: $bundle_id" \
  "release-prepare creates a new bundle draft and does not overwrite an existing release" \
  "edit $bundle_rel, then run make release-request BUNDLE=$bundle_id TASKS='<task ids>'"

tasks=""
task_list_markdown=""
for task_id in "$@"; do
  [[ "$task_id" != */* ]] || die "task_id must not contain '/': $task_id"
  task_file="$TEAM_QUEUE_DIR/tasks/$task_id.md"
  [[ -f "$task_file" ]] || die_rule \
    "release-prepare task file not found: $task_id" \
    "release bundle tasks must exist before release review is prepared" \
    "create .agents/queue/tasks/$task_id.md or remove the task from TASKS"
  team_require_release_task_ready "$bundle_id" "$task_id"
  if [[ -z "$tasks" ]]; then
    tasks="$task_id"
  else
    tasks="$tasks $task_id"
  fi
  task_list_markdown="$task_list_markdown"$'\n'"- $task_id"
done

cat > "$bundle_file" <<BUNDLE
# Release Bundle: $bundle_id

Status: prepared
Manager: $manager_id
Release captain: $release_captain_id
Review: $review_rel
Decision: none

## Goal

<!-- TEAM_PLACEHOLDER: goal -->

## Included tasks
$task_list_markdown

## Evidence summary

<!-- TEAM_PLACEHOLDER: evidence-summary -->

## Known issues

<!-- TEAM_PLACEHOLDER: known-issues -->

## Requested decision

- SHIP / FIX / BLOCKED を判断してください。
BUNDLE

cat > "$review_file" <<REVIEW
# Release Review: $bundle_id

Decision: none
Bundle: $bundle_rel
Manager: $manager_id
Release captain: $release_captain_id

## Decision Summary

<!-- TEAM_PLACEHOLDER: decision-summary -->

## Evidence

<!-- TEAM_PLACEHOLDER: evidence -->

## Caveats

<!-- TEAM_PLACEHOLDER: caveats -->

## Required fixes

<!-- TEAM_PLACEHOLDER: required-fixes -->
REVIEW

acquire_team_lock "release-$bundle_id"
team_write_release_state \
  "$bundle_id" \
  "$manager_id" \
  "$release_captain_id" \
  "prepared" \
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

printf 'bundle=%s\n' "$bundle_rel"
printf 'review=%s\n' "$review_rel"
printf 'state=%s\n' "$state_file"
