#!/usr/bin/env bash

# Runs a codex exec command for an on-demand agent, then records the outcome.
# Invoked by team_exec_run.sh with the full command as arguments and the
# bookkeeping context in TEAM_EXEC_* environment variables.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

state_file="${TEAM_EXEC_STATE_FILE:?}"
log_file="${TEAM_EXEC_LOG_FILE:?}"
err_file="${TEAM_EXEC_ERR_FILE:?}"
kind="${TEAM_EXEC_KIND:?}"
ref="${TEAM_EXEC_REF:?}"
notify="${TEAM_EXEC_NOTIFY:?}"
agent_id="${TEAM_AGENT_ID:?}"

cd "${TEAM_ROOT:?}"

read_session_id() {
  sed -nE 's/.*"type":"thread\.started","thread_id":"([0-9a-f-]{36})".*/\1/p' "$log_file" 2>/dev/null | head -n 1
}

"$@" > "$log_file" 2> "$err_file" < /dev/null &
codex_pid=$!

# thread.startedは実行開始直後にevent logへ流れる。終了時にまとめて記録すると
# 「workerが報告済みだがsession_id未記録」の隙間が生まれ、その間のexpress-fixが
# 再開先を見つけられないため、見つけ次第記録する
session_id=""
while :; do
  session_id="$(read_session_id)"
  if [[ -n "$session_id" ]]; then
    printf 'session_id=%s\n' "'$session_id'" >> "$state_file"
    break
  fi
  kill -0 "$codex_pid" 2>/dev/null || break
  sleep 1
done

wait "$codex_pid"
exit_code=$?

if [[ -z "$session_id" ]]; then
  session_id="$(read_session_id)"
  [[ -n "$session_id" ]] && printf 'session_id=%s\n' "'$session_id'" >> "$state_file"
fi

{
  printf 'ended_at=%s\n' "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
  printf 'exit_code=%s\n' "'$exit_code'"
} >> "$state_file"

if [[ "$exit_code" -ne 0 ]]; then
  body="exec agentの実行が失敗しました。agent=${agent_id} kind=${kind} ref=${ref} exit=${exit_code}。"
  body+="標準エラーは${err_file}、event logは${log_file}を確認してください。"
  "$SCRIPT_DIR/team_send.sh" --from "$agent_id" --type request --task "-" "$notify" "$body" >/dev/null 2>&1 \
    || echo "exec failure notification could not be sent: $agent_id -> $notify" >> "$err_file"
fi

exit "$exit_code"
