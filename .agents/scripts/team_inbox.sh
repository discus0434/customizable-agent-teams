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
  team_inbox.sh <agent_id> --raw
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

raw=0

if [[ "${1:-}" == "--mark" ]]; then
  [[ $# -eq 2 ]] || { usage; exit 2; }
  message_id="$2"
  printf '%s\n' "$(team_now_utc)" > "$processed_dir/$message_id"
  echo "marked processed: $message_id"
  exit 0
elif [[ "${1:-}" == "--raw" ]]; then
  [[ $# -eq 1 ]] || { usage; exit 2; }
  raw=1
  shift
fi

[[ $# -eq 0 ]] || { usage; exit 2; }

inbox_file="$TEAM_QUEUE_DIR/inbox/$agent_id.jsonl"
if [[ ! -f "$inbox_file" ]]; then
  : > "$inbox_file"
fi

pending=0
auto_processed=0
total=0
while IFS= read -r line; do
  message_id="$(printf '%s\n' "$line" | extract_json_field id)"
  [[ -n "$message_id" ]] || continue
  total=$((total + 1))
  if [[ ! -f "$processed_dir/$message_id" ]]; then
    pending=$((pending + 1))
    if [[ "$raw" -eq 1 ]]; then
      printf '%s\n' "$line"
      continue
    fi
    message_from="$(printf '%s\n' "$line" | extract_json_field from)"
    message_type="$(printf '%s\n' "$line" | extract_json_field type)"
    message_subtype="$(printf '%s\n' "$line" | extract_json_field subtype)"
    message_task="$(printf '%s\n' "$line" | extract_json_field task_id)"
    message_bundle="$(printf '%s\n' "$line" | extract_json_field bundle_id)"
    message_research="$(printf '%s\n' "$line" | extract_json_field research_id)"
    message_artifact="$(printf '%s\n' "$line" | extract_json_field artifact_path)"
    message_cc_of="$(printf '%s\n' "$line" | extract_json_field cc_of)"
    message_done="$(printf '%s\n' "$line" | extract_json_field done_recommendation)"
    message_created_at="$(printf '%s\n' "$line" | extract_json_field created_at)"
    message_body="$(printf '%s\n' "$line" | extract_json_field body)"
    message_auto_processed=0

    if [[ "$pending" -eq 1 ]]; then
      printf 'inbox %s: pending messages\n' "$agent_id"
    fi
    printf '\n'
    printf -- '- id: %s\n' "$message_id"
    printf '  from: %s\n' "${message_from:-unknown}"
    printf '  type: %s\n' "${message_type:-unknown}"
    [[ -n "$message_subtype" ]] && printf '  subtype: %s\n' "$message_subtype"
    [[ -n "$message_task" ]] && printf '  task: %s\n' "$message_task"
    [[ -n "$message_bundle" ]] && printf '  bundle: %s\n' "$message_bundle"
    [[ -n "$message_research" ]] && printf '  research: %s\n' "$message_research"
    [[ -n "$message_artifact" ]] && printf '  artifact: %s\n' "$message_artifact"
    [[ -n "$message_cc_of" ]] && printf '  cc_of: %s\n' "$message_cc_of"
    [[ -n "$message_done" ]] && printf '  done_recommendation: %s\n' "$message_done"
    [[ -n "$message_created_at" ]] && printf '  created_at: %s\n' "$message_created_at"
    printf '  body:\n'
    if [[ -n "$message_body" ]]; then
      printf '%s\n' "$message_body" | sed 's/^/    /'
    else
      printf '    \n'
    fi
    if team_message_auto_process_on_read "$message_type"; then
      printf '%s\n' "$(team_now_utc)" > "$processed_dir/$message_id"
      auto_processed=$((auto_processed + 1))
      message_auto_processed=1
    fi
    [[ "$message_auto_processed" -eq 1 ]] && printf '  processed_on_read: true\n'
    printf '  raw: %s\n' "$line"
  fi
done < "$inbox_file"

if [[ "$raw" -eq 1 ]]; then
  exit 0
fi

pending_after=$((pending - auto_processed))

if [[ "$pending_after" -eq 0 ]]; then
  printf 'inbox %s: 0 pending (%s total)\n' "$agent_id" "$total"
else
  printf '\ninbox %s: %s pending (%s total)\n' "$agent_id" "$pending_after" "$total"
fi
