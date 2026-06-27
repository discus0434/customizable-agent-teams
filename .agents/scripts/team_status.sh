#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

ensure_team_dirs

session="$(team_config_session)"
session_running=0

echo "Team: $(team_config_name)"
echo "Session: $session"
echo

echo "Agents:"
printf '%-16s %-16s %-18s %s\n' "id" "role" "model" "window"
while IFS='|' read -r id role cli model window command; do
  [[ -n "$id" ]] || continue
  printf '%-16s %-16s %-18s %s\n' "$id" "$role" "$model" "$window"
done < <(team_config_agents)
echo

if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$session" 2>/dev/null; then
  session_running=1
  echo "tmux panes:"
  tmux list-panes -t "$session" -F '  #{pane_id} #{window_name} agent=#{@agent_id} role=#{@role} model=#{@model}'
else
  echo "tmux panes: not running"
fi
echo

echo "Agent pane status:"
while IFS='|' read -r id role cli model window command; do
  [[ -n "$id" ]] || continue
  state_file="$TEAM_STATE_DIR/agents/$id.env"
  pane=""
  state_session=""
  status=""
  detail=""
  if [[ "$session_running" -ne 1 ]]; then
    status="not-running"
    detail="session=$session"
  elif [[ ! -f "$state_file" ]]; then
    status="missing-state"
    detail="window=$window"
  else
    configured_session="$session"
    pane=""
    session=""
    # shellcheck disable=SC1090
    source "$state_file"
    state_session="${session:-}"
    session="$configured_session"
    if [[ -z "${pane:-}" || -z "$state_session" ]]; then
      status="incomplete-state"
      detail="window=$window"
    elif team_tmux_pane_exists "$pane"; then
      status="live"
      detail="pane=$pane"
    else
      status="missing-pane"
      detail="pane=$pane window=$window"
    fi
  fi
  printf '  %-16s %-16s %s %s\n' "$id" "$role" "$status" "$detail"
done < <(team_config_agents)
echo

echo "Current STATE.md:"
state_file="$(team_state_file)"
if [[ -f "$state_file" ]]; then
  echo "  $state_file"
else
  echo "  missing: $state_file"
fi
echo

