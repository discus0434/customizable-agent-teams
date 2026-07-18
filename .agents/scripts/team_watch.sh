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
ensure_state_dirs
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
  sweep_task_obligations
  stall_alarm_check
}

# taskの生きたpendingがどこかのinboxにあれば、義務はmessage系の照合が担っている
task_has_live_pending() {
  local task_id="$1"
  local inbox_file agent_id line message_id message_task

  for inbox_file in "$TEAM_QUEUE_DIR"/inbox/*.jsonl; do
    [[ -f "$inbox_file" ]] || continue
    agent_id="$(basename "$inbox_file" .jsonl)"
    while IFS= read -r line; do
      message_id="$(printf '%s\n' "$line" | extract_json_field id)"
      [[ -n "$message_id" ]] || continue
      message_task="$(printf '%s\n' "$line" | extract_json_field task_id)"
      [[ "$message_task" == "$task_id" ]] || continue
      if [[ ! -f "$TEAM_STATE_DIR/processed/$agent_id/$message_id" ]]; then
        return 0
      fi
    done < "$inbox_file"
  done
  return 1
}

# idleのpaneへ督促textを直接送る。busyまたは未送信入力があれば次の周期に譲る
nudge_idle_pane_with_text() {
  local id="$1"
  local text="$2"
  (
    pane=""
    session=""
    cli=""
    state_file="$TEAM_STATE_DIR/agents/$id.env"
    [[ -f "$state_file" ]] || exit 0
    # shellcheck disable=SC1090
    source "$state_file"
    [[ -n "${pane:-}" && -n "${session:-}" ]] || exit 0
    tmux has-session -t "$session" 2>/dev/null || exit 0
    team_tmux_pane_in_session "$pane" "$session" || exit 0
    if team_tmux_pane_is_busy "$pane" || team_tmux_input_is_pending "$pane" "${cli:-}"; then
      exit 0
    fi
    team_tmux_send_text "$pane" "$text" || true
  )
}

# 義務はinboxとtask stateの2箇所に記録される。散文の待機宣言や自己再開の
# 放棄は、task stateにだけ義務が残り、どのinboxにも映らない停滞になる。
# statusから義務を負うagentを決め、そのpaneがidleでtaskのpendingも無ければ起こす
sweep_task_obligations() {
  local state_json task_id status target target_role
  for state_json in "$TEAM_STATE_DIR"/tasks/*.json; do
    [[ -f "$state_json" ]] || continue
    task_id="$(basename "$state_json" .json)"
    status="$(team_task_state_field "$task_id" status)"
    case "$status" in
      dispatched|supervision_fix|manager_fix)
        target="$(team_task_state_field "$task_id" worker)" ;;
      needs_supervision)
        target="$(team_task_state_field "$task_id" supervisor)" ;;
      supervision_ok|supervision_ask_manager|ready_for_lead|blocked)
        target="$(team_task_state_field "$task_id" owner)" ;;
      *) continue ;;
    esac
    [[ -n "$target" ]] || continue
    target_role="$(team_config_agent_field "$target" role 2>/dev/null || true)"
    [[ -n "$target_role" ]] || continue
    if team_config_role_is_exec "$target_role"; then
      continue
    fi
    if task_has_live_pending "$task_id"; then
      continue
    fi
    nudge_idle_pane_with_text "$target" \
      "task ${task_id} が status=${status} のまま、どのinboxにも義務が映っていません。担当はあなた(${target})です。作業を再開するか、待つ相手へpendingが立つmessageを送ってください。"
  done
}

# team全体が止まる新種の停滞は、既知の照合(inbox、task state)では拾えない。
# 「仕事が残っているのに、inboxもtask stateも動かず、作業中のpaneも無い」
# 状態が続いたら、診断者としてLeadを起こす。機構は修理せず、召喚だけを行う
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0\n'
}

stall_alarm_check() {
  local threshold="${TEAM_STALL_ALARM_SECONDS:-300}"
  [[ "$threshold" -gt 0 ]] || return 0

  local state_json task_id status open_tasks=""
  for state_json in "$TEAM_STATE_DIR"/tasks/*.json; do
    [[ -f "$state_json" ]] || continue
    task_id="$(basename "$state_json" .json)"
    status="$(team_task_state_field "$task_id" status)"
    [[ "$status" == "done" ]] && continue
    open_tasks+="${task_id}(${status}) "
  done
  [[ -n "$open_tasks" ]] || return 0

  local f mt newest=0 now age
  for f in "$TEAM_QUEUE_DIR"/inbox/*.jsonl "$TEAM_STATE_DIR"/tasks/*.json; do
    [[ -f "$f" ]] || continue
    mt="$(file_mtime "$f")"
    (( mt > newest )) && newest="$mt"
  done
  (( newest > 0 )) || return 0
  now="$(date +%s)"
  age=$(( now - newest ))
  (( age >= threshold )) || return 0

  local id role busy_found=0
  while IFS='|' read -r id role _cli _model _effort _window _supervisor; do
    [[ -n "$id" && "$id" != "lead" ]] || continue
    if team_config_role_is_exec "$role"; then
      continue
    fi
    if (
      pane=""
      state_file="$TEAM_STATE_DIR/agents/$id.env"
      [[ -f "$state_file" ]] || exit 1
      # shellcheck disable=SC1090
      source "$state_file"
      [[ -n "${pane:-}" ]] || exit 1
      team_tmux_pane_is_busy "$pane"
    ); then
      busy_found=1
      break
    fi
  done < <(team_config_agents)
  (( busy_found == 0 )) || return 0

  local marker="$TEAM_STATE_DIR/watch/stall-alarm.at" last
  mkdir -p "$TEAM_STATE_DIR/watch"
  last="$(cat "$marker" 2>/dev/null || printf '0\n')"
  (( now - last >= threshold )) || return 0
  printf '%s\n' "$now" > "$marker.tmp.$$"
  mv "$marker.tmp.$$" "$marker"

  nudge_idle_pane_with_text lead \
    "停滞警報: 約$(( age / 60 ))分、inboxとtask stateが動かず、作業中のpaneもありません。open tasks: ${open_tasks}。team-statusと各paneの実態を調べ、原因を特定して介入してください。"
}

if [[ "$once" == "1" ]]; then
  sweep
  exit 0
fi

while tmux has-session -t "$session" 2>/dev/null; do
  sweep
  sleep "${TEAM_WATCH_INTERVAL:-60}"
done
