#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

ensure_team_dirs

session="$(team_config_session)"

echo "Team: $(team_config_name)"
echo "Session: $session"
echo

echo "Agents:"
printf '%-12s %-12s %-18s %s\n' "id" "role" "model" "window"
while IFS='|' read -r id role cli model window command; do
  [[ -n "$id" ]] || continue
  printf '%-12s %-12s %-18s %s\n' "$id" "$role" "$model" "$window"
done < <(team_config_agents)
echo

if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$session" 2>/dev/null; then
  echo "tmux panes:"
  tmux list-panes -t "$session" -a -F '  #{pane_id} #{window_name} agent=#{@agent_id} role=#{@role} model=#{@model}'
else
  echo "tmux panes: not running"
fi
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
  state_file="$TEAM_STATE_DIR/tasks/$task_name.json"
  if [[ -f "$state_file" ]]; then
    manager="$(team_task_state_field "$task_name" manager)"
    owner="$(team_task_state_field "$task_name" owner)"
    reviewer="$(team_task_state_field "$task_name" reviewer)"
    status="$(team_task_state_field "$task_name" status)"
    head_commit="$(team_task_state_field "$task_name" head_commit)"
    review_decision="$(team_task_state_field "$task_name" review_decision)"
    done_recommendation="$(team_task_state_field "$task_name" done_recommendation)"
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
  if [[ -f "$inbox_file" ]]; then
    while IFS= read -r line; do
      message_id="$(printf '%s\n' "$line" | extract_json_field id)"
      [[ -n "$message_id" ]] || continue
      total=$((total + 1))
      if [[ ! -f "$TEAM_STATE_DIR/processed/$id/$message_id" ]]; then
        pending=$((pending + 1))
      fi
    done < "$inbox_file"
  fi
  echo "  $id pending=$pending total=$total"
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

echo "Memory proposals:"
proposal_count=0
while IFS= read -r proposal_file; do
  proposal_count=$((proposal_count + 1))
  echo "  $(basename "$proposal_file")"
done < <(find "$TEAM_QUEUE_DIR/memory_proposals" -maxdepth 1 -type f -name '*.md' | sort)
[[ "$proposal_count" -gt 0 ]] || echo "  none"
