#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

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
configured_session="$(team_config_session)"

if [[ ! -f "$state_file" ]]; then
  if [[ -n "$configured_session" ]] && ! tmux has-session -t "$configured_session" 2>/dev/null; then
    echo "[team] queued for $agent_id; tmux session is not running yet" >&2
    exit 0
  fi
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
  echo "[team] queued for $agent_id; tmux session is not running yet" >&2
  exit 0
fi

if ! team_tmux_pane_in_session "$pane" "$session"; then
  warn "tmux pane is not running for $agent_id: $pane"
  exit 1
fi

team_tmux_send_text "$pane" "inbox $agent_id"
