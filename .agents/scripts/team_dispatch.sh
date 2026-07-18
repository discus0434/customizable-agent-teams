#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_dispatch.sh [--owner <agent_id>] <task_id>" >&2
}

owner_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)
      [[ $# -ge 2 ]] || die "--owner requires a value"
      owner_id="$2"
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

lane="normal"
case "$task_id" in
  T-E-*) lane="express" ;;
esac

ensure_team_dirs
team_config_validate

if [[ -z "$owner_id" ]]; then
  [[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
    "dispatcher is required for dispatch" \
    "dispatch records the task owner, but this shell has no TEAM_AGENT_ID" \
    "run dispatch inside the manager or lead pane, or pass OWNER=<agent_id>"
  owner_id="$TEAM_AGENT_ID"
fi

team_config_agent_record "$owner_id" >/dev/null || die_rule \
  "unknown dispatcher: $owner_id" \
  "the dispatch sender must be present in $TEAM_CONFIG_FILE" \
  "run from the configured manager pane or pass OWNER=<agent_id>"
dispatcher_role="$(team_config_agent_field "$owner_id" role)"
if [[ "$lane" == "express" ]]; then
  [[ "$dispatcher_role" == "lead" ]] || die_rule \
    "express dispatch sender is not lead: $owner_id" \
    "$owner_id has role $dispatcher_role, but express tasks belong to Lead" \
    "run express dispatch from the lead pane"
else
  [[ "$dispatcher_role" == "manager" ]] || die_rule \
    "dispatch sender is not manager: $owner_id" \
    "$owner_id has role $dispatcher_role" \
    "run dispatch from the manager pane"
fi

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
architecture_required="$(team_task_markdown_field "$task_file" "Architecture required")"

if [[ "$lane" == "express" ]]; then
  while IFS= read -r express_state; do
    express_task="$(basename "$express_state" .json)"
    case "$express_task" in T-E-*) ;; *) continue ;; esac
    express_status="$(extract_json_field status < "$express_state")"
    if [[ "$express_status" != "done" ]]; then
      die_rule \
        "another express task is in flight: $express_task" \
        "express runs one task at a time to stay reviewable by Lead" \
        "finish $express_task or dispatch this work as a normal task"
    fi
  done < <(find "$TEAM_STATE_DIR/tasks" -maxdepth 1 -type f -name 'T-E-*.json' | sort)
fi

if busy_task="$(team_task_worker_is_busy "$worker_id")"; then
  die_rule \
    "implementation worker is busy: $worker_id" \
    "$worker_id is still assigned to $busy_task" \
    "wait for the current task to finish or choose another implementation worker"
fi

if [[ "$lane" == "express" ]]; then
  supervisor_id=""
  direction_status="not_applicable"
else
  supervisor_id="$(team_config_agent_field "$worker_id" supervisor)"
  supervisor_role="$(team_config_agent_field "$supervisor_id" role)"
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
fi

git -C "$TEAM_ROOT" rev-parse --verify HEAD >/dev/null 2>&1 || die_rule \
  "git HEAD does not exist" \
  "implementation tasks require a committed base" \
  "commit the initialized repository before dispatching tasks"
base_commit="$(git -C "$TEAM_ROOT" rev-parse HEAD)"

if [[ "$lane" != "express" ]]; then
  team_update_markdown_field "$task_file" "Supervisor" "$supervisor_id"
fi

acquire_team_lock "dispatch-$task_id"
team_write_task_state \
  "$task_id" \
  "$owner_id" \
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
  "$direction_status" \
  ""
release_team_lock

if [[ "$lane" == "express" ]]; then
  worker_body="${task_file}を読み、express taskとして実装からreportまで進めてください。Supervisorはいません。完了報告はexpress_readyで${owner_id}へ送ってください。"
  team_send_with_body_file "$owner_id" task_assigned "$task_id" "$worker_id" "$worker_body" >/dev/null

  exec_prompt="あなたはこのteamのexpress worker、agent_id=${worker_id}です。
make team-identityで自分を確認し、AGENTS.mdとteam-express-worker skillに従ってください。
express task ${task_id}が割り当てられています。.agents/queue/tasks/${task_id}.mdを読み、Allowed pathsの中で実装してください。
検証はtask固有の検証に加えて、make post-changeとmake smokeを実行してください。
変更のcommitはmake task-commit TASK=${task_id} MESSAGE=\"<summary>\"で行ってください。
その後、make report TASK=${task_id} STATUS=ready_for_leadを実行し、reportのplaceholderをすべて実測の証拠で埋めてください。
最後にmake team-send TO=${owner_id} TYPE=express_ready TASK=${task_id} BODY=\"<要点>\"でLeadへ報告してください。
Supervisorはいません。解消できないblockerがあれば、make team-send TO=${owner_id} TYPE=question TASK=${task_id} BODY=\"<質問>\"を送って終了してください。"
  if ! "$SCRIPT_DIR/team_exec_run.sh" --kind task --ref "$task_id" --notify "$owner_id" "$worker_id" "$exec_prompt" >/dev/null; then
    die_rule \
      "express exec launch failed: $task_id" \
      "$worker_id could not start a codex exec run" \
      "inspect .agents/queue/state/exec/${worker_id}.err, then dispatch again"
  fi
else
  worker_body="${task_file}を読み、固定Supervisor ${supervisor_id}と連携してtaskを進めてください。"
  supervisor_body="${task_file}を読み、固定Worker ${worker_id}の相談と最終判断を担当してください。最終成果物は${supervision_path}へ書いてください。"

  team_send_with_body_file "$owner_id" task_assigned "$task_id" "$worker_id" "$worker_body" >/dev/null
  team_send_with_body_file "$owner_id" supervision_assigned "$task_id" "$supervisor_id" "$supervisor_body" >/dev/null
fi

printf '%s\n' "$state_file"
# 選択肢は判断の瞬間に想起されなければ存在しないのと同じ。batch癖と
# research先行発注の失念が起きるのはこの瞬間なので、ここへ1行置く。
# stdoutはstate file pathの契約なので、助言はstderrへ出す
printf 'next: 並列にdispatchできるtaskが他に残っていないか、次のphaseのresearch先行発注が要るかを確認する。\n' >&2
