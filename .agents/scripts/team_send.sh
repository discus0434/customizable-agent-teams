#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_send.sh [--from <agent_id>] [--type <type>] [--task <task_id>] [--bundle <bundle_id>] [--body-file <path>] [--done-recommendation <true|false>] <to> [body...]

examples:
  team_send.sh --from lead --type intake --task - manager "ユーザー依頼の要点..."
  team_send.sh --from manager --type task_assigned --task T-001 worker-1
  team_send.sh --from reviewer-1 --task T-001 strategist "この設計判断を深掘りしてください。"
  team_send.sh --from manager --bundle R-001 release-captain "release bundle を見てください。"
USAGE
}

from=""
type=""
task_id=""
bundle_id=""
body_file=""
done_recommendation=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      [[ $# -ge 2 ]] || die "--from requires a value"
      from="$2"
      shift 2
      ;;
    --type)
      [[ $# -ge 2 ]] || die "--type requires a value"
      type="$2"
      shift 2
      ;;
    --task)
      [[ $# -ge 2 ]] || die "--task requires a value"
      task_id="$2"
      shift 2
      ;;
    --bundle)
      [[ $# -ge 2 ]] || die "--bundle requires a value"
      bundle_id="$2"
      shift 2
      ;;
    --body-file)
      [[ $# -ge 2 ]] || die "--body-file requires a path"
      body_file="$2"
      shift 2
      ;;
    --done-recommendation)
      [[ $# -ge 2 ]] || die "--done-recommendation requires true or false"
      done_recommendation="$2"
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

[[ $# -ge 1 ]] || { usage; exit 2; }

to="$1"
shift
body="${*:-}"

ensure_team_dirs

if ! team_config_agent_record "$to" >/dev/null; then
  die_rule \
    "unknown target agent: $to" \
    "the recipient is not present in $TEAM_CONFIG_FILE" \
    "choose an agent id from .agents/config/agent-team.yaml"
fi

if [[ -z "$from" ]]; then
  [[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
    "sender is unknown" \
    "this shell does not have TEAM_AGENT_ID and --from was not provided" \
    "run inside a team pane or pass --from <agent_id>"
  from="$TEAM_AGENT_ID"
fi

if ! team_config_agent_record "$from" >/dev/null; then
  die_rule \
    "unknown sender agent: $from" \
    "the sender is not present in $TEAM_CONFIG_FILE" \
    "choose an agent id from .agents/config/agent-team.yaml"
fi

from_role="$(team_config_agent_field "$from" role)"
to_role="$(team_config_agent_field "$to" role)"

if [[ -n "$done_recommendation" ]]; then
  case "$done_recommendation" in
    true|false) ;;
    *) die_rule \
      "invalid done recommendation: $done_recommendation" \
      "done recommendation must be true or false" \
      "pass --done-recommendation true or --done-recommendation false" ;;
  esac
fi

if [[ -z "$type" ]]; then
  case "$to_role" in
    strategist)
      type="strategy_request"
      ;;
    architect)
      type="architecture_request"
      ;;
    release-captain)
      type="release_request"
      ;;
    *)
      die_rule \
        "message type is required" \
        "TYPE can be omitted only when sending to strategist, architect, or release-captain" \
        "pass TYPE=<message_type>, or send to one of those roles for a request"
      ;;
  esac
fi

if [[ -n "$body_file" ]]; then
  [[ -z "$body" ]] || die_rule \
    "body and body file were both provided" \
    "message body has two sources, so the delivered text would be ambiguous" \
    "pass either BODY or BODY_FILE, not both"
  [[ -f "$body_file" ]] || die_rule \
    "body file not found: $body_file" \
    "the requested --body-file path does not exist" \
    "write the body file first or pass BODY directly"
  body="$(<"$body_file")"
fi

subtype=""
artifact_path=""
cc_to=""

case "$type" in
  strategy_request)
    [[ "$to_role" == "strategist" ]] || die_rule \
      "strategy_request target must be strategist" \
      "strategy requests are handled only by the strategist role" \
      "send strategy_request to the strategist agent"
    case "$from_role" in
      lead)
        subtype="lead_intake"
        ;;
      manager)
        subtype="manager_planning"
        ;;
      architect)
        subtype="architect_analysis"
        ;;
      reviewer)
        subtype="reviewer_supervision"
        [[ -n "$task_id" && "$task_id" != "-" ]] || die_rule \
          "reviewer strategy_request requires TASK" \
          "reviewer supervision strategy requests must be tied to a dispatched task" \
          "pass TASK=<task_id> for the task being supervised"
        state_file="$(team_task_state_file "$task_id")"
        [[ -f "$state_file" ]] || die_rule \
          "task state not found for reviewer strategy_request: $task_id" \
          "manager CC is resolved from the task state, but the task has not been dispatched" \
          "dispatch the task first, then send the strategy request"
        assigned_reviewer="$(team_task_state_field "$task_id" reviewer)"
        [[ "$assigned_reviewer" == "$from" ]] || die_rule \
          "reviewer is not assigned to task $task_id" \
          "only the task's assigned reviewer may request strategist help for reviewer supervision" \
          "send from $assigned_reviewer or update the task assignment"
        cc_to="$(team_task_state_field "$task_id" manager)"
        [[ -n "$cc_to" ]] || die_rule \
          "task $task_id is missing manager" \
          "reviewer strategy_request CC must go to the task manager recorded at dispatch" \
          "redispatch or repair task state so manager is recorded"
        if ! team_config_agent_record "$cc_to" >/dev/null; then
          die_rule \
            "task $task_id has unknown manager: $cc_to" \
            "reviewer strategy_request CC target is read from task state but is not present in team config" \
            "repair task state or dispatch the task with a configured manager"
        fi
        cc_role="$(team_config_agent_field "$cc_to" role)"
        [[ "$cc_role" == "manager" ]] || die_rule \
          "task $task_id manager is not a manager agent" \
          "$cc_to has role $cc_role in $TEAM_CONFIG_FILE" \
          "repair task state or dispatch the task with a manager agent"
        ;;
      worker)
        die_rule \
          "worker cannot send strategy_request directly" \
          "workers ask their assigned reviewer; reviewer decides whether strategist input is needed" \
          "send a question to the assigned reviewer instead"
        ;;
      *)
        die_rule \
          "role cannot send strategy_request: $from_role" \
          "strategy_request is limited to lead, manager, architect, and reviewer roles" \
          "send through lead, manager, architect, or the assigned reviewer"
        ;;
    esac
    artifact_path="$(team_strategy_artifact_path "$task_id" "$subtype")"
    if [[ -z "$body" ]]; then
      body="Strategy request from $from."
    fi
    body="${body}"$'\n\n'"Strategy artifact path: $artifact_path"
    ;;
  architecture_request)
    [[ "$to_role" == "architect" ]] || die_rule \
      "architecture_request target must be architect" \
      "architecture requests are handled only by the architect role" \
      "send architecture_request to the architect agent"
    case "$from_role" in
      lead)
        subtype="lead_intent"
        ;;
      manager)
        subtype="manager_design"
        ;;
      reviewer)
        subtype="reviewer_supervision"
        [[ -n "$task_id" && "$task_id" != "-" ]] || die_rule \
          "reviewer architecture_request requires TASK" \
          "reviewer architecture requests must be tied to a dispatched task" \
          "pass TASK=<task_id> for the task being supervised"
        state_file="$(team_task_state_file "$task_id")"
        [[ -f "$state_file" ]] || die_rule \
          "task state not found for architecture_request: $task_id" \
          "manager CC is resolved from task state, but the task has not been dispatched" \
          "dispatch the task first, then send the architecture request"
        assigned_reviewer="$(team_task_state_field "$task_id" reviewer)"
        [[ "$assigned_reviewer" == "$from" ]] || die_rule \
          "reviewer is not assigned to task $task_id" \
          "only the task's assigned reviewer may request architect help for reviewer supervision" \
          "send from $assigned_reviewer or update the task assignment"
        cc_to="$(team_task_state_field "$task_id" manager)"
        ;;
      release-captain)
        subtype="release_readiness"
        [[ -n "$bundle_id" && "$bundle_id" != "-" ]] || die_rule \
          "release-captain architecture_request requires BUNDLE" \
          "release readiness architecture requests must be tied to a release bundle" \
          "pass BUNDLE=<bundle_id>"
        release_state_file="$(team_release_state_file "$bundle_id")"
        [[ -f "$release_state_file" ]] || die_rule \
          "release state not found for architecture_request: $bundle_id" \
          "manager CC is resolved from release state, but the release has not been requested" \
          "run make release-request before asking architect from release-captain"
        assigned_release_captain="$(team_release_state_field "$bundle_id" release_captain)"
        [[ "$assigned_release_captain" == "$from" ]] || die_rule \
          "release-captain is not assigned to bundle $bundle_id" \
          "only the bundle's release-captain may request architect help for release readiness" \
          "send from $assigned_release_captain or request release review with the intended release-captain"
        cc_to="$(team_release_state_field "$bundle_id" manager)"
        ;;
      worker)
        die_rule \
          "worker cannot send architecture_request directly" \
          "workers ask their assigned reviewer; reviewer decides whether architect input is needed" \
          "send a question to the assigned reviewer instead"
        ;;
      *)
        die_rule \
          "role cannot send architecture_request: $from_role" \
          "architecture_request is limited to lead, manager, reviewer, and release-captain roles" \
          "send through lead, manager, the assigned reviewer, or release-captain"
        ;;
    esac
    if [[ "$subtype" == "reviewer_supervision" || "$subtype" == "release_readiness" ]]; then
      [[ -n "$cc_to" ]] || die_rule \
        "architecture_request CC target is missing" \
        "reviewer and release-captain architecture requests must also notify the relevant manager" \
        "repair task or release state so manager is recorded"
    fi
    if [[ -n "$cc_to" ]]; then
      if ! team_config_agent_record "$cc_to" >/dev/null; then
        die_rule \
          "architecture_request CC target is unknown: $cc_to" \
          "the resolved manager is not present in team config" \
          "repair task or release state with a configured manager"
      fi
      cc_role="$(team_config_agent_field "$cc_to" role)"
      [[ "$cc_role" == "manager" ]] || die_rule \
        "architecture_request CC target is not a manager agent" \
        "$cc_to has role $cc_role in $TEAM_CONFIG_FILE" \
        "repair task or release state with a manager agent"
    fi
    artifact_path="$(team_architecture_artifact_path "$task_id" "$bundle_id" "$subtype")"
    if [[ -n "$task_id" && "$task_id" != "-" ]]; then
      state_file="$(team_task_state_file "$task_id")"
      [[ -f "$state_file" ]] || die_rule \
        "task state not found for architecture_request: $task_id" \
        "task-scoped architecture requests update task architecture state" \
        "dispatch the task first or omit TASK for a general architecture request"
      manager="$(team_task_state_field "$task_id" manager)"
      owner="$(team_task_state_field "$task_id" owner)"
      reviewer="$(team_task_state_field "$task_id" reviewer)"
      status="$(team_task_state_field "$task_id" status)"
      base_commit="$(team_task_state_field "$task_id" base_commit)"
      head_commit="$(team_task_state_field "$task_id" head_commit)"
      report_file="$(team_task_state_field "$task_id" report)"
      review_file="$(team_task_state_field "$task_id" review)"
      review_decision="$(team_task_state_field "$task_id" review_decision)"
      current_done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
      release_bundle="$(team_task_state_field "$task_id" release_bundle)"
      team_write_task_state \
        "$task_id" \
        "$manager" \
        "$owner" \
        "$reviewer" \
        "$status" \
        "$base_commit" \
        "$head_commit" \
        "$report_file" \
        "$review_file" \
        "$review_decision" \
        "$current_done_recommendation" \
        "true" \
        "$artifact_path" \
        "$release_bundle"
    fi
    if [[ -z "$body" ]]; then
      body="Architecture request from $from."
    fi
    body="${body}"$'\n\n'"Architecture artifact path: $artifact_path"
    ;;
  architecture_result)
    [[ "$from_role" == "architect" ]] || die_rule \
      "architecture_result sender must be architect" \
      "architecture results are written by the architect role" \
      "send architecture_result from architect"
    case "$to_role" in
      lead|manager)
        ;;
      reviewer)
        [[ -n "$task_id" && "$task_id" != "-" ]] || die_rule \
          "architecture_result to reviewer requires TASK" \
          "manager CC and reviewer assignment are read from task state" \
          "pass TASK=<task_id>"
        state_file="$(team_task_state_file "$task_id")"
        [[ -f "$state_file" ]] || die_rule \
          "task state not found for architecture_result: $task_id" \
          "architecture_result to a reviewer must reference a dispatched task" \
          "dispatch the task first or send the result to lead or manager"
        assigned_reviewer="$(team_task_state_field "$task_id" reviewer)"
        [[ "$assigned_reviewer" == "$to" ]] || die_rule \
          "architecture_result reviewer mismatch for $task_id" \
          "task state reviewer is $assigned_reviewer, but target is $to" \
          "send to $assigned_reviewer or update the task assignment"
        cc_to="$(team_task_state_field "$task_id" manager)"
        [[ -n "$cc_to" ]] || die_rule \
          "task $task_id is missing manager" \
          "architecture_result to a reviewer must also notify the task manager" \
          "redispatch or repair task state so manager is recorded"
        ;;
      release-captain)
        [[ -n "$bundle_id" && "$bundle_id" != "-" ]] || die_rule \
          "architecture_result to release-captain requires BUNDLE" \
          "manager CC and release-captain assignment are read from release state" \
          "pass BUNDLE=<bundle_id>"
        release_state_file="$(team_release_state_file "$bundle_id")"
        [[ -f "$release_state_file" ]] || die_rule \
          "release state not found for architecture_result: $bundle_id" \
          "architecture_result to a release-captain must reference a release request" \
          "run make release-request first or send the result to lead or manager"
        assigned_release_captain="$(team_release_state_field "$bundle_id" release_captain)"
        [[ "$assigned_release_captain" == "$to" ]] || die_rule \
          "architecture_result release-captain mismatch for $bundle_id" \
          "release state release_captain is $assigned_release_captain, but target is $to" \
          "send to $assigned_release_captain or create a new release request"
        cc_to="$(team_release_state_field "$bundle_id" manager)"
        [[ -n "$cc_to" ]] || die_rule \
          "release $bundle_id is missing manager" \
          "architecture_result to a release-captain must also notify the release manager" \
          "rerun make release-request or repair release state so manager is recorded"
        ;;
      *)
        die_rule \
          "architecture_result target role is invalid: $to_role" \
          "architecture results return to lead, manager, an assigned reviewer, or an assigned release-captain" \
          "send architecture_result to the requester recorded in the architecture request"
        ;;
    esac
    if [[ -n "$cc_to" ]]; then
      if ! team_config_agent_record "$cc_to" >/dev/null; then
        die_rule \
          "architecture_result CC target is unknown: $cc_to" \
          "the resolved manager is not present in team config" \
          "repair task or release state with a configured manager"
      fi
      cc_role="$(team_config_agent_field "$cc_to" role)"
      [[ "$cc_role" == "manager" ]] || die_rule \
        "architecture_result CC target is not a manager agent" \
        "$cc_to has role $cc_role in $TEAM_CONFIG_FILE" \
        "repair task or release state with a manager agent"
    fi
    ;;
  release_request)
    [[ "$to_role" == "release-captain" ]] || die_rule \
      "release_request target must be release-captain" \
      "release requests are handled only by the release-captain role" \
      "send release_request to the release-captain agent"
    [[ "$from_role" == "manager" ]] || die_rule \
      "release_request sender must be manager" \
      "release bundles are owned by manager" \
      "send release_request from manager"
    [[ -n "$bundle_id" && "$bundle_id" != "-" ]] || die_rule \
      "release_request requires BUNDLE" \
      "release requests must reference a release bundle" \
      "pass BUNDLE=<bundle_id>"
    release_state_file="$(team_release_state_file "$bundle_id")"
    [[ -f "$release_state_file" ]] || die_rule \
      "release state not found for release_request: $bundle_id" \
      "release_request messages are sent by make release-request after state is written" \
      "run make release-request BUNDLE=$bundle_id TASKS='<task ids>'"
    release_manager="$(team_release_state_field "$bundle_id" manager)"
    release_captain="$(team_release_state_field "$bundle_id" release_captain)"
    [[ "$release_manager" == "$from" ]] || die_rule \
      "release_request manager mismatch for $bundle_id" \
      "release state manager is $release_manager, but sender is $from" \
      "send from $release_manager or create a new release request"
    [[ "$release_captain" == "$to" ]] || die_rule \
      "release_request target mismatch for $bundle_id" \
      "release state release_captain is $release_captain, but target is $to" \
      "send to $release_captain or create a new release request"
    artifact_path="$(team_relative_path "$(team_release_bundle_file "$bundle_id")")"
    review_artifact_path="$(team_relative_path "$(team_release_review_file "$bundle_id")")"
    if [[ -z "$body" ]]; then
      body="Release request from $from."
    fi
    body="${body}"$'\n\n'"Release bundle path: $artifact_path"$'\n'"Release review path: $review_artifact_path"
    ;;
  release_result)
    [[ "$from_role" == "release-captain" ]] || die_rule \
      "release_result sender must be release-captain" \
      "release results are written by the release-captain role" \
      "send release_result from release-captain"
    [[ "$to_role" == "manager" ]] || die_rule \
      "release_result target must be manager" \
      "release results return to the bundle manager" \
      "send release_result to manager"
    [[ -n "$bundle_id" && "$bundle_id" != "-" ]] || die_rule \
      "release_result requires BUNDLE" \
      "release results must reference a release bundle" \
      "pass BUNDLE=<bundle_id>"
    release_state_file="$(team_release_state_file "$bundle_id")"
    [[ -f "$release_state_file" ]] || die_rule \
      "release state not found for release_result: $bundle_id" \
      "release_result messages require an existing release request" \
      "run make release-request first"
    release_manager="$(team_release_state_field "$bundle_id" manager)"
    release_captain="$(team_release_state_field "$bundle_id" release_captain)"
    [[ "$release_manager" == "$to" ]] || die_rule \
      "release_result target mismatch for $bundle_id" \
      "release state manager is $release_manager, but target is $to" \
      "send to $release_manager"
    [[ "$release_captain" == "$from" ]] || die_rule \
      "release_result sender mismatch for $bundle_id" \
      "release state release_captain is $release_captain, but sender is $from" \
      "send from $release_captain"
    artifact_path="$(team_relative_path "$(team_release_review_file "$bundle_id")")"
    ;;
  review_feedback)
    [[ -n "$task_id" && "$task_id" != "-" ]] || die_rule \
      "review_feedback requires TASK" \
      "review feedback is task-local supervision and must be tied to a task" \
      "pass TASK=<task_id>"
    [[ "$from_role" == "reviewer" ]] || die_rule \
      "review_feedback sender must be reviewer" \
      "only the assigned reviewer sends task-local supervision feedback" \
      "send review_feedback from the task reviewer"
    state_file="$(team_task_state_file "$task_id")"
    [[ -f "$state_file" ]] || die_rule \
      "task state not found for review_feedback: $task_id" \
      "review feedback requires a dispatched task with owner and reviewer state" \
      "dispatch the task first"
    owner="$(team_task_state_field "$task_id" owner)"
    assigned_reviewer="$(team_task_state_field "$task_id" reviewer)"
    [[ "$assigned_reviewer" == "$from" ]] || die_rule \
      "reviewer is not assigned to task $task_id" \
      "review_feedback must come from the reviewer recorded in task state" \
      "send from $assigned_reviewer or update the task assignment"
    [[ "$to" == "$owner" ]] || die_rule \
      "review_feedback target must be task owner" \
      "review feedback is sent to the worker assigned in task state" \
      "send review_feedback to $owner"
    ;;
