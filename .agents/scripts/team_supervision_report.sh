#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_supervision_report.sh <task_id> <OK|FIX|ASK_MANAGER>" >&2
}

[[ $# -eq 2 ]] || { usage; exit 2; }

task_id="$1"
decision="$2"
[[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
  "supervisor identity is unavailable" \
  "the final decision belongs to the assigned supervisor pane" \
  "run make supervision-report inside the assigned supervisor pane"
supervisor_id="$TEAM_AGENT_ID"

case "$decision" in
  OK|FIX|ASK_MANAGER) ;;
  *) die "invalid supervision decision: $decision" ;;
esac

team_config_agent_record "$supervisor_id" >/dev/null || die "unknown supervisor: $supervisor_id"
supervisor_role="$(team_config_agent_field "$supervisor_id" role)"
case "$supervisor_role" in
  general-reviewer|frontend-critic) ;;
  *) die "$supervisor_id is not an implementation supervisor" ;;
esac

ensure_team_dirs
state_file="$(team_task_state_file "$task_id")"
[[ -f "$state_file" ]] || die "task is not dispatched: $task_id"

worker="$(team_task_state_field "$task_id" worker)"
manager="$(team_task_state_field "$task_id" manager)"
assigned_supervisor="$(team_task_state_field "$task_id" supervisor)"
base_commit="$(team_task_state_field "$task_id" base_commit)"
head_commit="$(team_task_state_field "$task_id" head_commit)"
report_file="$(team_task_state_field "$task_id" report)"
architecture_required="$(team_task_state_field "$task_id" architecture_required)"
architecture="$(team_task_state_field "$task_id" architecture)"
release_bundle="$(team_task_state_field "$task_id" release_bundle)"
direction_status="$(team_task_state_field "$task_id" direction_status)"
direction_artifact="$(team_task_state_field "$task_id" direction_artifact)"

[[ "$assigned_supervisor" == "$supervisor_id" ]] || die_rule \
  "supervisor is not assigned to task $task_id" \
  "task state names $assigned_supervisor, but the command uses $supervisor_id" \
  "run the command from the fixed supervisor pane"
[[ -n "$manager" && -n "$worker" && -n "$base_commit" ]] || die "task $task_id state is incomplete"
[[ -n "$head_commit" ]] || die_rule \
  "task has no reported head commit: $task_id" \
  "supervision starts after the implementation worker writes a report" \
  "worker must run make report and fill the report evidence"
[[ -n "$report_file" && -f "$report_file" ]] || die_rule \
  "task report is missing: $task_id" \
  "supervision requires the implementation report" \
  "worker must run make report before ready_for_supervision"
team_require_report_matches_task_state "$task_id" "$report_file" "$base_commit" "$head_commit"
team_require_no_placeholders "implementation report" "$report_file"

case "$supervisor_role" in
  general-reviewer)
    supervision_file="$TEAM_QUEUE_DIR/reviews/${task_id}_${supervisor_id}.md"
    worker_role="$(team_config_agent_field "$worker" role)"
    case "$worker_role" in
      general-worker|hard-task-worker) ;;
      *) die "general-reviewer cannot supervise $worker_role" ;;
    esac
    ;;
  frontend-critic)
    supervision_file="$TEAM_QUEUE_DIR/critiques/${task_id}_${supervisor_id}.md"
    worker_role="$(team_config_agent_field "$worker" role)"
    [[ "$worker_role" == "frontend-worker" ]] || die "frontend-critic cannot supervise $worker_role"
    case "$direction_status" in
      proceed|not_needed) ;;
      *) die_rule \
        "frontend direction is unresolved: $task_id" \
        "direction_status=$direction_status, but final critique requires PROCEED or NOT_NEEDED" \
        "resolve view direction before recording final supervision" ;;
    esac
    ;;
esac

[[ -f "$supervision_file" ]] || die_rule \
  "supervision artifact is missing: $(team_relative_path "$supervision_file")" \
  "$supervisor_role must write its completed final artifact before recording a decision" \
  "write the artifact with summary, findings, evidence reviewed, coordination, and manager escalation"
