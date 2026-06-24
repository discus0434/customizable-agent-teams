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
  team_send.sh worker-1 task_assigned T-001
  team_send.sh --from verifier worker-1 review T-001 ".agents/queue/reviews/... を確認してください。"
USAGE
}

from="${TEAM_AGENT_ID:-lead}"
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

body="${*:-}"
if [[ -n "$body_file" ]]; then
  [[ -f "$body_file" ]] || die "body file not found: $body_file"
  body="$(<"$body_file")"
fi

if [[ -z "$body" ]]; then
  if [[ -n "$task_id" && "$task_id" != "-" ]]; then
    body="$TEAM_QUEUE_DIR/tasks/$task_id.md を読んで、完了時は $TEAM_QUEUE_DIR/reports/${task_id}_${to}.md に報告してください。"
  else
    body="$TEAM_QUEUE_DIR/inbox/$to.jsonl を確認してください。"
  fi
fi

ensure_team_dirs

if [[ "$type" == "task_assigned" ]]; then
  [[ -n "$task_id" && "$task_id" != "-" ]] || die "task_assigned requires a task id"
  task_file="$TEAM_QUEUE_DIR/tasks/$task_id.md"
  [[ -f "$task_file" ]] || die "task file not found: $task_file"
  task_owner="$(team_task_markdown_field "$task_file" Owner)" || die "task Owner is missing: $task_file"
  [[ "$task_owner" == "$to" ]] || die "task Owner mismatch: expected $to, got $task_owner"
  git -C "$TEAM_ROOT" rev-parse --verify HEAD >/dev/null 2>&1 || die "git HEAD does not exist yet. Commit the template before dispatching tasks."
  if ! team_git_is_clean "$TEAM_ROOT"; then
    team_git_dirty_summary "$TEAM_ROOT" >&2
    die "team root must be clean before dispatching $task_id"
  fi

  state_file="$(team_task_state_file "$task_id")"
  [[ ! -f "$state_file" ]] || die "task state already exists: $state_file"

  acquire_team_lock "dispatch-$task_id"
  while IFS= read -r existing_state_file; do
    [[ -f "$existing_state_file" ]] || continue
    existing_task="$(basename "$existing_state_file" .json)"
    [[ "$existing_task" == "$task_id" ]] && continue
    existing_status="$(extract_json_field status < "$existing_state_file")"
    if [[ "$existing_status" != "integrated" ]]; then
      existing_owner="$(extract_json_field owner < "$existing_state_file")"
      release_team_lock
      die "shared root already has active task $existing_task owned by $existing_owner with status $existing_status"
    fi
  done < <(find "$TEAM_STATE_DIR/tasks" -maxdepth 1 -type f -name '*.json' | sort)

  base_commit="$(git -C "$TEAM_ROOT" rev-parse HEAD)"
  team_write_task_state \
    "$task_id" \
    "$to" \
    "assigned" \
    "$base_commit" \
    "" \
    "" \
    "" \
    "" \
    "" \
    ""
  release_team_lock
fi

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
