#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_state_update.sh show
  team_state_update.sh update <task_id> <dispatched|needs_review|review_fix|review_ask_manager|review_ok|done|blocked>
USAGE
}

command="${1:-}"

case "$command" in
  show)
    ensure_team_dirs
    state_file="$(team_state_file)"
    [[ -f "$state_file" ]] || die "STATE.md not found: $state_file"
    cat "$state_file"
    ;;
  update)
    [[ $# -eq 3 ]] || { usage; exit 2; }
    task_id="$2"
    next_status="$3"
    case "$next_status" in
      dispatched|needs_review|review_fix|review_ask_manager|review_ok|done|blocked) ;;
      *) die "invalid task status: $next_status" ;;
    esac
    state_file="$(team_task_state_file "$task_id")"
    [[ -f "$state_file" ]] || die "task state not found: $state_file"

    owner="$(team_task_state_field "$task_id" owner)"
    reviewer="$(team_task_state_field "$task_id" reviewer)"
    base_commit="$(team_task_state_field "$task_id" base_commit)"
    head_commit="$(team_task_state_field "$task_id" head_commit)"
    report_file="$(team_task_state_field "$task_id" report)"
    review_file="$(team_task_state_field "$task_id" review)"
    review_decision="$(team_task_state_field "$task_id" review_decision)"

    if [[ "$next_status" == "done" ]]; then
      [[ "$review_decision" == "OK" ]] || die "task $task_id can be marked done only after review Decision OK"
      [[ -n "$report_file" && -f "$report_file" ]] || die "task $task_id is missing report before done"
      [[ -n "$review_file" && -f "$review_file" ]] || die "task $task_id is missing review before done"
    fi

    team_write_task_state \
      "$task_id" \
      "$owner" \
      "$reviewer" \
      "$next_status" \
      "$base_commit" \
      "$head_commit" \
      "$report_file" \
      "$review_file" \
      "$review_decision"
    echo "$state_file"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
