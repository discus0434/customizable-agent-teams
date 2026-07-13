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
created_at="$(team_research_state_field "$request_id" created_at)"
[[ "$caller" == "$caller_id" ]] || {
  release_team_lock
  die_rule "research cancellation caller is invalid" "request $request_id belongs to $caller, not $caller_id" "cancel the request from its caller pane"
}
case "$status" in
  queued|active) ;;
  *)
    release_team_lock
    die_rule "research request cannot be cancelled: $request_id" "status=$status is terminal or transitioning" "cancel only queued or active research"
    ;;
esac

if [[ -n "$worker" ]]; then
  "$SCRIPT_DIR/team_send.sh" --from "$caller_id" --type research_cancelled --task "$task_id" --research "$request_id" "$worker" "$reason" >/dev/null
  exec_state="$TEAM_STATE_DIR/exec/$worker.env"
  if [[ -f "$exec_state" ]]; then
    exec_pid="$(sed -n "s/^pid='\{0,1\}\([0-9]*\)'\{0,1\}$/\1/p" "$exec_state" | head -n 1)"
    exec_ref="$(sed -n "s/^ref='\{0,1\}\([^']*\)'\{0,1\}$/\1/p" "$exec_state" | head -n 1)"
    if [[ "$exec_ref" == "$request_id" && -n "$exec_pid" ]] && kill -0 "$exec_pid" 2>/dev/null; then
      pkill -TERM -P "$exec_pid" 2>/dev/null || true
      kill -TERM "$exec_pid" 2>/dev/null || true
      {
        printf 'ended_at=%s\n' "'$(team_now_utc)'"
        printf 'exit_code=%s\n' "'cancelled'"
      } >> "$exec_state"
    fi
  fi
fi
team_write_research_state "$request_id" "$caller" "$worker" "cancelled" "$request_message_id" "$artifact" "$task_id" "$created_at"
team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "cancelled"
release_team_lock

if [[ -n "$worker" ]]; then
  team_mark_research_inbox_processed "$worker" "$request_id" research_request
fi
"$SCRIPT_DIR/team_research_assign.sh"
printf 'request_id=%s\nstatus=cancelled\n' "$request_id"
