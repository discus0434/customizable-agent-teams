#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

pending_count() {
  local agent_id="$1"
  local inbox_file="$TEAM_QUEUE_DIR/inbox/$agent_id.jsonl"
  local processed_dir="$TEAM_STATE_DIR/processed/$agent_id"
  local count=0
  local line
  local message_id

  [[ -f "$inbox_file" ]] || {
    printf '0\n'
    return 0
  }

  mkdir -p "$processed_dir"
  while IFS= read -r line; do
    message_id="$(printf '%s\n' "$line" | extract_json_field id)"
    [[ -n "$message_id" ]] || continue
    if [[ ! -f "$processed_dir/$message_id" ]]; then
      count=$((count + 1))
    fi
  done < "$inbox_file"

  printf '%s\n' "$count"
}

main() {
  ensure_team_dirs

  managers="$(team_config_role_agent_ids manager)"
  manager_count="$(printf '%s\n' "$managers" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$manager_count" -gt 0 ]] || die_rule \
    "manager is not configured" \
    "bootstrap team startup needs a manager to receive the lead intake" \
    "add a manager agent to $TEAM_CONFIG_FILE"

  "$SCRIPT_DIR/team_start.sh" --complete-existing

  while IFS= read -r manager_id; do
    [[ -n "$manager_id" ]] || continue
    count="$(pending_count "$manager_id")"
    if [[ "$count" -gt 0 ]]; then
      "$SCRIPT_DIR/team_nudge.sh" "$manager_id" >/dev/null
      printf 'nudged %s pending=%s\n' "$manager_id" "$count"
    else
      printf '%s pending=0\n' "$manager_id"
    fi
  done <<< "$managers"

  session="$(team_config_session)"
  echo "started tmux session: $session"
  echo "attach with: tmux attach -t $session"
}

main "$@"
