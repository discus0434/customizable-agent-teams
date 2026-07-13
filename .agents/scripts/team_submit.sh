#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

usage() {
  echo "usage: team_submit.sh <agent_id>" >&2
}

[[ $# -eq 1 ]] || { usage; exit 2; }

agent_id="$1"

require_command tmux
state_file="$TEAM_STATE_DIR/agents/$agent_id.env"

if [[ ! -f "$state_file" ]]; then
  die "no pane state for $agent_id"
fi

# shellcheck disable=SC1090
source "$state_file"

if [[ -z "${pane:-}" || -z "${session:-}" ]]; then
  die "pane state for $agent_id is incomplete"
fi

if ! tmux has-session -t "$session" 2>/dev/null; then
  die "tmux session is not running: $session"
fi

team_tmux_require_pane "$agent_id" "$pane" "$session" "${window:-$agent_id}"
team_tmux_cancel_mode_if_needed "$pane"
team_tmux_submit "$pane"
