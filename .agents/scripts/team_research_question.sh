#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

[[ $# -eq 3 ]] || die "usage: team_research_question.sh <request_id> <worker_id> <body>"
request_id="$1"
worker_id="$2"
body="$3"
[[ -n "$body" ]] || die "research question body is empty"

acquire_team_lock "research-queue"
caller="$(team_research_state_field "$request_id" caller)"
assigned_worker="$(team_research_state_field "$request_id" worker)"
status="$(team_research_state_field "$request_id" status)"
request_message_id="$(team_research_state_field "$request_id" request_message_id)"
artifact="$(team_research_state_field "$request_id" artifact)"
task_id="$(team_research_state_field "$request_id" task_id)"
created_at="$(team_research_state_field "$request_id" created_at)"
[[ "$assigned_worker" == "$worker_id" && "$status" == "active" ]] || {
  release_team_lock
  die_rule \
    "research question is not valid for $request_id" \
    "worker=$assigned_worker status=$status, but questions require the active assigned worker $worker_id" \
    "ask about the request currently assigned to this worker"
}

team_write_research_state "$request_id" "$caller" "$worker_id" "waiting_for_caller" "$request_message_id" "$artifact" "$task_id" "" "$created_at"
team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "waiting_for_caller"
if send_output="$("$SCRIPT_DIR/team_send.sh" --from "$worker_id" --type research_question --task "$task_id" --research "$request_id" "$caller" "$body")"; then
  question_message_id="$(printf '%s\n' "$send_output" | sed -n 's/^message_id=//p' | tail -n 1)"
  if [[ -z "$question_message_id" ]]; then
    team_write_research_state "$request_id" "$caller" "$worker_id" "active" "$request_message_id" "$artifact" "$task_id" "" "$created_at"
    team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "active"
    release_team_lock
    die_rule \
      "research question returned no message id: $request_id" \
      "the clarification could not be linked to the caller inbox" \
      "inspect the message writer, then ask the question again"
  fi
  team_write_research_state "$request_id" "$caller" "$worker_id" "waiting_for_caller" "$request_message_id" "$artifact" "$task_id" "$question_message_id" "$created_at"
else
  send_status=$?
  team_write_research_state "$request_id" "$caller" "$worker_id" "active" "$request_message_id" "$artifact" "$task_id" "" "$created_at"
  team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "active"
  release_team_lock
  exit "$send_status"
fi
release_team_lock
team_mark_research_inbox_processed "$worker_id" "$request_id" research_request research_answer
printf 'request_id=%s\nstatus=waiting_for_caller\nmessage_id=%s\n' "$request_id" "$question_message_id"
