#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_exec_run.sh [--resume <session_id>] [--kind <research|task>] [--ref <id>] [--notify <agent_id>] <agent_id> <prompt>" >&2
}

resume_session=""
kind="run"
ref=""
notify=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume) [[ $# -ge 2 ]] || die "--resume requires a value"; resume_session="$2"; shift 2 ;;
    --kind) [[ $# -ge 2 ]] || die "--kind requires a value"; kind="$2"; shift 2 ;;
    --ref) [[ $# -ge 2 ]] || die "--ref requires a value"; ref="$2"; shift 2 ;;
    --notify) [[ $# -ge 2 ]] || die "--notify requires a value"; notify="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

[[ $# -eq 2 ]] || { usage; exit 2; }
agent_id="$1"
prompt="$2"
[[ -n "$prompt" ]] || die "exec prompt is empty"

ensure_team_dirs
team_config_agent_record "$agent_id" >/dev/null || die "unknown exec agent: $agent_id"
mode="$(team_config_agent_field "$agent_id" mode)"
[[ "$mode" == "exec" ]] || die_rule \
  "agent does not run in exec mode: $agent_id" \
  "team_exec_run.sh launches on-demand agents only" \
  "set 'mode: exec' for $agent_id in $TEAM_CONFIG_FILE or use tmux nudges"
cli="$(team_config_agent_field "$agent_id" cli)"
[[ "$cli" == "codex" ]] || die "exec mode requires the codex CLI: $agent_id"
require_command codex

role="$(team_config_agent_field "$agent_id" role)"
model="$(team_config_agent_field "$agent_id" model)"
effort="$(team_config_agent_field "$agent_id" effort)"

state_file="$TEAM_STATE_DIR/exec/$agent_id.env"
log_file="$TEAM_STATE_DIR/exec/$agent_id.jsonl"
err_file="$TEAM_STATE_DIR/exec/$agent_id.err"
last_message_file="$TEAM_STATE_DIR/exec/$agent_id-last-message.txt"

if [[ -f "$state_file" ]]; then
  pid=""
  # shellcheck disable=SC1090
  source "$state_file"
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    die_rule \
      "exec agent is already running: $agent_id" \
      "pid $pid has not finished its current run" \
      "wait for the run to end or cancel it first"
  fi
fi

command_args=(codex exec)
if [[ -n "$resume_session" ]]; then
  command_args+=(resume "$resume_session")
fi
command_args+=(
  --dangerously-bypass-approvals-and-sandbox
  -C "$TEAM_ROOT"
  --json
  --output-last-message "$last_message_file"
  -c "model_reasoning_effort=\"$effort\""
)
if [[ -z "$resume_session" ]]; then
  command_args+=(--model "$model")
fi
if [[ "$role" == "research-worker" ]]; then
  command_args+=(-c "tools.web_search=true")
fi
command_args+=("$prompt")

started_at="$(team_now_utc)"
rm -f "$last_message_file"

runner="$SCRIPT_DIR/team_exec_wait.sh"

TEAM_AGENT_ID="$agent_id" \
TEAM_AGENT_ROLE="$role" \
TEAM_AGENT_CLI="$cli" \
TEAM_AGENT_MODEL="$model" \
TEAM_AGENT_EFFORT="$effort" \
TEAM_ROOT="$TEAM_ROOT" \
TEAM_CONFIG_FILE="$TEAM_CONFIG_FILE" \
TEAM_EXEC_STATE_FILE="$state_file" \
TEAM_EXEC_LOG_FILE="$log_file" \
TEAM_EXEC_ERR_FILE="$err_file" \
TEAM_EXEC_KIND="$kind" \
TEAM_EXEC_REF="$ref" \
TEAM_EXEC_NOTIFY="$notify" \
  nohup "$runner" "${command_args[@]}" >/dev/null 2>&1 &
pid=$!

{
  printf 'agent_id=%s\n' "$(shell_quote "$agent_id")"
  printf 'pid=%s\n' "$(shell_quote "$pid")"
  printf 'kind=%s\n' "$(shell_quote "$kind")"
  printf 'ref=%s\n' "$(shell_quote "$ref")"
  printf 'notify=%s\n' "$(shell_quote "$notify")"
  printf 'resume_session=%s\n' "$(shell_quote "$resume_session")"
  printf 'log=%s\n' "$(shell_quote "$log_file")"
  printf 'last_message_file=%s\n' "$(shell_quote "$last_message_file")"
  printf 'started_at=%s\n' "$(shell_quote "$started_at")"
} > "$state_file"

printf 'agent_id=%s\n' "$agent_id"
printf 'pid=%s\n' "$pid"
printf 'log=%s\n' "$log_file"