esac

if [[ -z "$body" ]]; then
  if [[ -n "$task_id" && "$task_id" != "-" ]]; then
    body="$TEAM_QUEUE_DIR/tasks/$task_id.md を確認してください。"
  else
    body="$TEAM_QUEUE_DIR/inbox/$to.jsonl を確認してください。"
  fi
fi

write_message() {
  local message_to="$1"
  local message_body="$2"
  local message_cc_of="$3"
  local message_id
  local created_at
  local inbox_file
  local message_file
  local line

  message_id="$(team_message_id)"
  created_at="$(team_now_utc)"
  inbox_file="$TEAM_QUEUE_DIR/inbox/$message_to.jsonl"
  message_file="$TEAM_STATE_DIR/messages/$message_id.json"

  line="{\"id\":\"$(json_string "$message_id")\",\"from\":\"$(json_string "$from")\",\"to\":\"$(json_string "$message_to")\",\"type\":\"$(json_string "$type")\",\"subtype\":\"$(json_string "$subtype")\",\"task_id\":\"$(json_string "$task_id")\",\"bundle_id\":\"$(json_string "$bundle_id")\",\"artifact_path\":\"$(json_string "$artifact_path")\",\"cc_of\":\"$(json_string "$message_cc_of")\",\"done_recommendation\":\"$(json_string "$done_recommendation")\",\"created_at\":\"$created_at\",\"body\":\"$(json_string "$message_body")\"}"

  acquire_team_lock "inbox-$message_to"
  printf '%s\n' "$line" >> "$inbox_file"
  printf '%s\n' "$line" > "$message_file"
  release_team_lock

  if ! "$SCRIPT_DIR/team_nudge.sh" "$message_to"; then
    warn "nudge failed for $message_to; inbox entry is still available at $inbox_file"
  fi

  printf '%s\n' "$message_id"
}

message_id="$(write_message "$to" "$body" "")"
printf 'message_id=%s\n' "$message_id"

if [[ -n "$cc_to" ]]; then
  cc_body="CC of $type $message_id from $from to $to."$'\n\n'"$body"
  cc_message_id="$(write_message "$cc_to" "$cc_body" "$message_id")"
  printf 'cc_to=%s\n' "$cc_to"
  printf 'cc_message_id=%s\n' "$cc_message_id"
fi

team_mark_inbox_processed "$from" "$task_id" "$bundle_id"
