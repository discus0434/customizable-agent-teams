#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

ensure_team_dirs
team_config_validate

latest_task_progress_summary() {
  local task_id="$1"
  local progress_file
  local line
  progress_file="$(team_task_progress_file "$task_id")"
  [[ -f "$progress_file" ]] || return 0
  line="$(tail -n 1 "$progress_file")"
  [[ -n "$line" ]] || return 0
  printf '%s %s->%s' \
    "$(printf '%s\n' "$line" | extract_json_field type)" \
    "$(printf '%s\n' "$line" | extract_json_field from)" \
    "$(printf '%s\n' "$line" | extract_json_field to)"
  summary="$(printf '%s\n' "$line" | extract_json_field summary)"
  [[ -n "$summary" ]] && printf ' %s' "$summary"
  printf '\n'
}

session="$(team_config_session)"
session_running=0
printf 'Team: %s\nSession: %s\n\n' "$(team_config_name)" "$session"

echo "Agents:"
printf '%-22s %-20s %-18s %-7s %s\n' "id" "role" "model" "effort" "window"
while IFS='|' read -r id role _cli model effort window _supervisor; do
  [[ -n "$id" ]] || continue
  if team_config_role_is_exec "$role"; then
    window="(exec)"
  fi
  printf '%-22s %-20s %-18s %-7s %s\n' "$id" "$role" "$model" "$effort" "$window"
done < <(team_config_agents)
echo

if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$session" 2>/dev/null; then
  session_running=1
  echo "tmux panes:"
  tmux list-panes -s -t "$session" -F '  #{pane_id} #{window_name} agent=#{@agent_id} role=#{@role} model=#{@model}'
else
  echo "tmux panes: not running"
fi
echo

echo "Agent pane status:"
while IFS='|' read -r id role _cli _model _effort window _supervisor; do
  [[ -n "$id" ]] || continue
  if team_config_role_is_exec "$role"; then
    exec_state="$TEAM_STATE_DIR/exec/$id.env"
    pane_status="exec idle"
    if [[ -f "$exec_state" ]]; then
      pid=""
      kind=""
      ref=""
      ended_at=""
      exit_code=""
      # shellcheck disable=SC1090
      source "$exec_state"
      if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
        pane_status="exec running pid=$pid $kind=$ref"
      elif [[ -n "${ended_at:-}" ]]; then
        pane_status="exec idle last=$kind exit=$exit_code"
      fi
    fi
    printf '  %-22s %-20s %s\n' "$id" "$role" "$pane_status"
    continue
  fi
  agent_state="$TEAM_STATE_DIR/agents/$id.env"
  if [[ "$session_running" -ne 1 ]]; then
    pane_status="not-running session=$session"
  elif [[ ! -f "$agent_state" ]]; then
    pane_status="missing-state window=$window"
  else
    configured_session="$session"
    pane=""
    state_session=""
    session=""
    # shellcheck disable=SC1090
    source "$agent_state"
    state_session="${session:-}"
    session="$configured_session"
    if [[ -n "${pane:-}" ]] && team_tmux_pane_in_session "$pane" "$session"; then
      pane_status="live pane=$pane"
    else
      pane_status="missing-pane pane=${pane:-none} window=$window state_session=${state_session:-none}"
    fi
  fi
  printf '  %-22s %-20s %s\n' "$id" "$role" "$pane_status"
done < <(team_config_agents)
echo

echo "Current STATE.md:"
[[ -f "$(team_state_file)" ]] && printf '  %s\n' "$(team_state_file)" || printf '  missing: %s\n' "$(team_state_file)"
echo

