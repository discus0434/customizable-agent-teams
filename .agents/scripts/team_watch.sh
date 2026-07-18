#!/usr/bin/env bash

# 「pendingを抱えたままidleのpane」を定期的に起こす照合loop。
# nudgeの配送は送信時の1回きりで、interruptやwaiterの喪失でwakeupが消えると
# チーム全体が静止して誰も回復できない。この常駐がlevel-triggerとして
# 消えたwakeupを回収する。team_start.shが起動し、team_stop.shが止める。
# usage: team_watch.sh [--once]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

once=0
if [[ "${1:-}" == "--once" ]]; then
  once=1
fi

require_command tmux
ensure_team_dirs
session="$(team_config_session)"

sweep() {
  local id role
  while IFS='|' read -r id role _cli _model _effort _window _supervisor; do
    [[ -n "$id" ]] || continue
    if team_config_role_is_exec "$role"; then
      continue
    fi
    if team_inbox_has_pending "$id"; then
      "$SCRIPT_DIR/team_nudge.sh" "$id" >/dev/null 2>&1 || true
    fi
  done < <(team_config_agents)
}

if [[ "$once" == "1" ]]; then
  sweep
  exit 0
fi

while tmux has-session -t "$session" 2>/dev/null; do
  sweep
  sleep "${TEAM_WATCH_INTERVAL:-60}"
done