echo "Tasks:"
task_count=0
while IFS= read -r task_file; do
  task_name="$(basename "$task_file" .md)"
  [[ "$task_name" == "TEMPLATE" ]] && continue
  task_count=$((task_count + 1))
  manager="unassigned"
  owner="unassigned"
  reviewer="unassigned"
  status="no-state"
  head_commit=""
  review_decision=""
  done_recommendation=""
  strategy_artifact=""
  architecture_required=""
  architecture=""
  release_bundle=""
  state_file="$TEAM_STATE_DIR/tasks/$task_name.json"
  if [[ -f "$state_file" ]]; then
    manager="$(team_task_state_field "$task_name" manager)"
    owner="$(team_task_state_field "$task_name" owner)"
    reviewer="$(team_task_state_field "$task_name" reviewer)"
    status="$(team_task_state_field "$task_name" status)"
    head_commit="$(team_task_state_field "$task_name" head_commit)"
    review_decision="$(team_task_state_field "$task_name" review_decision)"
    done_recommendation="$(team_task_state_field "$task_name" done_recommendation)"
    architecture_required="$(team_task_state_field "$task_name" architecture_required)"
    architecture="$(team_task_state_field "$task_name" architecture)"
    release_bundle="$(team_task_state_field "$task_name" release_bundle)"
  fi
  while IFS= read -r candidate; do
    strategy_artifact="$(team_relative_path "$candidate")"
  done < <(find "$TEAM_QUEUE_DIR/strategy" -maxdepth 1 -type f -name "${task_name}_*.md" | sort)
  short_head="$head_commit"
  [[ ${#short_head} -gt 12 ]] && short_head="${short_head:0:12}"
  line="  $task_name manager=${manager:-none} owner=${owner:-none} reviewer=${reviewer:-none} status=$status head=${short_head:-none} review=${review_decision:-none} done_recommendation=${done_recommendation:-false}"
  if [[ -n "$strategy_artifact" ]]; then
    line="$line strategy=$strategy_artifact"
  fi
  if [[ "$architecture_required" == "true" || -n "$architecture" ]]; then
    line="$line architecture_required=${architecture_required:-false}"
    if [[ -n "$architecture" ]]; then
      line="$line architecture=$architecture"
    fi
  fi
  if [[ -n "$release_bundle" ]]; then
    line="$line release_bundle=$release_bundle"
  fi
  echo "$line"
done < <(find "$TEAM_QUEUE_DIR/tasks" -maxdepth 1 -type f -name '*.md' | sort)
[[ "$task_count" -gt 0 ]] || echo "  none"
echo

echo "Inbox:"
while IFS='|' read -r id role cli model window command; do
  [[ -n "$id" ]] || continue
  inbox_file="$TEAM_QUEUE_DIR/inbox/$id.jsonl"
  total=0
  pending=0
  latest_pending_id=""
  latest_pending_type=""
  latest_pending_from=""
  if [[ -f "$inbox_file" ]]; then
    while IFS= read -r line; do
      message_id="$(printf '%s\n' "$line" | extract_json_field id)"
      [[ -n "$message_id" ]] || continue
      total=$((total + 1))
      if [[ ! -f "$TEAM_STATE_DIR/processed/$id/$message_id" ]]; then
        pending=$((pending + 1))
        latest_pending_id="$message_id"
        latest_pending_type="$(printf '%s\n' "$line" | extract_json_field type)"
        latest_pending_from="$(printf '%s\n' "$line" | extract_json_field from)"
      fi
    done < "$inbox_file"
  fi
  if [[ "$pending" -gt 0 ]]; then
    echo "  $id pending=$pending total=$total latest=$latest_pending_id type=$latest_pending_type from=$latest_pending_from"
  else
    echo "  $id pending=0 total=$total"
  fi
done < <(team_config_agents)
echo

echo "Reports:"
report_count=0
while IFS= read -r report_file; do
  report_count=$((report_count + 1))
  echo "  $(basename "$report_file")"
done < <(find "$TEAM_QUEUE_DIR/reports" -maxdepth 1 -type f -name '*.md' | sort)
[[ "$report_count" -gt 0 ]] || echo "  none"
echo

echo "Reviews:"
review_count=0
while IFS= read -r review_file; do
  review_count=$((review_count + 1))
  echo "  $(basename "$review_file")"
done < <(find "$TEAM_QUEUE_DIR/reviews" -maxdepth 1 -type f -name '*.md' | sort)
[[ "$review_count" -gt 0 ]] || echo "  none"
echo

echo "Strategy:"
strategy_count=0
while IFS= read -r strategy_file; do
  strategy_count=$((strategy_count + 1))
  echo "  $(basename "$strategy_file")"
done < <(find "$TEAM_QUEUE_DIR/strategy" -maxdepth 1 -type f -name '*.md' | sort)
[[ "$strategy_count" -gt 0 ]] || echo "  none"
echo

echo "Architecture:"
architecture_count=0
while IFS= read -r architecture_file; do
  architecture_count=$((architecture_count + 1))
  echo "  $(basename "$architecture_file")"
done < <(find "$TEAM_QUEUE_DIR/architecture" -maxdepth 1 -type f -name '*.md' | sort)
[[ "$architecture_count" -gt 0 ]] || echo "  none"
echo

echo "Releases:"
release_count=0
while IFS= read -r release_state_file; do
  release_count=$((release_count + 1))
  bundle_id="$(basename "$release_state_file" .json)"
  release_manager="$(team_release_state_field "$bundle_id" manager)"
  release_captain="$(team_release_state_field "$bundle_id" release_captain)"
  release_status="$(team_release_state_field "$bundle_id" status)"
  release_decision="$(team_release_state_field "$bundle_id" decision)"
  bundle_artifact="$(team_release_state_field "$bundle_id" bundle_artifact)"
  review_artifact="$(team_release_state_field "$bundle_id" review_artifact)"
  echo "  $bundle_id manager=${release_manager:-none} release_captain=${release_captain:-none} status=${release_status:-none} decision=${release_decision:-none} bundle=$(team_relative_path "$bundle_artifact") review=$(team_relative_path "$review_artifact")"
done < <(find "$TEAM_STATE_DIR/releases" -maxdepth 1 -type f -name '*.json' | sort)
[[ "$release_count" -gt 0 ]] || echo "  none"
echo

echo "Memory proposals:"
proposal_count=0
while IFS= read -r proposal_file; do
  proposal_count=$((proposal_count + 1))
  echo "  $(basename "$proposal_file")"
done < <(find "$TEAM_QUEUE_DIR/memory_proposals" -maxdepth 1 -type f -name '*.md' | sort)
[[ "$proposal_count" -gt 0 ]] || echo "  none"

echo
echo "Skill proposals:"
skill_proposal_count=0
while IFS= read -r proposal_file; do
  skill_proposal_count=$((skill_proposal_count + 1))
  echo "  $(basename "$proposal_file")"
done < <(find "$TEAM_QUEUE_DIR/skill_proposals" -maxdepth 1 -type f -name '*.md' | sort)
[[ "$skill_proposal_count" -gt 0 ]] || echo "  none"
