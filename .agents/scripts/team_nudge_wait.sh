#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

[[ $# -eq 2 ]] || exit 2

agent_id="$1"
waiter_lock="$2"

cleanup() {
  rm -f "$waiter_lock/pid"
  rmdir "$waiter_lock" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

for _attempt in $(seq 1 7200); do
  team_inbox_has_pending "$agent_id" || exit 0

  state_file="$TEAM_STATE_DIR/agents/$agent_id.env"
  [[ -f "$state_file" ]] || exit 0
  # shellcheck disable=SC1090
  source "$state_file"
  [[ -n "${pane:-}" && -n "${session:-}" ]] || exit 0
  tmux has-session -t "$session" 2>/dev/null || exit 0
  team_tmux_pane_in_session "$pane" "$session" || exit 0

  if ! team_tmux_pane_is_busy "$pane"; then
    team_tmux_send_text "$pane" "inbox $agent_id"
    exit 0
  fi
  sleep 0.5
done
