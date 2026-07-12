#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

ensure_team_dirs
team_config_validate

while true; do
  acquire_team_lock "research-queue"

  idle_worker=""
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if ! team_research_worker_active_request "$candidate" >/dev/null; then
      idle_worker="$candidate"
      break
    fi
  done < <(team_config_role_agent_ids research-worker)

  queued_state=""
  while IFS='|' read -r _created candidate; do
    [[ -n "$candidate" ]] || continue
    if [[ "$(extract_json_field status < "$candidate")" == "queued" ]]; then
      queued_state="$candidate"
      break
    fi
  done < <(
    while IFS= read -r candidate; do
      printf '%s|%s\n' "$(extract_json_field created_at < "$candidate")" "$candidate"
    done < <(find "$TEAM_STATE_DIR/research" -maxdepth 1 -type f -name '*.json') | sort
  )

  if [[ -z "$idle_worker" || -z "$queued_state" ]]; then
    release_team_lock
    break
  fi

  request_id="$(extract_json_field request_id < "$queued_state")"
  caller="$(extract_json_field caller < "$queued_state")"
  artifact="$(extract_json_field artifact < "$queued_state")"
  task_id="$(extract_json_field task_id < "$queued_state")"
  created_at="$(extract_json_field created_at < "$queued_state")"

  team_write_research_state "$request_id" "$caller" "$idle_worker" "assigning" "" "$artifact" "$task_id" "" "$created_at"
  team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "assigning"
  team_update_markdown_field "$TEAM_ROOT/$artifact" "Worker" "$idle_worker"

  body="Research request ${request_id}を調査してください。プロジェクトコードは編集せず、結果を${artifact}のResultへ書いて依頼元へ返してください。"
  if send_output="$("$SCRIPT_DIR/team_send.sh" --from "$caller" --type research_request --task "$task_id" --research "$request_id" "$idle_worker" "$body")"; then
    message_id="$(printf '%s\n' "$send_output" | sed -n 's/^message_id=//p' | tail -n 1)"
    if [[ -z "$message_id" ]]; then
      team_write_research_state "$request_id" "$caller" "" "queued" "" "$artifact" "$task_id" "" "$created_at"
      team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "queued"
      team_update_markdown_field "$TEAM_ROOT/$artifact" "Worker" "unassigned"
      release_team_lock
      die_rule \
        "research assignment returned no message id: $request_id" \
        "the request could not be linked to an inbox message" \
        "inspect the message writer, then run team_research_assign.sh again"
    fi
    team_write_research_state "$request_id" "$caller" "$idle_worker" "active" "$message_id" "$artifact" "$task_id" "" "$created_at"
    team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "active"
  else
    status=$?
    team_write_research_state "$request_id" "$caller" "" "queued" "" "$artifact" "$task_id" "" "$created_at"
    team_update_markdown_field "$TEAM_ROOT/$artifact" "Status" "queued"
    team_update_markdown_field "$TEAM_ROOT/$artifact" "Worker" "unassigned"
    release_team_lock
    exit "$status"
  fi
  release_team_lock
done
