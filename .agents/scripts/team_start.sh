#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

restart=0
lead_only=0
complete_existing=0

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
    --complete-existing)
      complete_existing=1
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
usage: team_start.sh [--restart] [--lead-only] [--complete-existing]

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
  local effort="$5"
  local window="$6"
  local supervisor="$7"
  local command="$8"
  local pane="$9"
  local session="${10}"
  local state_file="$TEAM_STATE_DIR/agents/$id.env"

  {
    printf 'agent_id=%s\n' "$(shell_quote "$id")"
    printf 'role=%s\n' "$(shell_quote "$role")"
    printf 'cli=%s\n' "$(shell_quote "$cli")"
    printf 'model=%s\n' "$(shell_quote "$model")"
    printf 'effort=%s\n' "$(shell_quote "$effort")"
    printf 'window=%s\n' "$(shell_quote "$window")"
    printf 'supervisor=%s\n' "$(shell_quote "$supervisor")"
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

agent_state_is_live() {
  local id="$1"
  local configured_session="$2"
  local state_file="$TEAM_STATE_DIR/agents/$id.env"
  local pane=""
  local state_session=""
  local session=""

  [[ -f "$state_file" ]] || return 1

  pane=""
  session=""
  # shellcheck disable=SC1090
  source "$state_file"
  state_session="${session:-}"
  session="$configured_session"

  [[ -n "${pane:-}" && "$state_session" == "$configured_session" ]] || return 1
  team_tmux_pane_in_session "$pane" "$configured_session"
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
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=manager agent_id=$id として待機してください。STATE の主編集者として task 分解、dispatch、進捗、supervision result 受領を担当します。通知は inbox $id です。"
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
    general-reviewer)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=general-reviewer agent_id=$id として待機してください。supervision_assigned を受けたら固定ペアの general-worker と直接やりとりし、task-local supervision と final review を行います。通知は inbox $id です。"
      ;;
    general-worker)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=general-worker agent_id=$id として待機してください。task_assigned を受けたら固定 supervisor と連携して実装、検証、commit、report を行います。通知は inbox $id です。"
      ;;
    research-worker)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=research-worker agent_id=$id として待機してください。research_request を受けたら事実と根拠を中心に調査し、指定 artifact に結果を書いて caller へ返します。project code は編集しません。通知は inbox $id です。"
      ;;
    frontend-worker)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=frontend-worker agent_id=$id として待機してください。task_assigned を受けたら frontend-critic と view direction を固め、実画面を確認しながら実装、検証、commit、report を行います。通知は inbox $id です。"
      ;;
    frontend-critic)
      team_tmux_send_text "$pane" "AGENTS.md を読み、role=frontend-critic agent_id=$id として待機してください。supervision_assigned を受けたら view direction と実画面品質を厳しく確認し、task 全体の final critique を行います。project code は編集しません。通知は inbox $id です。"
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
  local effort="$5"
  local supervisor="$6"
  local session="$7"
  local command="$8"

  printf 'TEAM_AGENT_ID=%s TEAM_AGENT_ROLE=%s TEAM_AGENT_CLI=%s TEAM_AGENT_MODEL=%s TEAM_AGENT_EFFORT=%s TEAM_AGENT_SUPERVISOR=%s TEAM_SESSION=%s TEAM_ROOT=%s TEAM_CONFIG_FILE=%s %s' \
    "$(shell_quote "$id")" \
    "$(shell_quote "$role")" \
    "$(shell_quote "$cli")" \
    "$(shell_quote "$model")" \
    "$(shell_quote "$effort")" \
    "$(shell_quote "$supervisor")" \
    "$(shell_quote "$session")" \
    "$(shell_quote "$TEAM_ROOT")" \
    "$(shell_quote "$TEAM_CONFIG_FILE")" \
    "$command"
}

main() {
  require_command tmux
  ensure_team_dirs
  team_config_validate

  local session
  session="$(team_config_session)"
  [[ -n "$session" ]] || die "team.session is missing in $TEAM_CONFIG_FILE"
  [[ "$restart" -eq 0 || "$complete_existing" -eq 0 ]] || die_rule \
    "conflicting start options" \
    "--restart replaces the session while --complete-existing preserves live panes" \
    "choose either --restart or --complete-existing"

  local session_exists=0
  if tmux has-session -t "$session" 2>/dev/null; then
    session_exists=1
    if [[ "$restart" -eq 1 ]]; then
      tmux kill-session -t "$session"
      session_exists=0
    else
      [[ "$complete_existing" -eq 1 ]] || die "tmux session already exists: $session. Use --restart to replace it."
    fi
  fi

  if [[ "$complete_existing" -eq 0 || "$session_exists" -eq 0 ]]; then
    rm -f "$TEAM_STATE_DIR/agents/"*.env 2>/dev/null || true
  fi

  local first=1
  [[ "$session_exists" -eq 1 ]] && first=0
  while IFS='|' read -r id role cli model effort window supervisor; do
    [[ -n "$id" ]] || continue
    if [[ "$lead_only" -eq 1 && "$role" != "lead" ]]; then
      continue
    fi
    if [[ "$complete_existing" -eq 1 && "$session_exists" -eq 1 ]] && agent_state_is_live "$id" "$session"; then
      continue
    fi
    [[ -n "$window" ]] || window="$id"
    command="$(team_config_agent_command "$id")"

    local launch_command
    launch_command="$(agent_launch_command "$id" "$role" "$cli" "$model" "$effort" "$supervisor" "$session" "$command")"

    if [[ "$first" -eq 1 ]]; then
      tmux new-session -d -s "$session" -n "$window" -c "$TEAM_ROOT" "$launch_command"
      first=0
    else
      tmux new-window -d -t "$session:" -n "$window" -c "$TEAM_ROOT" "$launch_command"
    fi

    local pane
    if ! pane="$(tmux display-message -p -t "$session:$window.0" '#{pane_id}')"; then
      die_rule \
        "tmux pane is not running for agent $id" \
        "the configured window $window in session $session exited or could not be found" \
        "fix the agent command in $TEAM_CONFIG_FILE, then run make team-start again"
    fi
    team_tmux_require_pane "$id" "$pane" "$session" "$window"
    set_pane_metadata "$pane" "$id" "$role" "$model"
    team_tmux_accept_startup_prompt "$pane" "$cli" 10
    team_tmux_require_pane "$id" "$pane" "$session" "$window"
    send_boot_nudge "$pane" "$id" "$role" "$cli"
    team_tmux_require_pane "$id" "$pane" "$session" "$window"
    write_agent_state "$id" "$role" "$cli" "$model" "$effort" "$window" "$supervisor" "$command" "$pane" "$session"
  done < <(team_config_agents)

  tmux set-option -t "$session" status on >/dev/null
  tmux set-option -t "$session" pane-border-status top >/dev/null
  tmux set-option -t "$session" pane-border-format '#{@agent_id} #{@role} #{@model}' >/dev/null

  echo "started tmux session: $session"
  echo "attach with: make team-attach"
}

main "$@"
