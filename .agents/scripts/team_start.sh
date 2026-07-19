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
  local _attempt

  if [[ "${TEAM_BOOT_NUDGE:-1}" == "0" ]]; then
    return 0
  fi

  sleep "${TEAM_BOOT_NUDGE_DELAY:-1}"
  # 起動の遅いmachineではTUIの準備前に貼り付けが始まり、送信確認が失敗する。
  # roleを問わずreadyを待つ。待つのは実際の起動時間だけで、間に合わない
  # 場合も致命傷にしない(paneは動いていて、promptは後から渡し直せる)
  for _attempt in $(seq 1 "${TEAM_BOOT_NUDGE_READY_TIMEOUT:-60}"); do
    if team_tmux_content_is_ready "$(team_tmux_capture_pane "$pane")" "$cli"; then
      if team_tmux_send_text "$pane" "AGENTS.mdを読み、role=${role}、agent_id=${id}としてinbox ${id}で待機してください。"; then
        return 0
      fi
      return 1
    fi
    sleep 1
  done
  warn "pane did not become ready for the boot nudge: $id ($pane)"
  return 1
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
  ensure_state_dirs
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
  local -a unconfirmed_nudges=()
  while IFS='|' read -r id role cli model effort window supervisor; do
    [[ -n "$id" ]] || continue
    if team_config_role_is_exec "$role"; then
      continue
    fi
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
    # nudgeの不達はこのpaneだけの問題なので、残りのagentの起動を止めない
    if ! send_boot_nudge "$pane" "$id" "$role" "$cli"; then
      unconfirmed_nudges+=("$id")
    fi
    team_tmux_require_pane "$id" "$pane" "$session" "$window"
    write_agent_state "$id" "$role" "$cli" "$model" "$effort" "$window" "$supervisor" "$command" "$pane" "$session"
  done < <(team_config_agents)

  tmux set-option -t "$session" status on >/dev/null
  tmux set-option -t "$session" pane-border-status top >/dev/null
  tmux set-option -t "$session" pane-border-format '#{@agent_id} #{@role} #{@model}' >/dev/null

  while IFS='|' read -r id role _cli _model _effort _window _supervisor; do
    [[ -n "$id" ]] || continue
    if team_config_role_is_exec "$role"; then
      continue
    fi
    if [[ "$lead_only" -eq 1 && "$role" != "lead" ]]; then
      continue
    fi
    if team_inbox_has_pending "$id"; then
      "$SCRIPT_DIR/team_nudge.sh" "$id" >/dev/null || warn "startup nudge failed for $id; pending inbox messages remain"
    fi
  done < <(team_config_agents)

  # 消えたwakeupを回収する照合loopを常駐させる(多重起動はpidで防ぐ)
  local watch_pid_file="$TEAM_STATE_DIR/watch.pid"
  local watch_pid
  watch_pid="$(cat "$watch_pid_file" 2>/dev/null || true)"
  if [[ -z "$watch_pid" ]] || ! kill -0 "$watch_pid" 2>/dev/null; then
    watch_pid="$(
      TEAM_ROOT="$TEAM_ROOT" TEAM_CONFIG_FILE="$TEAM_CONFIG_FILE" \
        bash -c 'set -m; nohup "$1" >/dev/null 2>&1 & echo $!' _ "$SCRIPT_DIR/team_watch.sh"
    )"
    printf '%s\n' "$watch_pid" > "$watch_pid_file"
  fi

  if [[ "${#unconfirmed_nudges[@]}" -gt 0 ]]; then
    die_rule \
      "boot nudge was not confirmed for: ${unconfirmed_nudges[*]}" \
      "the panes are running, but their identity prompt could not be verified" \
      "attach with make team-attach, check those panes, and paste the boot prompt manually if it is missing"
  fi

  echo "started tmux session: $session"
  echo "attach with: make team-attach"
}

main "$@"