echo "Tasks:"
task_count=0
while IFS= read -r task_file; do
  task_id="$(basename "$task_file" .md)"
  case "$task_id" in GENERAL_TEMPLATE|FRONTEND_TEMPLATE|EXPRESS_TEMPLATE) continue ;; esac
  task_count=$((task_count + 1))
  task_state="$(team_task_state_file "$task_id")"
  if [[ ! -f "$task_state" ]]; then
    printf '  %s status=not-dispatched\n' "$task_id"
    continue
  fi
  owner="$(team_task_state_field "$task_id" owner)"
  worker="$(team_task_state_field "$task_id" worker)"
  supervisor="$(team_task_state_field "$task_id" supervisor)"
  status="$(team_task_state_field "$task_id" status)"
  task_commits="$(team_task_state_field "$task_id" task_commits)"
  supervision_decision="$(team_task_state_field "$task_id" supervision_decision)"
  done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
  direction_status="$(team_task_state_field "$task_id" direction_status)"
  latest_commit="${task_commits##* }"
  [[ ${#latest_commit} -gt 12 ]] && latest_commit="${latest_commit:0:12}"
  line="  $task_id owner=$owner worker=$worker supervisor=$supervisor status=$status latest_commit=${latest_commit:-none} supervision=${supervision_decision:-none} done_recommendation=${done_recommendation:-false}"
  [[ "$direction_status" != "not_applicable" && -n "$direction_status" ]] && line+=" direction=$direction_status"
  progress="$(latest_task_progress_summary "$task_id")"
  [[ -n "$progress" ]] && line+=" progress=\"$progress\""
  echo "$line"
done < <(find "$TEAM_QUEUE_DIR/tasks" -maxdepth 1 -type f -name '*.md' | sort)
[[ "$task_count" -gt 0 ]] || echo "  none"
echo

echo "Research:"
research_count=0
while IFS= read -r research_state; do
  request_id="$(extract_json_field request_id < "$research_state")"
  status="$(extract_json_field status < "$research_state")"
  case "$status" in queued|active) ;; *) continue ;; esac
  research_count=$((research_count + 1))
  caller="$(extract_json_field caller < "$research_state")"
  worker="$(extract_json_field worker < "$research_state")"
  task_id="$(extract_json_field task_id < "$research_state")"
  artifact="$(extract_json_field artifact < "$research_state")"
  printf '  %s caller=%s worker=%s status=%s task=%s artifact=%s\n' "$request_id" "$caller" "${worker:-queued}" "$status" "${task_id:--}" "$artifact"
done < <(find "$TEAM_STATE_DIR/research" -maxdepth 1 -type f -name '*.json' | sort)
[[ "$research_count" -gt 0 ]] || echo "  none"
echo

echo "Inbox:"
while IFS='|' read -r id agent_role _cli _model _effort _window _supervisor; do
  [[ -n "$id" ]] || continue
  inbox_file="$TEAM_QUEUE_DIR/inbox/$id.jsonl"
  total=0
  pending=0
  latest=""
  if [[ -f "$inbox_file" ]]; then
    while IFS= read -r line; do
      message_id="$(printf '%s\n' "$line" | extract_json_field id)"
      [[ -n "$message_id" ]] || continue
      total=$((total + 1))
      if [[ ! -f "$TEAM_STATE_DIR/processed/$id/$message_id" ]]; then
        pending=$((pending + 1))
        latest="$message_id type=$(printf '%s\n' "$line" | extract_json_field type) from=$(printf '%s\n' "$line" | extract_json_field from)"
      fi
    done < "$inbox_file"
  fi
  printf '  %s pending=%s total=%s' "$id" "$pending" "$total"
  [[ -n "$latest" ]] && printf ' latest=%s' "$latest"
  # pendingを抱えたままidleのpaneは、wakeupが消えた停滞の徴候なので警告する
  if [[ "$pending" -gt 0 && "$session_running" -eq 1 ]] && ! team_config_role_is_exec "$agent_role"; then
    stalled="$(
      pane=""
      cli=""
      # shellcheck disable=SC1090
      source "$TEAM_STATE_DIR/agents/$id.env" 2>/dev/null || exit 0
      if [[ -n "$pane" ]] && team_tmux_pane_in_session "$pane" "$(team_config_session)" \
        && ! team_tmux_pane_is_busy "$pane" && ! team_tmux_input_is_pending "$pane" "$cli"; then
        printf 'stalled'
      fi
    )"
    if [[ "$stalled" == "stalled" ]]; then
      printf ' WARN: idle with pending'
    fi
  fi
  printf '\n'
done < <(team_config_agents)
echo

for artifact_group in "Reports:$TEAM_QUEUE_DIR/reports" "Reviews:$TEAM_QUEUE_DIR/reviews" "Critiques:$TEAM_QUEUE_DIR/critiques" "Direction critiques:$TEAM_QUEUE_DIR/direction-critiques" "Strategy:$TEAM_QUEUE_DIR/strategy" "Architecture:$TEAM_QUEUE_DIR/architecture"; do
  label="${artifact_group%%:*}"
  directory="${artifact_group#*:}"
  printf '%s:\n' "$label"
  count=0
  while IFS= read -r artifact; do
    count=$((count + 1))
    printf '  %s\n' "$(basename "$artifact")"
  done < <(find "$directory" -maxdepth 1 -type f -name '*.md' | sort)
  [[ "$count" -gt 0 ]] || echo "  none"
  echo
done

for proposal_group in "Memory proposals:$TEAM_QUEUE_DIR/memory_proposals" "Skill proposals:$TEAM_QUEUE_DIR/skill_proposals"; do
  label="${proposal_group%%:*}"
  directory="${proposal_group#*:}"
  printf '%s:\n' "$label"
  count=0
  while IFS= read -r artifact; do count=$((count + 1)); printf '  %s\n' "$(basename "$artifact")"; done < <(find "$directory" -maxdepth 1 -type f -name '*.md' | sort)
  [[ "$count" -gt 0 ]] || echo "  none"
  echo
done
