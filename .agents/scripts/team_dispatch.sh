#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_dispatch.sh [--manager <manager_id>] <task_id>" >&2
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
    --*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

[[ $# -eq 1 ]] || { usage; exit 2; }

task_id="$1"
[[ "$task_id" != */* ]] || die "task_id must not contain '/': $task_id"

ensure_team_dirs
team_config_validate

if [[ -z "$manager_id" ]]; then
  [[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
    "manager is required for dispatch" \
    "dispatch records the task manager, but this shell has no TEAM_AGENT_ID" \
    "run dispatch inside a manager pane or pass MANAGER=<manager_id>"
  manager_id="$TEAM_AGENT_ID"
fi

team_config_agent_record "$manager_id" >/dev/null || die_rule \
  "unknown manager: $manager_id" \
  "the dispatch sender must be present in $TEAM_CONFIG_FILE" \
  "run from the configured manager pane or pass MANAGER=<manager_id>"
manager_role="$(team_config_agent_field "$manager_id" role)"
[[ "$manager_role" == "manager" ]] || die_rule \
  "dispatch sender is not manager: $manager_id" \
  "$manager_id has role $manager_role" \
  "run dispatch from the manager pane"

task_file="$TEAM_QUEUE_DIR/tasks/$task_id.md"
state_file="$(team_task_state_file "$task_id")"
[[ -f "$task_file" ]] || die_rule \
  "task file not found: $task_id" \
  "dispatch requires a completed implementation task contract" \
  "create $task_file from GENERAL_TEMPLATE.md or FRONTEND_TEMPLATE.md"
[[ ! -f "$state_file" ]] || die_rule \
  "task is already dispatched: $task_id" \
  "$state_file already records an assignment" \
  "continue the existing task lifecycle instead of dispatching it again"

"$SCRIPT_DIR/team_task_lint.sh" "$task_id" >/dev/null

worker_id="$(team_task_markdown_field "$task_file" Worker)"
worker_role="$(team_config_agent_field "$worker_id" role)"
supervisor_id="$(team_config_agent_field "$worker_id" supervisor)"
supervisor_role="$(team_config_agent_field "$supervisor_id" role)"
architecture_required="$(team_task_markdown_field "$task_file" "Architecture required")"

if busy_task="$(team_task_worker_is_busy "$worker_id")"; then
  die_rule \
    "implementation worker is busy: $worker_id" \
    "$worker_id is still assigned to $busy_task" \
    "wait for Manager to mark $busy_task done or choose another implementation worker"
fi
if busy_task="$(team_task_supervisor_is_busy "$supervisor_id")"; then
  die_rule \
    "implementation supervisor is busy: $supervisor_id" \
    "$supervisor_id is still assigned to $busy_task" \
    "wait for Manager to mark $busy_task done or choose another fixed worker pair"
fi

case "$worker_role:$supervisor_role" in
  general-worker:general-reviewer|hard-task-worker:general-reviewer)
    direction_status="not_applicable"
    supervision_path=".agents/queue/reviews/${task_id}_${supervisor_id}.md"
    ;;
  frontend-worker:frontend-critic)
    direction_status="pending"
    supervision_path=".agents/queue/critiques/${task_id}_${supervisor_id}.md"
    ;;
  *)
    die_rule \
      "invalid implementation pair: $worker_id and $supervisor_id" \
      "$worker_role cannot be supervised by $supervisor_role" \
      "fix the supervisor pairing in $TEAM_CONFIG_FILE"
    ;;
esac

git -C "$TEAM_ROOT" rev-parse --verify HEAD >/dev/null 2>&1 || die_rule \
  "git HEAD does not exist" \
  "implementation tasks require a committed base" \
  "commit the initialized repository before dispatching tasks"
base_commit="$(git -C "$TEAM_ROOT" rev-parse HEAD)"

team_update_markdown_field "$task_file" "Supervisor" "$supervisor_id"

acquire_team_lock "dispatch-$task_id"
team_write_task_state \
  "$task_id" \
  "$manager_id" \
  "$worker_id" \
  "$supervisor_id" \
  "dispatched" \
  "$base_commit" \
  "" \
  "" \
  "" \
  "" \
  "false" \
  "$architecture_required" \
  "" \
  "" \
  "$direction_status" \
  ""
release_team_lock

if [[ "$worker_role" == "frontend-worker" ]]; then
  worker_body="$task_file を読み、固定 supervisor は $supervisor_id です。まず view direction を共有し、critic の response を受けてから主要 UI 実装へ進んでください。実画面を確認しながら実装、検証、task commit、report を行い、ready_for_supervision を送ってください。"
  supervisor_body="$task_file を読み、固定 worker $worker_id を task-local に監督してください。最初に direction critique の要否を判断し、必要なら view direction を固めてから実装を進めます。最終 artifact は $supervision_path です。"
else
  worker_body="$task_file を読み、固定 supervisor は $supervisor_id です。Reviewerの入力が実装を有意に変え得る時は supervision_checkpoint で相談してください。実装、検証、task commit、report 作成後に ready_for_supervision を送ってください。"
  supervisor_body="$task_file を読み、固定 worker $worker_id と直接やりとりしてください。task-local supervisor として checkpoint、相談、feedback、ready_for_supervision を扱い、最終 artifact を $supervision_path に書いてください。"
fi

team_send_with_body_file "$manager_id" task_assigned "$task_id" "" "$worker_id" "$worker_body" >/dev/null
team_send_with_body_file "$manager_id" supervision_assigned "$task_id" "" "$supervisor_id" "$supervisor_body" >/dev/null

printf '%s\n' "$state_file"
