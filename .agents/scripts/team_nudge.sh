#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

usage() {
  echo "usage: team_nudge.sh <agent_id>" >&2
}

[[ $# -eq 1 ]] || { usage; exit 2; }

agent_id="$1"

if [[ "${TEAM_DISABLE_NUDGE:-0}" == "1" ]]; then
  exit 0
fi

require_command tmux
state_file="$TEAM_STATE_DIR/agents/$agent_id.env"

if [[ ! -f "$state_file" ]]; then
  warn "no pane state for $agent_id; message was written but no tmux nudge was sent"
  exit 1
fi

# shellcheck disable=SC1090
source "$state_file"

if [[ -z "${pane:-}" || -z "${session:-}" ]]; then
  warn "pane state for $agent_id is incomplete"
  exit 1
fi

if ! tmux has-session -t "$session" 2>/dev/null; then
  warn "tmux session is not running: $session"
  exit 1
fi

if ! team_tmux_pane_in_session "$pane" "$session"; then
  warn "tmux pane is not running for $agent_id: $pane"
  exit 1
fi

team_tmux_cancel_mode_if_needed "$pane"
tmux send-keys -t "$pane" C-u
tmux send-keys -t "$pane" -l "inbox $agent_id"
team_tmux_submit "$pane"
