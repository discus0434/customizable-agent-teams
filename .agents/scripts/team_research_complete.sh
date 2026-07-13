#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

[[ $# -eq 2 ]] || die "usage: team_research_complete.sh <request_id> <worker_id>"
request_id="$1"
worker_id="$2"
state_file="$(team_research_state_file "$request_id")"
[[ -f "$state_file" ]] || die "research request not found: $request_id"

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
    "research request cannot be completed: $request_id" \
    "worker=$assigned_worker status=$status, but completion requires the active assigned worker $worker_id" \
    "resolve any pending caller question, then complete the active request"
}
[[ -f "$TEAM_ROOT/$artifact" ]] || {
  release_team_lock
  die_rule "research artifact is missing: $request_id" "$artifact does not exist" "restore the request artifact before completing the request"
}
team_markdown_section_has_content "$TEAM_ROOT/$artifact" Result || {
  release_team_lock
  die_rule \
    "research result is empty: $request_id" \
    "$artifact has no substantive content under Result" \
    "write the evidence-first result before replying"
}

body="Research result: ${artifact}を確認してください。"
"$SCRIPT_DIR/team_send.sh" --from "$worker_id" --type research_result --task "$task_id" --research "$request_id" "$caller" "$body" >/dev/null
team_write_research_state "$request_id" "$caller" "$worker_id" "completed" "$request_message_id" "$artifact" "$task_id" "$created_at"
team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "completed"
release_team_lock
team_mark_research_inbox_processed "$worker_id" "$request_id" research_request research_cancelled
"$SCRIPT_DIR/team_research_assign.sh"
printf 'request_id=%s\nstatus=completed\nartifact=%s\n' "$request_id" "$artifact"
