#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

[[ $# -eq 3 ]] || die "usage: team_research_cancel.sh <request_id> <caller_id> <reason>"
request_id="$1"
caller_id="$2"
reason="$3"
[[ -n "$reason" ]] || die "research cancellation reason is empty"

acquire_team_lock "research-queue"
state_file="$(team_research_state_file "$request_id")"
[[ -f "$state_file" ]] || {
  release_team_lock
  die_rule "research request not found: $request_id" "no request state exists" "use a request id shown by make team-status"
}
caller="$(team_research_state_field "$request_id" caller)"
worker="$(team_research_state_field "$request_id" worker)"
status="$(team_research_state_field "$request_id" status)"
request_message_id="$(team_research_state_field "$request_id" request_message_id)"
artifact="$(team_research_state_field "$request_id" artifact)"
task_id="$(team_research_state_field "$request_id" task_id)"
question_message_id="$(team_research_state_field "$request_id" question_message_id)"
created_at="$(team_research_state_field "$request_id" created_at)"
[[ "$caller" == "$caller_id" ]] || {
  release_team_lock
  die_rule "research cancellation caller is invalid" "request $request_id belongs to $caller, not $caller_id" "cancel the request from its caller pane"
}
case "$status" in
  queued|active|waiting_for_caller) ;;
  *)
    release_team_lock
    die_rule "research request cannot be cancelled: $request_id" "status=$status is terminal or transitioning" "cancel only queued, active, or waiting_for_caller research"
    ;;
esac

if [[ -n "$worker" ]]; then
  "$SCRIPT_DIR/team_send.sh" --from "$caller_id" --type research_cancelled --task "$task_id" --research "$request_id" "$worker" "$reason" >/dev/null
fi
team_write_research_state "$request_id" "$caller" "$worker" "cancelled" "$request_message_id" "$artifact" "$task_id" "$question_message_id" "$created_at"
team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "cancelled"
release_team_lock

if [[ -n "$worker" ]]; then
  team_mark_research_inbox_processed "$worker" "$request_id" research_request research_answer
fi
team_mark_research_inbox_processed "$caller" "$request_id" research_question
"$SCRIPT_DIR/team_research_assign.sh"
printf 'request_id=%s\nstatus=cancelled\n' "$request_id"
