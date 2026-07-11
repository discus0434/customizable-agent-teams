#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

[[ $# -eq 3 ]] || die "usage: team_research_answer.sh <request_id> <caller_id> <body>"
request_id="$1"
caller_id="$2"
body="$3"
[[ -n "$body" ]] || die "research answer body is empty"

acquire_team_lock "research-queue"
caller="$(team_research_state_field "$request_id" caller)"
worker="$(team_research_state_field "$request_id" worker)"
status="$(team_research_state_field "$request_id" status)"
request_message_id="$(team_research_state_field "$request_id" request_message_id)"
artifact="$(team_research_state_field "$request_id" artifact)"
task_id="$(team_research_state_field "$request_id" task_id)"
question_message_id="$(team_research_state_field "$request_id" question_message_id)"
created_at="$(team_research_state_field "$request_id" created_at)"
[[ "$caller" == "$caller_id" && "$status" == "waiting_for_caller" ]] || {
  release_team_lock
  die_rule \
    "research answer is not valid for $request_id" \
    "caller=$caller status=$status, but answers require the waiting caller $caller_id" \
    "answer the pending clarification for a request in waiting_for_caller"
}

"$SCRIPT_DIR/team_send.sh" --from "$caller_id" --type research_answer --task "$task_id" --research "$request_id" "$worker" "$body" >/dev/null
team_write_research_state "$request_id" "$caller" "$worker" "active" "$request_message_id" "$artifact" "$task_id" "$question_message_id" "$created_at"
team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "active"
release_team_lock
team_mark_research_inbox_processed "$caller_id" "$request_id" research_question
printf 'request_id=%s\nstatus=active\n' "$request_id"
