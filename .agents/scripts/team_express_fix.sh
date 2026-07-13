#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_express_fix.sh <task_id> <feedback>" >&2
}

[[ $# -eq 2 ]] || { usage; exit 2; }
task_id="$1"
feedback="$2"
[[ -n "$feedback" ]] || die "express fix feedback is empty"
case "$task_id" in
  T-E-*) ;;
  *) die "express fix requires an express task id: $task_id" ;;
esac

[[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
  "express fix identity is unavailable" \
  "fix feedback belongs to the dispatching lead" \
  "run make express-fix inside the lead pane"
lead_id="$TEAM_AGENT_ID"
[[ "$(team_config_agent_field "$lead_id" role)" == "lead" ]] || die_rule \
  "express fix sender is not lead: $lead_id" \
  "express tasks are reviewed and returned by Lead" \
  "run make express-fix from the lead pane"

ensure_team_dirs
state_file="$(team_task_state_file "$task_id")"
[[ -f "$state_file" ]] || die "task is not dispatched: $task_id"

owner="$(team_task_state_field "$task_id" owner)"
worker="$(team_task_state_field "$task_id" worker)"
status="$(team_task_state_field "$task_id" status)"
base_commit="$(team_task_state_field "$task_id" base_commit)"
task_commits="$(team_task_state_field "$task_id" task_commits)"
report_file="$(team_task_state_field "$task_id" report)"
architecture_required="$(team_task_state_field "$task_id" architecture_required)"
direction_status="$(team_task_state_field "$task_id" direction_status)"
direction_artifact="$(team_task_state_field "$task_id" direction_artifact)"

[[ "$owner" == "$lead_id" ]] || die "task $task_id belongs to $owner, not $lead_id"
case "$status" in
  ready_for_lead|blocked) ;;
  *) die_rule \
    "express task does not accept fix feedback: $task_id" \
    "task status is $status" \
    "send fix feedback after the worker reports ready_for_lead or blocked" ;;
esac

"$SCRIPT_DIR/team_send.sh" --from "$lead_id" --type request --task "$task_id" "$worker" "$feedback" >/dev/null

team_write_task_state \
  "$task_id" "$owner" "$worker" "" "dispatched" \
  "$base_commit" "$task_commits" "$report_file" "" \
  "" "false" "$architecture_required" "" \
  "$direction_status" "$direction_artifact"

session_id=""
exec_state="$TEAM_STATE_DIR/exec/$worker.env"
if [[ -f "$exec_state" ]]; then
  session_id="$(sed -n "s/^session_id='\{0,1\}\([0-9a-f-]*\)'\{0,1\}$/\1/p" "$exec_state" | head -n 1)"
fi
[[ -n "$session_id" ]] || die_rule \
  "express fix has no session to resume: $task_id" \
  "the last exec run of $worker left no recorded codex session id" \
  "mark the task blocked, delete its state, and dispatch it again as a new express or normal task"

resume_prompt="Leadからexpress task ${task_id}へのfix feedbackです。
${feedback}

make inbox AGENT=${worker}で届いているmessageも確認してください。
feedbackを反映し、task固有の検証とmake post-changeとmake smokeを再実行してください。
変更はmake task-commit TASK=${task_id} MESSAGE=\"<summary>\"でcommitしてください。
その後、make report TASK=${task_id} STATUS=ready_for_leadを再実行して証拠を更新し、
make team-send TO=${lead_id} TYPE=express_ready TASK=${task_id} BODY=\"<要点>\"で再報告してください。"

"$SCRIPT_DIR/team_exec_run.sh" --resume "$session_id" --kind task --ref "$task_id" --notify "$lead_id" "$worker" "$resume_prompt" >/dev/null || die_rule \
  "express fix exec launch failed: $task_id" \
  "$worker could not start a codex exec run" \
  "inspect .agents/queue/state/exec/${worker}.err, then run make express-fix again"

printf 'task=%s\nstatus=dispatched\nworker=%s\nresumed_session=%s\n' "$task_id" "$worker" "$session_id"
