#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_send.sh [--from <agent_id>] [--body-file <path>] <to> <type> [task_id] [body...]

examples:
  team_send.sh --from lead manager intake - "ユーザー依頼の要点..."
  team_send.sh --from manager worker-1 task_assigned T-001
  team_send.sh --from manager reviewer-1 review_watch_assigned T-001
USAGE
}

from=""
body_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      [[ $# -ge 2 ]] || die "--from requires a value"
      from="$2"
      shift 2
      ;;
    --body-file)
      [[ $# -ge 2 ]] || die "--body-file requires a path"
      body_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    --*)
      die "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -ge 2 ]] || { usage; exit 2; }

to="$1"
type="$2"
task_id="${3:-}"
shift 2
if [[ $# -gt 0 ]]; then
  shift || true
fi

if ! team_config_agent_record "$to" >/dev/null; then
  die "unknown target agent: $to"
fi

if [[ -z "$from" ]]; then
  [[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die "sender is unknown; set TEAM_AGENT_ID by running inside a team pane or pass --from <agent_id>"
  from="$TEAM_AGENT_ID"
fi

if ! team_config_agent_record "$from" >/dev/null; then
  die "unknown sender agent: $from"
fi

body="${*:-}"
if [[ -n "$body_file" ]]; then
  [[ -f "$body_file" ]] || die "body file not found: $body_file"
  body="$(<"$body_file")"
fi

if [[ -z "$body" ]]; then
  if [[ -n "$task_id" && "$task_id" != "-" ]]; then
    body="$TEAM_QUEUE_DIR/tasks/$task_id.md を確認してください。"
  else
    body="$TEAM_QUEUE_DIR/inbox/$to.jsonl を確認してください。"
  fi
fi

ensure_team_dirs

message_id="$(team_message_id)"
created_at="$(team_now_utc)"
inbox_file="$TEAM_QUEUE_DIR/inbox/$to.jsonl"
message_file="$TEAM_STATE_DIR/messages/$message_id.json"

escaped_body="$(json_string "$body")"
escaped_from="$(json_string "$from")"
escaped_to="$(json_string "$to")"
escaped_type="$(json_string "$type")"
escaped_task_id="$(json_string "$task_id")"

line="{\"id\":\"$message_id\",\"from\":\"$escaped_from\",\"to\":\"$escaped_to\",\"type\":\"$escaped_type\",\"task_id\":\"$escaped_task_id\",\"created_at\":\"$created_at\",\"body\":\"$escaped_body\"}"

acquire_team_lock "inbox-$to"
printf '%s\n' "$line" >> "$inbox_file"
printf '%s\n' "$line" > "$message_file"
release_team_lock

if ! "$SCRIPT_DIR/team_nudge.sh" "$to"; then
  warn "nudge failed for $to; inbox entry is still available at $inbox_file"
fi

echo "$message_id"
