#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

from=""
task_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) [[ $# -ge 2 ]] || die "--from requires a value"; from="$2"; shift 2 ;;
    --task) [[ $# -ge 2 ]] || die "--task requires a value"; task_id="$2"; shift 2 ;;
    --*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

[[ $# -eq 1 ]] || die "usage: team_research_request.sh --from <agent_id> [--task <task_id>] <body>"
body="$1"
[[ -n "$body" ]] || die_rule "research request body is empty" "research workers need a concrete question" "describe what must be learned and why"

ensure_team_dirs
team_config_validate
team_config_agent_record "$from" >/dev/null || die "unknown research caller: $from"
case "$(team_config_agent_field "$from" role)" in
  lead|manager|strategist|architect) ;;
  *) die "role cannot request research: $(team_config_agent_field "$from" role)" ;;
esac

request_id="$(team_research_id)"
created_at="$(team_now_utc)"
artifact_rel=".agents/queue/research/${request_id}.md"
artifact="$TEAM_ROOT/$artifact_rel"

{
  printf '# Research: %s\n\n' "$request_id"
  printf 'Status: queued\n'
  printf 'Caller: %s\n' "$from"
  printf 'Worker: unassigned\n'
  printf 'Related task: %s\n' "${task_id:--}"
  printf 'Created at: %s\n\n' "$created_at"
  printf '## Request\n\n%s\n\n' "$body"
  printf '## Result\n\n'
} > "$artifact"

acquire_team_lock "research-queue"
team_write_research_state "$request_id" "$from" "" "queued" "" "$artifact_rel" "$task_id" "$created_at"
release_team_lock

"$SCRIPT_DIR/team_research_assign.sh"

status="$(team_research_state_field "$request_id" status)"
worker="$(team_research_state_field "$request_id" worker)"
request_message_id="$(team_research_state_field "$request_id" request_message_id)"
printf 'request_id=%s\n' "$request_id"
printf 'status=%s\n' "$status"
printf 'worker=%s\n' "${worker:-queued}"
printf 'artifact=%s\n' "$artifact_rel"
[[ -n "$request_message_id" ]] && printf 'message_id=%s\n' "$request_message_id"
