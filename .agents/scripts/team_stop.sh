#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

session="$(team_session_name)"

watch_pid_file="$TEAM_STATE_DIR/watch.pid"
watch_pid="$(cat "$watch_pid_file" 2>/dev/null || true)"

# watchのloopはsessionが死ねば自分で終わる。sessionが無いのに残っているpidは、
# PCの再起動をまたいで別のprocessへ再利用されたpidでありうるので、殺さない
if tmux has-session -t "$session" 2>/dev/null; then
  if [[ -n "$watch_pid" ]]; then
    kill "$watch_pid" 2>/dev/null || true
  fi
  tmux kill-session -t "$session"
  echo "stopped tmux session: $session"
else
  echo "tmux session is not running: $session"
fi

rm -f "$watch_pid_file"

