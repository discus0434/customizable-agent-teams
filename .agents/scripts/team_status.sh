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
  case "$task_id" in GENERAL_TEMPLATE|FRONTEND_TEMPLATE) continue ;; esac
  task_count=$((task_count + 1))
  task_state="$(team_task_state_file "$task_id")"
  if [[ ! -f "$task_state" ]]; then
    printf '  %s status=not-dispatched\n' "$task_id"
    continue
  fi
  manager="$(team_task_state_field "$task_id" manager)"
  worker="$(team_task_state_field "$task_id" worker)"
  supervisor="$(team_task_state_field "$task_id" supervisor)"
  status="$(team_task_state_field "$task_id" status)"
  task_commits="$(team_task_state_field "$task_id" task_commits)"
  supervision_decision="$(team_task_state_field "$task_id" supervision_decision)"
  done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
  direction_status="$(team_task_state_field "$task_id" direction_status)"
  release_bundle="$(team_task_state_field "$task_id" release_bundle)"
  latest_commit="${task_commits##* }"
  [[ ${#latest_commit} -gt 12 ]] && latest_commit="${latest_commit:0:12}"
  line="  $task_id manager=$manager worker=$worker supervisor=$supervisor status=$status latest_commit=${latest_commit:-none} supervision=${supervision_decision:-none} done_recommendation=${done_recommendation:-false}"
  [[ "$direction_status" != "not_applicable" && -n "$direction_status" ]] && line+=" direction=$direction_status"
  progress="$(latest_task_progress_summary "$task_id")"
  [[ -n "$progress" ]] && line+=" progress=\"$progress\""
  [[ -n "$release_bundle" ]] && line+=" release_bundle=$release_bundle"
  echo "$line"
done < <(find "$TEAM_QUEUE_DIR/tasks" -maxdepth 1 -type f -name '*.md' | sort)
[[ "$task_count" -gt 0 ]] || echo "  none"
echo

echo "Research:"
research_count=0
while IFS= read -r research_state; do
  request_id="$(extract_json_field request_id < "$research_state")"
  status="$(extract_json_field status < "$research_state")"
  case "$status" in queued|active|waiting_for_caller) ;; *) continue ;; esac
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
while IFS='|' read -r id _role _cli _model _effort _window _supervisor; do
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

echo "Releases:"
release_count=0
while IFS= read -r release_state; do
  release_count=$((release_count + 1))
  bundle_id="$(basename "$release_state" .json)"
  printf '  %s manager=%s release_captain=%s status=%s decision=%s\n' \
    "$bundle_id" \
    "$(team_release_state_field "$bundle_id" manager)" \
    "$(team_release_state_field "$bundle_id" release_captain)" \
    "$(team_release_state_field "$bundle_id" status)" \
    "$(team_release_state_field "$bundle_id" decision)"
done < <(find "$TEAM_STATE_DIR/releases" -maxdepth 1 -type f -name '*.json' | sort)
[[ "$release_count" -gt 0 ]] || echo "  none"
echo

for proposal_group in "Memory proposals:$TEAM_QUEUE_DIR/memory_proposals" "Skill proposals:$TEAM_QUEUE_DIR/skill_proposals"; do
  label="${proposal_group%%:*}"
  directory="${proposal_group#*:}"
  printf '%s:\n' "$label"
  count=0
  while IFS= read -r artifact; do count=$((count + 1)); printf '  %s\n' "$(basename "$artifact")"; done < <(find "$directory" -maxdepth 1 -type f -name '*.md' | sort)
  [[ "$count" -gt 0 ]] || echo "  none"
  echo
done
