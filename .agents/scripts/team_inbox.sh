#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_inbox.sh <agent_id>
  team_inbox.sh <agent_id> --mark <message_id>
USAGE
}

[[ $# -ge 1 ]] || { usage; exit 2; }

agent_id="$1"
shift

if ! team_config_agent_record "$agent_id" >/dev/null; then
  die "unknown agent: $agent_id"
fi

ensure_team_dirs

processed_dir="$TEAM_STATE_DIR/processed/$agent_id"
mkdir -p "$processed_dir"

if [[ "${1:-}" == "--mark" ]]; then
  [[ $# -eq 2 ]] || { usage; exit 2; }
  message_id="$2"
  printf '%s\n' "$(team_now_utc)" > "$processed_dir/$message_id"
  echo "marked processed: $message_id"
  exit 0
fi

[[ $# -eq 0 ]] || { usage; exit 2; }

inbox_file="$TEAM_QUEUE_DIR/inbox/$agent_id.jsonl"
if [[ ! -f "$inbox_file" ]]; then
  : > "$inbox_file"
fi

pending=0
while IFS= read -r line; do
  message_id="$(printf '%s\n' "$line" | extract_json_field id)"
  [[ -n "$message_id" ]] || continue
  if [[ ! -f "$processed_dir/$message_id" ]]; then
    pending=$((pending + 1))
    printf '%s\n' "$line"
  fi
done < "$inbox_file"

if [[ "$pending" -eq 0 ]]; then
  printf 'inbox %s: 0 messages\n' "$agent_id"
fi
