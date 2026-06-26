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
    [[ -f "$state_file" ]] || die_rule \
      "task state not found: $state_file" \
      "the task has not been dispatched or its machine state is missing" \
      "dispatch the task before updating its state"

    manager="$(team_task_state_field "$task_id" manager)"
    owner="$(team_task_state_field "$task_id" owner)"
    reviewer="$(team_task_state_field "$task_id" reviewer)"
    base_commit="$(team_task_state_field "$task_id" base_commit)"
    head_commit="$(team_task_state_field "$task_id" head_commit)"
    report_file="$(team_task_state_field "$task_id" report)"
    review_file="$(team_task_state_field "$task_id" review)"
    review_decision="$(team_task_state_field "$task_id" review_decision)"
    done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
    architecture_required="$(team_task_state_field "$task_id" architecture_required)"
    architecture="$(team_task_state_field "$task_id" architecture)"
    release_bundle="$(team_task_state_field "$task_id" release_bundle)"

    if [[ "$next_status" == "done" ]]; then
      [[ "$review_decision" == "OK" ]] || die_rule \
        "task $task_id cannot be marked done" \
        "review_decision is ${review_decision:-missing}, but done requires reviewer Decision OK" \
        "reviewer must run make review-report TASK=$task_id REVIEWER=$reviewer DECISION=OK"
      [[ "$done_recommendation" == "true" ]] || die_rule \
        "task $task_id cannot be marked done" \
        "reviewer OK is missing done_recommendation=true" \
        "reviewer must run review-report with DECISION=OK so the review artifact records Done recommendation: yes and task state records done_recommendation=true"
      [[ -n "$report_file" && -f "$report_file" ]] || die_rule \
        "task $task_id cannot be marked done" \
        "the worker report is missing or the recorded report path does not exist" \
        "worker must run make report TASK=$task_id AGENT=$owner STATUS=needs_review and fill the report evidence"
      [[ -n "$review_file" && -f "$review_file" ]] || die_rule \
        "task $task_id cannot be marked done" \
        "the review artifact is missing or the recorded review path does not exist" \
        "reviewer must run make review-report TASK=$task_id REVIEWER=$reviewer DECISION=OK"
      if [[ "$architecture_required" == "true" ]]; then
        [[ -n "$architecture" ]] || die_rule \
          "task $task_id cannot be marked done" \
          "architecture_required=true but task state has no architecture artifact path" \
          "send an architecture request and wait for the architect to write the architecture note"
        [[ -f "$TEAM_ROOT/$architecture" || -f "$architecture" ]] || die_rule \
          "task $task_id cannot be marked done" \
          "architecture_required=true but the recorded architecture note does not exist: $architecture" \
          "architect must write the architecture note at the recorded path before manager marks done"
      fi
    fi

    team_write_task_state \
      "$task_id" \
      "$manager" \
      "$owner" \
      "$reviewer" \
      "$next_status" \
      "$base_commit" \
      "$head_commit" \
      "$report_file" \
      "$review_file" \
      "$review_decision" \
      "$done_recommendation" \
      "$architecture_required" \
      "$architecture" \
      "$release_bundle"
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
