#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_direction_report.sh <task_id> <PROCEED|REVISE|NOT_NEEDED|ASK_MANAGER> [rationale_file]" >&2
}

[[ $# -ge 2 && $# -le 3 ]] || { usage; exit 2; }

task_id="$1"
decision="$2"
rationale_file="${3:-}"
[[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
  "critic identity is unavailable" \
  "view direction decisions belong to the assigned frontend-critic pane" \
  "run make direction-report inside the assigned critic pane"
critic_id="$TEAM_AGENT_ID"

case "$decision" in
  PROCEED|REVISE|NOT_NEEDED|ASK_MANAGER) ;;
  *) die "invalid direction decision: $decision" ;;
esac

team_config_agent_record "$critic_id" >/dev/null || die "unknown critic: $critic_id"
critic_role="$(team_config_agent_field "$critic_id" role)"
[[ "$critic_role" == "frontend-critic" ]] || die "$critic_id is not a frontend-critic"

ensure_team_dirs
state_file="$(team_task_state_file "$task_id")"
[[ -f "$state_file" ]] || die "task is not dispatched: $task_id"

worker="$(team_task_state_field "$task_id" worker)"
owner="$(team_task_state_field "$task_id" owner)"
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

[[ "$supervisor" == "$critic_id" ]] || die "task $task_id critic is $supervisor, not $critic_id"
worker_role="$(team_config_agent_field "$worker" role)"
[[ "$worker_role" == "frontend-worker" ]] || die "direction decisions apply only to frontend tasks"

direction_file="$TEAM_QUEUE_DIR/direction-critiques/${task_id}_${critic_id}.md"
case "$decision" in
  NOT_NEEDED)
    [[ -n "$rationale_file" && -f "$rationale_file" ]] || die_rule \
      "NOT_NEEDED requires a rationale file" \
      "the critic must explain why the task does not change view direction" \
      "write a short rationale and pass BODY_FILE=<path>"
    body="$(<"$rationale_file")"
    direction_status="not_needed"
    direction_artifact=""
    target="$worker"
    ;;
  PROCEED|REVISE|ASK_MANAGER)
    [[ -f "$direction_file" ]] || die_rule \
      "direction critique is missing: $(team_relative_path "$direction_file")" \
      "$decision requires a written view-direction critique" \
      "write the direction critique before recording the decision"
    team_require_no_placeholders "direction critique" "$direction_file"
    for required_section in "Direction Reviewed" Critique; do
      grep -q "^## $required_section$" "$direction_file" || die_rule \
        "direction critique section is missing: $required_section" \
        "the view-direction decision needs a concise rationale" \
        "add a substantive '## $required_section' section"
      team_markdown_section_has_content "$direction_file" "$required_section" || die_rule \
        "direction critique section is empty: $required_section" \
        "the critic decision must explain what was reviewed" \
        "fill '## $required_section' before recording the decision"
    done
    team_update_markdown_field "$direction_file" "Decision" "$decision"
    team_update_markdown_field "$direction_file" "Task" ".agents/queue/tasks/$task_id.md"
    team_update_markdown_field "$direction_file" "Worker" "$worker"
    direction_artifact="$(team_relative_path "$direction_file")"
    body="View direction decision: ${decision}。${direction_artifact}を確認してください。"
    case "$decision" in
      PROCEED) direction_status="proceed"; target="$worker" ;;
      REVISE) direction_status="revise"; target="$worker" ;;
      ASK_MANAGER) direction_status="ask_manager"; target="$owner" ;;
    esac
    ;;
esac

team_write_task_state \
  "$task_id" "$owner" "$worker" "$supervisor" "$status" \
  "$base_commit" "$task_commits" "$report_file" "$supervision_artifact" \
  "$supervision_decision" "${done_recommendation:-false}" "$architecture_required" \
  "$architecture" "$direction_status" "$direction_artifact"

"$SCRIPT_DIR/team_send.sh" --from "$critic_id" --type view_direction_result --task "$task_id" "$target" "$body" >/dev/null
team_mark_inbox_processed "$critic_id" "$task_id" view_direction_ready
printf 'direction_status=%s\n' "$direction_status"
[[ -n "$direction_artifact" ]] && printf 'direction_artifact=%s\n' "$direction_artifact"
