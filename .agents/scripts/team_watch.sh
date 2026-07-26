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
  sweep_task_ages
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
    if team_tmux_pane_is_busy "$pane" "${cli:-}" || team_tmux_input_is_pending "$pane" "${cli:-}"; then
      exit 0
    fi
    team_tmux_send_text "$pane" "$text" || true
  )
}

# Long-lived task review uses the same positive pane checks as ordinary nudges,
# but must distinguish a successful send from a blocked or unavailable pane.
send_idle_pane_with_text() {
  local id="$1"
  local text="$2"
  (
    pane=""
    session=""
    cli=""
    state_file="$TEAM_STATE_DIR/agents/$id.env"
    [[ -f "$state_file" ]] || exit 1
    # shellcheck disable=SC1090
    source "$state_file"
    [[ -n "${pane:-}" && -n "${session:-}" && -n "${cli:-}" ]] || exit 1
    tmux has-session -t "$session" 2>/dev/null || exit 1
    team_tmux_pane_in_session "$pane" "$session" || exit 1
    team_tmux_pane_is_busy "$pane" "${cli:-}" && exit 1
    team_tmux_input_is_pending "$pane" "$cli" && exit 1
    team_tmux_send_text "$pane" "$text"
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

task_age_marker_root="$TEAM_STATE_DIR/watch/task-age"
task_age_first_seen=""
task_age_last_alarm=""

task_age_marker_path() {
  local task_id="$1"
  [[ "$task_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  printf '%s/%s.marker\n' "$task_age_marker_root" "$task_id"
}

task_age_marker_write() {
  local task_id="$1"
  local first_seen="$2"
  local last_alarm="$3"
  local marker tmp
  marker="$(task_age_marker_path "$task_id")" || return 1
  tmp="$(mktemp "$task_age_marker_root/.${task_id}.XXXXXX")" || return 1
  if ! {
    printf 'task_id=%s\n' "$task_id"
    printf 'first_seen=%s\n' "$first_seen"
    printf 'last_alarm=%s\n' "$last_alarm"
  } > "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if ! mv -f -- "$tmp" "$marker"; then
    rm -f -- "$tmp"
    return 1
  fi
}

task_age_marker_read() {
  local task_id="$1"
  local marker="$2"
  local -a lines=()
  task_age_marker_path "$task_id" >/dev/null || return 1
  mapfile -t lines < "$marker" || return 1
  [[ "${#lines[@]}" -eq 3 ]] || return 1
  [[ "${lines[0]}" == "task_id=$task_id" ]] || return 1
  [[ "${lines[1]}" == first_seen=* ]] || return 1
  [[ "${lines[2]}" == last_alarm=* ]] || return 1
  task_age_first_seen="${lines[1]#first_seen=}"
  task_age_last_alarm="${lines[2]#last_alarm=}"
  [[ "$task_age_first_seen" =~ ^[0-9]+$ ]] || return 1
  [[ "$task_age_last_alarm" =~ ^[0-9]+$ ]] || return 1
  [[ "$task_age_first_seen" -le "$task_age_now" ]] || return 1
  [[ "$task_age_last_alarm" -le "$task_age_now" ]] || return 1
}

task_age_strategist_id() {
  local -a strategist_ids=()
  mapfile -t strategist_ids < <(team_config_role_agent_ids strategist)
  [[ "${#strategist_ids[@]}" -eq 1 && -n "${strategist_ids[0]}" ]] || return 1
  printf '%s\n' "${strategist_ids[0]}"
}

sweep_task_ages() {
  local state_json task_id status marker elapsed hours summon strategist_id
  task_age_now="$(date +%s)"
  [[ "$task_age_now" =~ ^[0-9]+$ ]] || {
    warn "task-age sweep has invalid current epoch: $task_age_now"
    return 0
  }
  mkdir -p "$task_age_marker_root"
  strategist_id="$(task_age_strategist_id 2>/dev/null || true)"

  for state_json in "$TEAM_STATE_DIR"/tasks/*.json; do
    [[ -f "$state_json" ]] || continue
    task_id="$(basename "$state_json" .json)"
    marker="$(task_age_marker_path "$task_id" 2>/dev/null || true)"
    [[ -n "$marker" ]] || {
      warn "task-age marker suppressed for invalid task id: $task_id"
      continue
    }
    status="$(team_task_state_field "$task_id" status)"
    if [[ "$status" == "done" ]]; then
      if [[ -e "$marker" || -L "$marker" ]]; then
        rm -f -- "$marker" || warn "could not remove completed task-age marker: $task_id"
      fi
      continue
    fi
    if [[ ! -e "$marker" ]]; then
      task_age_marker_write "$task_id" "$task_age_now" 0 \
        || warn "could not publish first task-age marker: $task_id"
      continue
    fi
    if ! task_age_marker_read "$task_id" "$marker"; then
      warn "invalid task-age marker; suppressing alarm: $task_id"
      continue
    fi
    elapsed=$(( task_age_now - task_age_first_seen ))
    (( elapsed > 7200 )) || continue
    if (( task_age_last_alarm != 0 && task_age_now - task_age_last_alarm <= 3600 )); then
      continue
    fi
    if [[ -z "$strategist_id" ]]; then
      warn "strategist pane is not uniquely configured; suppressing task-age alarm: $task_id"
      continue
    fi
    hours=$(( elapsed / 3600 ))
    summon="長生きtask確認: ${task_id}が開始から約${hours}時間生存している。taskの内容と直近の進捗を調べたうえで、やりたいことから逆算した場合に、Manager・Worker・Reviewerが取り組んでいるこのtaskにもっとreasonableなやり方がないのか、単純なことを複雑に考えていないか、を熟考すること。もっと良いやり方があると判断した場合は、具体的な提案をManagerへnoteで送ること。taskが相応に難しいもので、時間がかかっていることが妥当だと判断した場合は、何もしなくてよい。"
    if send_idle_pane_with_text "$strategist_id" "$summon"; then
      task_age_marker_write "$task_id" "$task_age_first_seen" "$task_age_now" \
        || warn "task-age alarm sent but last alarm marker failed: $task_id"
    fi
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
      cli=""
      state_file="$TEAM_STATE_DIR/agents/$id.env"
      [[ -f "$state_file" ]] || exit 1
      # shellcheck disable=SC1090
      source "$state_file"
      [[ -n "${pane:-}" ]] || exit 1
      team_tmux_pane_is_busy "$pane" "${cli:-}"
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
