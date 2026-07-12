#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_send.sh [--from <agent_id>] [--type <type>] [--task <task_id>] [--bundle <bundle_id>] [--research <request_id>] [--body-file <path>] [--done-recommendation <true|false>] <to> [body...]

TYPE=note records information. Omit TYPE when requesting strategist, architect, release-captain, or the research-worker pool.
USAGE
}

from=""
type=""
task_id=""
bundle_id=""
research_id=""
body_file=""
done_recommendation=""
requires_attention=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) [[ $# -ge 2 ]] || die "--from requires a value"; from="$2"; shift 2 ;;
    --type) [[ $# -ge 2 ]] || die "--type requires a value"; type="$2"; shift 2 ;;
    --task) [[ $# -ge 2 ]] || die "--task requires a value"; task_id="$2"; shift 2 ;;
    --bundle) [[ $# -ge 2 ]] || die "--bundle requires a value"; bundle_id="$2"; shift 2 ;;
    --research) [[ $# -ge 2 ]] || die "--research requires a value"; research_id="$2"; shift 2 ;;
    --body-file) [[ $# -ge 2 ]] || die "--body-file requires a path"; body_file="$2"; shift 2 ;;
    --done-recommendation) [[ $# -ge 2 ]] || die "--done-recommendation requires true or false"; done_recommendation="$2"; shift 2 ;;
    --requires-attention) requires_attention="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    --*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

[[ $# -ge 1 ]] || { usage; exit 2; }
to="$1"
shift
body="${*:-}"

ensure_team_dirs
team_config_validate

if [[ -z "$from" ]]; then
  [[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
    "sender is unknown" \
    "this shell has no TEAM_AGENT_ID and --from was not provided" \
    "run inside a team pane or pass FROM=<agent_id>"
  from="$TEAM_AGENT_ID"
fi
team_config_agent_record "$from" >/dev/null || die_rule \
  "unknown sender agent: $from" \
  "the sender is not present in $TEAM_CONFIG_FILE" \
  "choose a configured agent id"
from_role="$(team_config_agent_field "$from" role)"

if [[ -n "$body_file" ]]; then
  [[ -z "$body" ]] || die_rule \
    "body and body file were both provided" \
    "message body must have one source" \
    "pass either BODY or BODY_FILE"
  [[ -f "$body_file" ]] || die_rule \
    "body file not found: $body_file" \
    "the requested path does not exist" \
    "write the body file first or pass BODY directly"
  body="$(<"$body_file")"
fi

if [[ "$to" == "research-worker" ]]; then
  [[ -z "$type" || "$type" == "research_request" ]] || die_rule \
    "research-worker pool accepts research requests only" \
    "TYPE=$type does not describe a pool request" \
    "omit TYPE when sending to research-worker"
  [[ -z "$bundle_id" && -z "$research_id" && -z "$done_recommendation" ]] || die_rule \
    "research request has incompatible routing fields" \
    "a new research request is not a bundle, result, or done recommendation" \
    "send only TASK when the research is related to an implementation task"
  case "$from_role" in
    lead|manager|strategist|architect|release-captain) ;;
    *) die_rule \
      "role cannot request research: $from_role" \
      "research-worker is available to lead, manager, strategist, architect, and release-captain" \
      "route the need through one of those roles" ;;
  esac
  exec "$SCRIPT_DIR/team_research_request.sh" --from "$from" --task "$task_id" "$body"
fi

team_config_agent_record "$to" >/dev/null || die_rule \
  "unknown target agent: $to" \
  "the recipient is not present in $TEAM_CONFIG_FILE" \
  "choose a configured agent id or TO=research-worker"
to_role="$(team_config_agent_field "$to" role)"

if [[ -n "$done_recommendation" ]]; then
  case "$done_recommendation" in
    true|false) ;;
    *) die_rule "invalid done recommendation: $done_recommendation" "the value must be true or false" "pass true or false" ;;
  esac
fi

if [[ -z "$type" ]]; then
  case "$to_role" in
    strategist) type="strategy_request" ;;
    architect) type="architecture_request" ;;
    release-captain) type="release_request" ;;
    *) die_rule \
      "message type is required" \
      "the recipient role does not imply a unique action" \
      "pass TYPE=<message_type>" ;;
  esac
fi

subtype=""
artifact_path=""
cc_to=""

load_task_assignment() {
  [[ -n "$task_id" && "$task_id" != "-" ]] || die_rule \
    "$type requires TASK" \
    "task-local messages must reference one dispatched task" \
    "pass TASK=<task_id>"
  local state_file
  state_file="$(team_task_state_file "$task_id")"
  [[ -f "$state_file" ]] || die_rule \
    "task state not found: $task_id" \
    "$type requires a dispatched task" \
    "dispatch the task first"
  task_manager="$(team_task_state_field "$task_id" manager)"
  task_worker="$(team_task_state_field "$task_id" worker)"
  task_supervisor="$(team_task_state_field "$task_id" supervisor)"
  task_status="$(team_task_state_field "$task_id" status)"
  task_base_commit="$(team_task_state_field "$task_id" base_commit)"
  task_head_commit="$(team_task_state_field "$task_id" head_commit)"
  task_report="$(team_task_state_field "$task_id" report)"
  task_supervision_artifact="$(team_task_state_field "$task_id" supervision_artifact)"
  task_supervision_decision="$(team_task_state_field "$task_id" supervision_decision)"
  task_done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
  task_architecture_required="$(team_task_state_field "$task_id" architecture_required)"
  task_architecture="$(team_task_state_field "$task_id" architecture)"
  task_release_bundle="$(team_task_state_field "$task_id" release_bundle)"
  task_direction_status="$(team_task_state_field "$task_id" direction_status)"
  task_direction_artifact="$(team_task_state_field "$task_id" direction_artifact)"
}

require_assigned_worker_to_supervisor() {
  load_task_assignment
  [[ "$from" == "$task_worker" ]] || die_rule \
    "$type sender is not the assigned worker" \
    "task $task_id is assigned to $task_worker, but sender is $from" \
    "send from $task_worker"
  [[ "$to" == "$task_supervisor" ]] || die_rule \
    "$type target is not the assigned supervisor" \
    "task $task_id is supervised by $task_supervisor, but target is $to" \
    "send to $task_supervisor"
}

require_assigned_supervisor_to_worker() {
  load_task_assignment
  [[ "$from" == "$task_supervisor" ]] || die_rule \
    "$type sender is not the assigned supervisor" \
    "task $task_id is supervised by $task_supervisor, but sender is $from" \
    "send from $task_supervisor"
  [[ "$to" == "$task_worker" ]] || die_rule \
    "$type target is not the assigned worker" \
    "task $task_id is assigned to $task_worker, but target is $to" \
    "send to $task_worker"
}

case "$type" in
  strategy_request)
    [[ "$to_role" == "strategist" ]] || die_rule "strategy_request target must be strategist" "the strategist owns focused analysis" "send to the strategist agent"
    case "$from_role" in
      lead) subtype="lead_intake" ;;
      manager) subtype="manager_planning" ;;
      architect) subtype="architect_analysis" ;;
      general-reviewer|frontend-critic)
        load_task_assignment
        [[ "$task_supervisor" == "$from" ]] || die_rule "supervisor is not assigned to $task_id" "only the fixed task supervisor may request task-local analysis" "send from $task_supervisor"
        subtype="${from_role}-supervision"
        cc_to="$task_manager"
        ;;
      general-worker|hard-task-worker|frontend-worker)
        load_task_assignment
        die_rule "implementation worker cannot request strategist directly" "task-local uncertainty goes through the fixed supervisor" "ask $task_supervisor"
        ;;
      *) die_rule "role cannot request strategy: $from_role" "strategy requests come from lead, manager, architect, or an assigned supervisor" "route the request through an allowed role" ;;
    esac
    artifact_path="$(team_strategy_artifact_path "$task_id" "$subtype")"
    [[ -n "$body" ]] || body="Strategy request from $from."
    body+=$'\n\n'"Strategy artifact path: $artifact_path"
    ;;
  strategy_result)
    [[ "$from_role" == "strategist" ]] || die_rule \
      "strategy_result sender must be strategist" \
      "the strategist writes focused analysis results" \
      "send from the strategist agent"
    case "$to_role" in
      lead|manager|architect)
        ;;
      general-reviewer|frontend-critic)
        load_task_assignment
        [[ "$to" == "$task_supervisor" ]] || die_rule \
          "strategy result target does not supervise $task_id" \
          "task supervisor is $task_supervisor" \
          "send to $task_supervisor"
        cc_to="$task_manager"
        ;;
      *)
        die_rule \
          "strategy_result target role is invalid: $to_role" \
          "strategy results return to Lead, Manager, Architect, or the assigned task Supervisor" \
          "send the result to the role that requested the strategy work"
        ;;
    esac
    ;;
  architecture_request)
    [[ "$to_role" == "architect" ]] || die_rule "architecture_request target must be architect" "the architect owns technical direction" "send to the architect agent"
    case "$from_role" in
      lead) subtype="lead_intent" ;;
      manager) subtype="manager_design" ;;
      general-reviewer|frontend-critic)
        load_task_assignment
        [[ "$task_supervisor" == "$from" ]] || die_rule "supervisor is not assigned to $task_id" "only the fixed task supervisor may request task-local architecture direction" "send from $task_supervisor"
        subtype="${from_role}-supervision"
        cc_to="$task_manager"
        ;;
      release-captain)
        [[ -n "$bundle_id" && "$bundle_id" != "-" ]] || die_rule "release architecture request requires BUNDLE" "release readiness is scoped to one bundle" "pass BUNDLE=<bundle_id>"
        [[ -f "$(team_release_state_file "$bundle_id")" ]] || die_rule "release state not found: $bundle_id" "the bundle has not been requested" "run make release-request first"
        assigned_release_captain="$(team_release_state_field "$bundle_id" release_captain)"
        [[ "$assigned_release_captain" == "$from" ]] || die_rule "release-captain is not assigned to $bundle_id" "release state names $assigned_release_captain" "send from $assigned_release_captain"
        subtype="release_readiness"
        cc_to="$(team_release_state_field "$bundle_id" manager)"
        ;;
      general-worker|hard-task-worker|frontend-worker)
        load_task_assignment
        die_rule "implementation worker cannot request architect directly" "task-local technical direction goes through the fixed supervisor" "ask $task_supervisor"
        ;;
      *) die_rule "role cannot request architecture: $from_role" "architecture requests come from lead, manager, assigned supervisors, or release-captain" "route the request through an allowed role" ;;
    esac
    artifact_path="$(team_architecture_artifact_path "$task_id" "$bundle_id" "$subtype")"
    if [[ -n "$task_id" && "$task_id" != "-" ]]; then
      load_task_assignment
      team_write_task_state \
        "$task_id" "$task_manager" "$task_worker" "$task_supervisor" "$task_status" \
        "$task_base_commit" "$task_head_commit" "$task_report" "$task_supervision_artifact" \
        "$task_supervision_decision" "${task_done_recommendation:-false}" "true" "$artifact_path" \
        "$task_release_bundle" "$task_direction_status" "$task_direction_artifact"
    fi
    [[ -n "$body" ]] || body="Architecture request from $from."
    body+=$'\n\n'"Architecture artifact path: $artifact_path"
    ;;
  architecture_result)
    [[ "$from_role" == "architect" ]] || die_rule "architecture_result sender must be architect" "the architect writes architecture results" "send from architect"
    case "$to_role" in
      lead|manager) ;;
      general-reviewer|frontend-critic)
        load_task_assignment
        [[ "$to" == "$task_supervisor" ]] || die_rule "architecture result target does not supervise $task_id" "task supervisor is $task_supervisor" "send to $task_supervisor"
        cc_to="$task_manager"
        ;;
      release-captain)
        [[ -n "$bundle_id" && "$bundle_id" != "-" ]] || die_rule "architecture_result requires BUNDLE" "the result returns to one release review" "pass BUNDLE=<bundle_id>"
        [[ "$to" == "$(team_release_state_field "$bundle_id" release_captain)" ]] || die_rule "architecture result target is not assigned to $bundle_id" "release state names another captain" "send to the assigned release-captain"
        cc_to="$(team_release_state_field "$bundle_id" manager)"
        ;;
      *) die_rule "architecture_result target role is invalid: $to_role" "results return to the requester role" "send to lead, manager, assigned supervisor, or release-captain" ;;
    esac
    ;;
  release_request)
    [[ "$from_role" == "manager" && "$to_role" == "release-captain" ]] || die_rule "invalid release_request route" "release requests go from manager to release-captain" "use make release-request"
    [[ -n "$bundle_id" && "$bundle_id" != "-" ]] || die_rule "release_request requires BUNDLE" "the message must reference a prepared bundle" "pass BUNDLE=<bundle_id>"
    [[ -f "$(team_release_state_file "$bundle_id")" ]] || die_rule "release state not found: $bundle_id" "make release-request creates state before sending" "run make release-request"
    [[ "$(team_release_state_field "$bundle_id" manager)" == "$from" ]] || die "release manager mismatch for $bundle_id"
    [[ "$(team_release_state_field "$bundle_id" release_captain)" == "$to" ]] || die "release-captain mismatch for $bundle_id"
    artifact_path="$(team_relative_path "$(team_release_bundle_file "$bundle_id")")"
    body="${body:-Release request from $from.}"$'\n\n'"Release bundle path: $artifact_path"$'\n'"Release review path: $(team_relative_path "$(team_release_review_file "$bundle_id")")"
    ;;
  release_result)
    [[ "$from_role" == "release-captain" && "$to_role" == "manager" ]] || die_rule "invalid release_result route" "release results return from release-captain to manager" "use make release-report"
    [[ -n "$bundle_id" && -f "$(team_release_state_file "$bundle_id")" ]] || die "release state not found: $bundle_id"
    [[ "$(team_release_state_field "$bundle_id" manager)" == "$to" ]] || die "release manager mismatch for $bundle_id"
    [[ "$(team_release_state_field "$bundle_id" release_captain)" == "$from" ]] || die "release-captain mismatch for $bundle_id"
    artifact_path="$(team_relative_path "$(team_release_review_file "$bundle_id")")"
    ;;
  completion_ready|completion_ack)
    [[ -n "$bundle_id" && -f "$(team_release_state_file "$bundle_id")" ]] || die_rule "$type requires a shipped BUNDLE" "completion messages close one release" "pass BUNDLE=<bundle_id> after SHIP"
    release_manager="$(team_release_state_field "$bundle_id" manager)"
    release_status="$(team_release_state_field "$bundle_id" status)"
    release_decision="$(team_release_state_field "$bundle_id" decision)"
    [[ "$release_status" == "ship" && "$release_decision" == "SHIP" ]] || die_rule "release is not shipped: $bundle_id" "status=$release_status decision=$release_decision" "wait for release-captain SHIP"
    if [[ "$type" == "completion_ready" ]]; then
      [[ "$from_role" == "manager" && "$to_role" == "lead" && "$from" == "$release_manager" ]] || die_rule "invalid completion_ready route" "the bundle manager sends readiness to lead" "send from $release_manager to lead"
    else
      [[ "$from_role" == "lead" && "$to" == "$release_manager" ]] || die_rule "invalid completion_ack route" "lead acknowledges the bundle manager" "send from lead to $release_manager"
    fi
    artifact_path="$(team_relative_path "$(team_release_review_file "$bundle_id")")"
    ;;
  manager_fix)
    [[ "$from_role" == "manager" ]] || die_rule "manager_fix sender must be manager" "only Manager returns an accepted task to its implementation pair" "send from manager"
    load_task_assignment
    [[ "$from" == "$task_manager" ]] || die "task manager is $task_manager, not $from"
    [[ "$task_status" == "supervision_ok" ]] || die_rule "task is not awaiting Manager done decision: $task_id" "status=$task_status, but manager_fix requires supervision_ok" "wait for supervisor OK or use supervision_feedback earlier"
    [[ "$to" == "$task_worker" || "$to" == "$task_supervisor" ]] || die_rule "manager_fix target is outside the implementation pair" "the task pair is $task_worker and $task_supervisor" "send to one of the task pair"
    team_write_task_state \
      "$task_id" "$task_manager" "$task_worker" "$task_supervisor" "manager_fix" \
      "$task_base_commit" "$task_head_commit" "$task_report" "$task_supervision_artifact" \
      "FIX" "false" "$task_architecture_required" "$task_architecture" "$task_release_bundle" \
      "$task_direction_status" "$task_direction_artifact"
    ;;
  task_assigned)
    [[ "$from_role" == "manager" ]] || die "task_assigned sender must be manager"
    load_task_assignment
    [[ "$from" == "$task_manager" && "$to" == "$task_worker" ]] || die "task_assigned route does not match task state"
    ;;
  supervision_assigned)
    [[ "$from_role" == "manager" ]] || die "supervision_assigned sender must be manager"
    load_task_assignment
    [[ "$from" == "$task_manager" && "$to" == "$task_supervisor" ]] || die "supervision_assigned route does not match task state"
    ;;
  supervision_checkpoint|ready_for_supervision|view_direction_ready)
    require_assigned_worker_to_supervisor
    if [[ "$type" == "view_direction_ready" ]]; then
      [[ "$from_role" == "frontend-worker" && "$to_role" == "frontend-critic" ]] || die_rule "view_direction_ready requires the frontend pair" "general implementation uses supervision_checkpoint" "send from frontend-worker to frontend-critic"
    fi
    ;;
  supervision_feedback)
    require_assigned_supervisor_to_worker
    ;;
  view_direction_result)
    load_task_assignment
    [[ "$from" == "$task_supervisor" && "$from_role" == "frontend-critic" ]] || die "view_direction_result sender must be the assigned frontend-critic"
    [[ "$to" == "$task_worker" || "$to" == "$task_manager" ]] || die "view_direction_result target must be task worker or manager"
    ;;
  supervision_result)
    load_task_assignment
    [[ "$from" == "$task_supervisor" ]] || die "supervision_result sender must be the assigned supervisor"
    [[ "$to" == "$task_worker" || "$to" == "$task_manager" ]] || die "supervision_result target must be task worker or manager"
    ;;
  research_request)
    [[ "$from_role" =~ ^(lead|manager|strategist|architect|release-captain)$ ]] || die "invalid research_request sender role: $from_role"
    [[ "$to_role" == "research-worker" && -n "$research_id" ]] || die "direct research_request requires an assigned research worker and request id"
    [[ -f "$(team_research_state_file "$research_id")" ]] || die "research state not found: $research_id"
    [[ "$(team_research_state_field "$research_id" caller)" == "$from" ]] || die "research caller mismatch: $research_id"
    [[ "$(team_research_state_field "$research_id" worker)" == "$to" ]] || die "research worker mismatch: $research_id"
    artifact_path=".agents/queue/research/${research_id}.md"
    ;;
  research_question)
    [[ "$from_role" == "research-worker" ]] || die "research_question sender must be research-worker"
    [[ -n "$research_id" ]] || die "research_question requires research id"
    [[ "$(team_research_state_field "$research_id" worker)" == "$from" ]] || die "research question sender is not assigned: $research_id"
    [[ "$(team_research_state_field "$research_id" caller)" == "$to" ]] || die "research question target is not caller: $research_id"
    ;;
  research_answer)
    [[ -n "$research_id" ]] || die "research_answer requires research id"
    [[ "$(team_research_state_field "$research_id" caller)" == "$from" ]] || die "research answer sender is not caller: $research_id"
    [[ "$(team_research_state_field "$research_id" worker)" == "$to" ]] || die "research answer target is not assigned worker: $research_id"
    ;;
  research_cancelled)
    [[ -n "$research_id" ]] || die "research_cancelled requires research id"
    [[ "$(team_research_state_field "$research_id" caller)" == "$from" ]] || die "research cancellation sender is not caller: $research_id"
    [[ "$(team_research_state_field "$research_id" worker)" == "$to" ]] || die "research cancellation target is not assigned worker: $research_id"
    ;;
  research_result)
    [[ -n "$research_id" ]] || die "research_result requires research id"
    [[ "$(team_research_state_field "$research_id" worker)" == "$from" ]] || die "research result sender is not assigned worker: $research_id"
    [[ "$(team_research_state_field "$research_id" caller)" == "$to" ]] || die "research result target is not caller: $research_id"
    artifact_path="$(team_research_state_field "$research_id" artifact)"
    ;;
  note|intake|approval|decision|question|answer|request)
    ;;
  *)
    die_rule \
      "unknown message type: $type" \
      "message routing accepts only protocol types" \
      "use a type documented in .agents/docs/TEAM_PROTOCOL.md"
    ;;
