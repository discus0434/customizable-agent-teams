#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

restart=0
lead_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --restart)
      restart=1
      shift
      ;;
    --lead-only)
      lead_only=1
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
usage: team_start.sh [--restart] [--lead-only]

Starts the tmux session described in .agents/config/agent-team.yaml.
USAGE
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

write_agent_state() {
  local id="$1"
  local role="$2"
  local cli="$3"
  local model="$4"
  local window="$5"
  local command="$6"
  local pane="$7"
  local session="$8"
  local state_file="$TEAM_STATE_DIR/agents/$id.env"

  {
    printf 'agent_id=%s\n' "$(shell_quote "$id")"
    printf 'role=%s\n' "$(shell_quote "$role")"
    printf 'cli=%s\n' "$(shell_quote "$cli")"
    printf 'model=%s\n' "$(shell_quote "$model")"
    printf 'window=%s\n' "$(shell_quote "$window")"
    printf 'command=%s\n' "$(shell_quote "$command")"
    printf 'pane=%s\n' "$(shell_quote "$pane")"
    printf 'session=%s\n' "$(shell_quote "$session")"
    printf 'started_at=%s\n' "$(shell_quote "$(team_now_utc)")"
  } > "$state_file"
}

set_pane_metadata() {
  local pane="$1"
  local id="$2"
  local role="$3"
  local model="$4"

  tmux set-option -p -t "$pane" @agent_id "$id" >/dev/null
  tmux set-option -p -t "$pane" @role "$role" >/dev/null
  tmux set-option -p -t "$pane" @model "$model" >/dev/null
}

send_boot_nudge() {
  local pane="$1"
  local id="$2"
  local role="$3"
  local cli="$4"

  if [[ "${TEAM_BOOT_NUDGE:-1}" == "0" ]]; then
    return 0
  fi

  sleep "${TEAM_BOOT_NUDGE_DELAY:-1}"
  case "$role" in
    lead)
      team_tmux_wait_for_ready "$pane" "$cli" 30
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=lead agent_id=$id として待機してください。人間の指示はこの pane に直接来ます。実装や dispatch はせず、必要な擦り合わせをしてから manager に依頼します。agent 間通知は inbox $id です。"
      ;;
    manager)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=manager agent_id=$id として待機してください。STATE の主編集者として task 分解、dispatch、進捗、review 受領を担当します。通知は inbox $id です。"
      ;;
    strategist)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=strategist agent_id=$id として待機してください。strategy_request を受けたら .agents/queue/strategy/ に成果物を書きます。通知は inbox $id です。"
      ;;
    architect)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=architect agent_id=$id として待機してください。architecture_request を受けたら .agents/queue/architecture/ に技術判断を書きます。通知は inbox $id です。"
      ;;
    release-captain)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=release-captain agent_id=$id として待機してください。release_request を受けたら release bundle を確認し、SHIP/FIX/BLOCKED を返します。通知は inbox $id です。"
      ;;
    reviewer)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=reviewer agent_id=$id として待機してください。review_watch_assigned を受けたら worker と直接やりとりし、review artifact を書きます。通知は inbox $id です。"
      ;;
    worker)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=worker agent_id=$id として待機してください。task_assigned を受けたら担当 reviewer と連携して実装、検証、commit、report を行います。通知は inbox $id です。"
      ;;
    *)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=$role agent_id=$id として待機してください。通知は inbox $id です。"
      ;;
  esac
}

agent_launch_command() {
  local id="$1"
  local role="$2"
  local cli="$3"
  local model="$4"
  local session="$5"
  local command="$6"

  printf 'TEAM_AGENT_ID=%s TEAM_AGENT_ROLE=%s TEAM_AGENT_CLI=%s TEAM_AGENT_MODEL=%s TEAM_SESSION=%s TEAM_ROOT=%s TEAM_CONFIG_FILE=%s %s' \
    "$(shell_quote "$id")" \
    "$(shell_quote "$role")" \
    "$(shell_quote "$cli")" \
    "$(shell_quote "$model")" \
    "$(shell_quote "$session")" \
    "$(shell_quote "$TEAM_ROOT")" \
    "$(shell_quote "$TEAM_CONFIG_FILE")" \
    "$command"
}

main() {
  require_command tmux
  ensure_team_dirs

  local session
  session="$(team_config_session)"
  [[ -n "$session" ]] || die "team.session is missing in $TEAM_CONFIG_FILE"

  if tmux has-session -t "$session" 2>/dev/null; then
    if [[ "$restart" -eq 1 ]]; then
      tmux kill-session -t "$session"
    else
      die "tmux session already exists: $session. Use --restart to replace it."
    fi
  fi

  rm -f "$TEAM_STATE_DIR/agents/"*.env 2>/dev/null || true

  local first=1
  while IFS='|' read -r id role cli model window command; do
    [[ -n "$id" ]] || continue
    if [[ "$lead_only" -eq 1 && "$role" != "lead" ]]; then
      continue
    fi
    [[ -n "$window" ]] || window="$id"
    [[ -n "$command" ]] || die "agent $id has no command"

    local launch_command
    launch_command="$(agent_launch_command "$id" "$role" "$cli" "$model" "$session" "$command")"

    if [[ "$first" -eq 1 ]]; then
      tmux new-session -d -s "$session" -n "$window" -c "$TEAM_ROOT" "$launch_command"
      first=0
    else
      tmux new-window -d -t "$session:" -n "$window" -c "$TEAM_ROOT" "$launch_command"
    fi

    local pane
    pane="$(tmux display-message -p -t "$session:$window.0" '#{pane_id}')"
    set_pane_metadata "$pane" "$id" "$role" "$model"
    write_agent_state "$id" "$role" "$cli" "$model" "$window" "$command" "$pane" "$session"
    team_tmux_accept_startup_prompt "$pane" "$cli" 10
    send_boot_nudge "$pane" "$id" "$role" "$cli"
  done < <(team_config_agents)

  tmux set-option -t "$session" status on >/dev/null
  tmux set-option -t "$session" pane-border-status top >/dev/null
  tmux set-option -t "$session" pane-border-format '#{@agent_id} #{@role} #{@model}' >/dev/null

  echo "started tmux session: $session"
  echo "attach with: tmux attach -t $session"
}

main "$@"
