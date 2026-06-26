#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_dispatch.sh <task_id> <worker_id> <reviewer_id>" >&2
}

[[ $# -eq 3 ]] || { usage; exit 2; }

task_id="$1"
worker_id="$2"
reviewer_id="$3"

[[ "$task_id" != */* ]] || die "task_id must not contain '/': $task_id"
[[ "$worker_id" != */* ]] || die "worker_id must not contain '/': $worker_id"
[[ "$reviewer_id" != */* ]] || die "reviewer_id must not contain '/': $reviewer_id"

ensure_team_dirs

task_file="$TEAM_QUEUE_DIR/tasks/$task_id.md"
state_file="$(team_task_state_file "$task_id")"

[[ -f "$task_file" ]] || die "task file not found: $task_file"
[[ ! -f "$state_file" ]] || die "task state already exists: $state_file"

if ! team_config_agent_record "$worker_id" >/dev/null; then
  die "unknown worker: $worker_id"
fi
if ! team_config_agent_record "$reviewer_id" >/dev/null; then
  die "unknown reviewer: $reviewer_id"
fi

worker_role="$(team_config_agent_field "$worker_id" role)"
reviewer_role="$(team_config_agent_field "$reviewer_id" role)"
[[ "$worker_role" == "worker" ]] || die "$worker_id is not a worker agent"
[[ "$reviewer_role" == "reviewer" ]] || die "$reviewer_id is not a reviewer agent"

task_owner="$(team_task_markdown_field "$task_file" Owner)" || die "task Owner is missing: $task_file"
task_reviewer="$(team_task_markdown_field "$task_file" Reviewer)" || die "task Reviewer is missing: $task_file"
[[ "$task_owner" == "$worker_id" ]] || die "task Owner mismatch: expected $worker_id, got $task_owner"
[[ "$task_reviewer" == "$reviewer_id" ]] || die "task Reviewer mismatch: expected $reviewer_id, got $task_reviewer"

git -C "$TEAM_ROOT" rev-parse --verify HEAD >/dev/null 2>&1 || die "git HEAD does not exist yet. Commit the template before dispatching tasks."
base_commit="$(git -C "$TEAM_ROOT" rev-parse HEAD)"

acquire_team_lock "dispatch-$task_id"
team_write_task_state \
  "$task_id" \
  "$worker_id" \
  "$reviewer_id" \
  "dispatched" \
  "$base_commit" \
  "" \
  "" \
  "" \
  ""
release_team_lock

worker_body="$task_file を読み、担当 reviewer は $reviewer_id です。実装、検証、commit、report 作成後、ready_for_review を $reviewer_id に送ってください。"
reviewer_body="$task_file を読み、担当 worker $worker_id と直接やりとりしてください。worker の実装中 checkpoint、相談、ready_for_review を受け、review artifact を .agents/queue/reviews/${task_id}_${reviewer_id}.md に書いてください。"

"$SCRIPT_DIR/team_send.sh" --from manager "$worker_id" task_assigned "$task_id" "$worker_body" >/dev/null
"$SCRIPT_DIR/team_send.sh" --from manager "$reviewer_id" review_watch_assigned "$task_id" "$reviewer_body" >/dev/null

echo "$state_file"
