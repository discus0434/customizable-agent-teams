#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_reply.sh --from <agent_id> --to <agent_id> --in-reply-to <message_id> --type <type> [--task <task_id>] [--bundle <bundle_id>] [--body-file <path>] [body...]
USAGE
}

from=""
to=""
in_reply_to=""
type=""
task_id=""
bundle_id=""
body_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      [[ $# -ge 2 ]] || die "--from requires a value"
      from="$2"
      shift 2
      ;;
    --to)
      [[ $# -ge 2 ]] || die "--to requires a value"
      to="$2"
      shift 2
      ;;
    --in-reply-to)
      [[ $# -ge 2 ]] || die "--in-reply-to requires a value"
      in_reply_to="$2"
      shift 2
      ;;
    --type)
      [[ $# -ge 2 ]] || die "--type requires a value"
      type="$2"
      shift 2
      ;;
    --task)
      [[ $# -ge 2 ]] || die "--task requires a value"
      task_id="$2"
      shift 2
      ;;
    --bundle)
      [[ $# -ge 2 ]] || die "--bundle requires a value"
      bundle_id="$2"
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

body="${*:-}"

[[ -n "$from" ]] || { usage; exit 2; }
[[ -n "$to" ]] || { usage; exit 2; }
[[ -n "$in_reply_to" ]] || { usage; exit 2; }
[[ -n "$type" ]] || { usage; exit 2; }

ensure_team_dirs

if ! team_config_agent_record "$from" >/dev/null; then
  die_rule \
    "unknown sender agent: $from" \
    "the reply sender is not present in $TEAM_CONFIG_FILE" \
    "choose an agent id from .agents/config/agent-team.yaml"
fi

if ! team_config_agent_record "$to" >/dev/null; then
  die_rule \
    "unknown target agent: $to" \
    "the reply recipient is not present in $TEAM_CONFIG_FILE" \
    "choose an agent id from .agents/config/agent-team.yaml"
fi

if [[ -n "$body_file" ]]; then
  [[ -z "$body" ]] || die_rule \
    "body and body file were both provided" \
    "reply body has two sources, so the delivered text would be ambiguous" \
    "pass either BODY or BODY_FILE, not both"
  [[ -f "$body_file" ]] || die_rule \
    "body file not found: $body_file" \
    "the requested --body-file path does not exist" \
    "write the body file first or pass BODY directly"
elif [[ -z "$body" ]]; then
  die_rule \
    "reply body is required" \
    "an empty reply would mark the source message without recording the answer" \
    "pass BODY=... or BODY_FILE=..."
fi

inbox_file="$TEAM_QUEUE_DIR/inbox/$from.jsonl"
processed_marker="$TEAM_STATE_DIR/processed/$from/$in_reply_to"

[[ -f "$inbox_file" ]] || die_rule \
  "source inbox does not exist for $from" \
  "the source message must be an inbox item delivered to the replying agent" \
  "run make inbox AGENT=$from and use one of its message ids"

[[ ! -f "$processed_marker" ]] || die_rule \
  "message already processed: $in_reply_to" \
  "replying again would duplicate a handled conversation" \
  "choose an unread message id from make inbox AGENT=$from"

source_line=""
while IFS= read -r line; do
  message_id="$(printf '%s\n' "$line" | extract_json_field id)"
  if [[ "$message_id" == "$in_reply_to" ]]; then
    source_line="$line"
    break
  fi
done < "$inbox_file"

[[ -n "$source_line" ]] || die_rule \
  "source message not found: $in_reply_to" \
  "the source message id is not present in $from's inbox" \
  "run make inbox AGENT=$from and pass the exact id"

source_to="$(printf '%s\n' "$source_line" | extract_json_field to)"
[[ "$source_to" == "$from" ]] || die_rule \
  "source message is not addressed to $from" \
  "only the recipient may reply-and-mark the message" \
  "run team-reply from the agent shown in the message's to field"

if [[ -z "$task_id" ]]; then
  task_id="$(printf '%s\n' "$source_line" | extract_json_field task_id)"
fi

if [[ -z "$bundle_id" ]]; then
  bundle_id="$(printf '%s\n' "$source_line" | extract_json_field bundle_id)"
fi

send_args=(--from "$from" --type "$type" --requires-attention)
if [[ -n "$task_id" ]]; then
  send_args+=(--task "$task_id")
fi
if [[ -n "$bundle_id" ]]; then
  send_args+=(--bundle "$bundle_id")
fi
if [[ -n "$body_file" ]]; then
  send_args+=(--body-file "$body_file" "$to")
  "$SCRIPT_DIR/team_send.sh" "${send_args[@]}"
else
  send_args+=("$to" "$body")
  "$SCRIPT_DIR/team_send.sh" "${send_args[@]}"
fi

mkdir -p "$TEAM_STATE_DIR/processed/$from"
printf '%s\n' "$(team_now_utc)" > "$processed_marker"
printf 'marked_processed=%s\n' "$in_reply_to"