team_require_no_placeholders "supervision artifact" "$supervision_file"
for required_section in Summary Findings "Evidence Reviewed" Coordination; do
  grep -q "^## $required_section$" "$supervision_file" || die_rule \
    "supervision artifact section is missing: $required_section" \
    "$(team_relative_path "$supervision_file") must make the final judgment auditable" \
    "add a substantive '## $required_section' section"
  team_markdown_section_has_content "$supervision_file" "$required_section" || die_rule \
    "supervision artifact section is empty: $required_section" \
    "$(team_relative_path "$supervision_file") does not record the supervisor's work" \
    "fill '## $required_section' before recording the decision"
done
if [[ "$supervisor_role" == "frontend-critic" ]]; then
  grep -q '^## Visual Evidence Reviewed$' "$supervision_file" || die_rule \
    "frontend critique has no Visual Evidence Reviewed section" \
    "the critic must independently inspect the rendered result" \
    "add screenshot paths, devices or viewports, states, and interaction checks"
  team_markdown_section_has_content "$supervision_file" "Visual Evidence Reviewed" || die_rule \
    "frontend critique visual evidence is empty" \
    "the final decision must identify what the critic actually inspected" \
    "record the visual evidence and interaction checks"
fi

case "$decision" in
  OK)
    done_recommendation="true"
    done_recommendation_text="yes"
    next_status="supervision_ok"
    target="$manager"
    message="Supervision Decision: OK. Done recommendation: yes. $(team_relative_path "$supervision_file") を確認し、全体制約に問題がなければ task を done にしてください。"
    ;;
  FIX)
    done_recommendation="false"
    done_recommendation_text="no"
    next_status="supervision_fix"
    target="$worker"
    message="Supervision Decision: FIX. Done recommendation: no. $(team_relative_path "$supervision_file") を確認し、修正、検証、commit、report 更新後に ready_for_supervision を送ってください。"
    ;;
  ASK_MANAGER)
    done_recommendation="false"
    done_recommendation_text="no"
    next_status="supervision_ask_manager"
    target="$manager"
    message="Supervision Decision: ASK_MANAGER. Done recommendation: no. $(team_relative_path "$supervision_file") を確認し、判断または Lead への escalation を行ってください。"
    ;;
esac

team_update_markdown_field "$supervision_file" "Decision" "$decision"
team_update_markdown_field "$supervision_file" "Done recommendation" "$done_recommendation_text"
team_update_markdown_field "$supervision_file" "Task" ".agents/queue/tasks/$task_id.md"
team_update_markdown_field "$supervision_file" "Worker" "$worker"
team_update_markdown_field "$supervision_file" "Report" "$(team_relative_path "$report_file")"
team_update_markdown_field "$supervision_file" "Base commit" "$base_commit"
team_update_markdown_field "$supervision_file" "Head commit" "$head_commit"

team_update_markdown_field "$report_file" "Supervision artifact" "$(team_relative_path "$supervision_file")"
team_update_markdown_field "$report_file" "Supervision decision" "$decision"
team_update_markdown_field "$report_file" "Done recommendation" "$done_recommendation"

team_write_task_state \
  "$task_id" \
  "$manager" \
  "$worker" \
  "$supervisor_id" \
  "$next_status" \
  "$base_commit" \
  "$head_commit" \
  "$report_file" \
  "$supervision_file" \
  "$decision" \
  "$done_recommendation" \
  "$architecture_required" \
  "$architecture" \
  "$release_bundle" \
  "$direction_status" \
  "$direction_artifact"

"$SCRIPT_DIR/team_send.sh" --from "$supervisor_id" --type supervision_result --task "$task_id" --done-recommendation "$done_recommendation" "$target" "$message" >/dev/null
team_mark_inbox_processed "$supervisor_id" "$task_id" ""
printf '%s\n' "$supervision_file"
