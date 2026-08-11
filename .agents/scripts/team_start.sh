#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

# CLIが立ち上がるまでpaneを待つ上限。起動時の確認dialogもこの間に答える
TEAM_STARTUP_TIMEOUT=10

restart=0
lead_only=0
prompt=""

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
    --prompt)
      [[ $# -ge 2 ]] || die "--prompt needs a value"
      prompt="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'USAGE'
usage: team_start.sh [--restart] [--lead-only] [--prompt <text>]

Brings this repository's tmux session to the shape described in
.agents/config/agent-team.yaml: live agents are left alone, missing agents are
created. The session name is derived from the repository, so teams running in
other checkouts are never touched.
--restart kills the session first and rebuilds every agent.
--prompt replaces the boot prompt each agent starts with.
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

# paneは起動直後に死ぬことがある。tmuxの生のerrorを人間へ漏らさず、
# 失敗として返して呼び出し側のdead agent扱いに合流させる
set_pane_metadata() {
  local pane="$1"
  local id="$2"
  local role="$3"
  local model="$4"

  tmux set-option -p -t "$pane" @agent_id "$id" >/dev/null 2>&1 || return 1
  tmux set-option -p -t "$pane" @role "$role" >/dev/null 2>&1 || return 1
  tmux set-option -p -t "$pane" @model "$model" >/dev/null 2>&1 || return 1
}

# sessionと寿命を共にするruntime stateを捨てる。paneのstate、督促waiterのlock、
# watchのpidは、いずれもそのsessionが生きている間だけ意味を持つ。
# PCの再起動をまたぐとpidは別のprocessへ再利用されるので、生存確認では
# 見分けられない。sessionを作り直す側が責任をもって捨てる
reset_session_runtime_state() {
  rm -f "$TEAM_STATE_DIR/agents/"*.env
  rm -rf "${TEAM_STATE_DIR:?}/locks/"*
  rm -f "$TEAM_STATE_DIR/watch.pid"
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

# agentの最初の仕事はCLIの引数として渡す。claudeもcodexもpromptを引数に取り、
# それを最初のmessageとして対話sessionを開く。TUIの描画を読んで貼り付ける必要は
# ないので、composerの見え方や起動の速さで配送が落ちることもない
agent_boot_prompt() {
  local id="$1"
  local role="$2"

  if [[ -n "$prompt" ]]; then
    printf '%s' "$prompt"
    return 0
  fi
  printf 'AGENTS.mdを読み、role=%s、agent_id=%sとしてinbox %sで待機してください。' \
    "$role" "$id" "$id"
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

  printf 'TEAM_AGENT_ID=%s TEAM_AGENT_ROLE=%s TEAM_AGENT_CLI=%s TEAM_AGENT_MODEL=%s TEAM_AGENT_EFFORT=%s TEAM_AGENT_SUPERVISOR=%s TEAM_SESSION=%s TEAM_ROOT=%s TEAM_CONFIG_FILE=%s %s %s' \
    "$(shell_quote "$id")" \
    "$(shell_quote "$role")" \
    "$(shell_quote "$cli")" \
    "$(shell_quote "$model")" \
    "$(shell_quote "$effort")" \
    "$(shell_quote "$supervisor")" \
    "$(shell_quote "$session")" \
    "$(shell_quote "$TEAM_ROOT")" \
    "$(shell_quote "$TEAM_CONFIG_FILE")" \
    "$command" \
    "$(shell_quote "$(agent_boot_prompt "$id" "$role")")"
}

main() {
  require_command tmux
  ensure_state_dirs
  team_config_validate

  local session
  session="$(team_session_name)"

  local session_live=0
  if tmux has-session -t "$session" 2>/dev/null; then
    session_live=1
    if [[ "$restart" -eq 1 ]]; then
      tmux kill-session -t "$session"
      session_live=0
    fi
  fi

  # sessionが無い状態から作るなら、前のsessionのruntime stateは残らず捨てる
  if [[ "$session_live" -eq 0 ]]; then
    reset_session_runtime_state
  fi

  # 何を何個作るのかを先に決める。paneごとにCLIの起動を待つので、進み具合を
  # 出せないと、人間には固まったのか進んでいるのか見分けがつかない
  local -a pending=()
  while IFS='|' read -r id role cli model effort window supervisor; do
    [[ -n "$id" ]] || continue
    if team_config_role_is_exec "$role"; then
      continue
    fi
    if [[ "$lead_only" -eq 1 && "$role" != "lead" ]]; then
      continue
    fi
    # 生きているagentには触れない。触れるのは、居ないか、起動しきれなかったagentだけ
    if agent_state_is_live "$id" "$session"; then
      continue
    fi
    pending+=("$id|$role|$cli|$model|$effort|$window|$supervisor")
  done < <(team_config_agents)

  local total="${#pending[@]}"
  if [[ "$total" -eq 0 ]]; then
    echo "every configured agent is already running"
  else
    echo "starting $total agents; each one waits up to ${TEAM_STARTUP_TIMEOUT}s for its CLI to come up, so this takes a while"
  fi

  local first=1
  [[ "$session_live" -eq 1 ]] && first=0
  local index
  local -a dead_agents=()
  for ((index = 1; index <= total; index++)); do
    IFS='|' read -r id role cli model effort window supervisor <<< "${pending[index - 1]}"
    [[ -n "$window" ]] || window="$id"
    command="$(team_config_agent_command "$id")"

    local launch_command
    launch_command="$(agent_launch_command "$id" "$role" "$cli" "$model" "$effort" "$supervisor" "$session" "$command")"

    # paneのidは作った当人から受け取る。window名で引き直すと、同名windowが
    # 残っている場合にどちらのpaneを指したのか分からなくなる
    local pane
    if [[ "$first" -eq 1 ]]; then
      pane="$(tmux new-session -d -P -F '#{pane_id}' -s "$session" -n "$window" -c "$TEAM_ROOT" "$launch_command")"
      first=0
    else
      pane="$(tmux new-window -d -P -F '#{pane_id}' -t "$session:" -n "$window" -c "$TEAM_ROOT" "$launch_command")"
    fi

    # paneの死亡はそのagentだけの問題として収集し、残りのagentの起動を止めない。
    # 死んだagentのstateは書かないので、次のmake team-startが欠けたagentだけを
    # 作り直せる
    if ! set_pane_metadata "$pane" "$id" "$role" "$model" \
      || ! team_tmux_accept_startup_prompt "$pane" "$cli" "$TEAM_STARTUP_TIMEOUT"; then
      printf '  [%d/%d] %s exited\n' "$index" "$total" "$id"
      dead_agents+=("$id")
      continue
    fi
    printf '  [%d/%d] %s ok\n' "$index" "$total" "$id"
    write_agent_state "$id" "$role" "$cli" "$model" "$effort" "$window" "$supervisor" "$command" "$pane" "$session"
  done

  # 全paneが死ぬとwindowが尽き、tmuxはsessionごと畳む。session宛の操作は
  # そこで意味を失うので、生きているときだけ触る
  if tmux has-session -t "$session" 2>/dev/null; then
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

    # 消えたwakeupを回収する照合loopを常駐させる。
    # watchのloopはsessionが生きている間だけ回るので、pid fileが残っているのは
    # このsessionを起こしたthis runか、その前の生きたrunだけである
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
  fi

  if [[ "${#dead_agents[@]}" -gt 0 ]]; then
    die_rule \
      "agent panes exited during startup: ${dead_agents[*]}" \
      "these agents hold no pane state, so they are not team members yet" \
      "run make team-start again to rebuild exactly the agents named above (live agents are left untouched); if the same agent keeps failing, run its command from $TEAM_CONFIG_FILE by hand in $TEAM_ROOT to see why it exits"
  fi

  echo "tmux session: $session"
  echo "attach with: make team-attach"
}

main "$@"