esac

if [[ -n "$cc_to" ]]; then
  team_config_agent_record "$cc_to" >/dev/null || die "resolved CC target is not configured: $cc_to"
  [[ "$(team_config_agent_field "$cc_to" role)" == "manager" ]] || die "resolved CC target is not manager: $cc_to"
fi

if [[ -z "$body" ]]; then
  if [[ -n "$task_id" && "$task_id" != "-" ]]; then
    body=".agents/queue/tasks/$task_id.md を確認してください。"
  else
    body="inbox $to を確認してください。"
  fi
fi

if [[ -z "$requires_attention" ]]; then
  [[ "$type" == "note" ]] && requires_attention="false" || requires_attention="true"
fi

write_message() {
  local message_to="$1"
  local message_body="$2"
  local message_cc_of="$3"
  local message_requires_attention="$4"
  local message_id
  local created_at
  local inbox_file
  local message_file
  local processed_dir
  local line

  message_id="$(team_message_id)"
  created_at="$(team_now_utc)"
  inbox_file="$TEAM_QUEUE_DIR/inbox/$message_to.jsonl"
  message_file="$TEAM_STATE_DIR/messages/$message_id.json"
  processed_dir="$TEAM_STATE_DIR/processed/$message_to"
  line="{\"id\":\"$(json_string "$message_id")\",\"from\":\"$(json_string "$from")\",\"to\":\"$(json_string "$message_to")\",\"type\":\"$(json_string "$type")\",\"subtype\":\"$(json_string "$subtype")\",\"task_id\":\"$(json_string "$task_id")\",\"bundle_id\":\"$(json_string "$bundle_id")\",\"research_id\":\"$(json_string "$research_id")\",\"artifact_path\":\"$(json_string "$artifact_path")\",\"cc_of\":\"$(json_string "$message_cc_of")\",\"done_recommendation\":\"$(json_string "$done_recommendation")\",\"requires_attention\":\"$(json_string "$message_requires_attention")\",\"created_at\":\"$created_at\",\"body\":\"$(json_string "$message_body")\"}"

  acquire_team_lock "inbox-$message_to"
  printf '%s\n' "$line" >> "$inbox_file"
  printf '%s\n' "$line" > "$message_file"
  if [[ "$message_requires_attention" == "false" ]]; then
    mkdir -p "$processed_dir"
    printf '%s\n' "$created_at" > "$processed_dir/$message_id"
  fi
  release_team_lock

  if [[ "$message_requires_attention" == "true" ]]; then
    "$SCRIPT_DIR/team_nudge.sh" "$message_to" >/dev/null || warn "nudge failed for $message_to; inbox message remains available"
  fi
  printf '%s\n' "$message_id"
}

message_id="$(write_message "$to" "$body" "" "$requires_attention")"
team_record_task_message_activity "$message_id"
printf 'message_id=%s\n' "$message_id"

if [[ -n "$cc_to" ]]; then
  cc_body="CC of $type $message_id from $from to $to."$'\n\n'"$body"
  cc_message_id="$(write_message "$cc_to" "$cc_body" "$message_id" "true")"
  team_record_task_message_activity "$cc_message_id"
  printf 'cc_to=%s\n' "$cc_to"
  printf 'cc_message_id=%s\n' "$cc_message_id"
fi

case "$type" in
  research_request|research_question|research_answer|research_cancelled|research_result) ;;
  *) team_mark_inbox_processed "$from" "$task_id" "$bundle_id" ;;
esac
