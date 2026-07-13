#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_reply.sh [--from <agent_id>] [--to <agent_id>] --in-reply-to <message_id|research_id> [--type <type>] [--body-file <path>] [body...]
USAGE
}

from=""
to=""
in_reply_to=""
type=""
body_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) [[ $# -ge 2 ]] || die "--from requires a value"; from="$2"; shift 2 ;;
    --to) [[ $# -ge 2 ]] || die "--to requires a value"; to="$2"; shift 2 ;;
    --in-reply-to) [[ $# -ge 2 ]] || die "--in-reply-to requires a value"; in_reply_to="$2"; shift 2 ;;
    --type) [[ $# -ge 2 ]] || die "--type requires a value"; type="$2"; shift 2 ;;
    --body-file) [[ $# -ge 2 ]] || die "--body-file requires a path"; body_file="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    --*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
body="${*:-}"

[[ -n "$in_reply_to" ]] || { usage; exit 2; }
if [[ -z "$from" ]]; then
  [[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
    "reply sender is unknown" \
    "this shell has no TEAM_AGENT_ID" \
    "run inside a team pane or pass FROM=<agent_id>"
  from="$TEAM_AGENT_ID"
fi

ensure_team_dirs
team_config_agent_record "$from" >/dev/null || die "unknown reply sender: $from"

if [[ -n "$body_file" ]]; then
  [[ -z "$body" ]] || die "BODY and BODY_FILE cannot both be set"
  [[ -f "$body_file" ]] || die "body file not found: $body_file"
  body="$(<"$body_file")"
fi

research_state_file="$(team_research_state_file "$in_reply_to")"
if [[ -f "$research_state_file" ]]; then
  [[ "$type" == "cancel" ]] || die_rule \
    "research request id accepts cancellation only" \
    "$in_reply_to is a research request id, not an inbox message id" \
    "pass TYPE=cancel with a reason, or reply to the assigned inbox message"
  [[ -n "$body" ]] || die "research cancellation requires a reason"
  exec "$SCRIPT_DIR/team_research_cancel.sh" "$in_reply_to" "$from" "$body"
fi

message_file="$TEAM_STATE_DIR/messages/$in_reply_to.json"
[[ -f "$message_file" ]] || die_rule \
  "source message not found: $in_reply_to" \
  "reply requires an inbox message id or research request id" \
  "run make inbox and use the exact id"
source_line="$(<"$message_file")"
source_from="$(printf '%s\n' "$source_line" | extract_json_field from)"
source_to="$(printf '%s\n' "$source_line" | extract_json_field to)"
source_type="$(printf '%s\n' "$source_line" | extract_json_field type)"
task_id="$(printf '%s\n' "$source_line" | extract_json_field task_id)"
bundle_id="$(printf '%s\n' "$source_line" | extract_json_field bundle_id)"
research_id="$(printf '%s\n' "$source_line" | extract_json_field research_id)"

[[ "$source_to" == "$from" ]] || die_rule \
  "source message is not addressed to $from" \
  "only the recipient may reply" \
  "run from the $source_to pane"
if [[ -n "$to" && "$to" != "$source_from" ]]; then
  die_rule \
    "reply target does not match the source sender" \
    "the source message came from $source_from, but TO=$to" \
    "omit TO or set TO=$source_from"
fi
to="$source_from"

processed_marker="$TEAM_STATE_DIR/processed/$from/$in_reply_to"
if [[ -f "$processed_marker" && "$source_type" != "research_request" ]]; then
  die_rule \
    "message already processed: $in_reply_to" \
    "the source message has already been handled" \
    "choose a pending inbox message"
fi

case "$source_type" in
  research_request)
    case "${type:-result}" in
      result)
        exec "$SCRIPT_DIR/team_research_complete.sh" "$research_id" "$from"
        ;;
      cancel)
        [[ -n "$body" ]] || die "research cancellation reason is required"
        exec "$SCRIPT_DIR/team_research_cancel.sh" "$research_id" "$from" "$body"
        ;;
      *) die "research request reply type must be result or cancel" ;;
    esac
    ;;
esac

if [[ -z "$type" ]]; then
  case "$source_type" in
    question) type="answer" ;;
    *) die_rule "reply type is required" "the source message does not imply one response type" "pass TYPE=<message_type>" ;;
  esac
fi
[[ -n "$body" ]] || die_rule "reply body is required" "an empty reply would close the source without an answer" "pass BODY or BODY_FILE"

send_args=(--from "$from" --type "$type" --requires-attention)
[[ -n "$task_id" ]] && send_args+=(--task "$task_id")
[[ -n "$bundle_id" ]] && send_args+=(--bundle "$bundle_id")
[[ -n "$research_id" ]] && send_args+=(--research "$research_id")
"$SCRIPT_DIR/team_send.sh" "${send_args[@]}" "$to" "$body"

mkdir -p "$TEAM_STATE_DIR/processed/$from"
printf '%s\n' "$(team_now_utc)" > "$processed_marker"
printf 'marked_processed=%s\n' "$in_reply_to"
