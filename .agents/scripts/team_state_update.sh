#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_state_update.sh show
  team_state_update.sh update <task_id> <dispatched|needs_supervision|supervision_fix|supervision_ask_manager|supervision_ok|manager_fix|done|blocked>
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
      dispatched|needs_supervision|supervision_fix|supervision_ask_manager|supervision_ok|manager_fix|done|blocked) ;;
      *) die "invalid task status: $next_status" ;;
    esac

    state_file="$(team_task_state_file "$task_id")"
    [[ -f "$state_file" ]] || die_rule \
      "task state not found: $state_file" \
      "the task has not been dispatched" \
      "dispatch the task before updating its state"

    manager="$(team_task_state_field "$task_id" manager)"
    worker="$(team_task_state_field "$task_id" worker)"
    supervisor="$(team_task_state_field "$task_id" supervisor)"
    base_commit="$(team_task_state_field "$task_id" base_commit)"
    task_commits="$(team_task_state_field "$task_id" task_commits)"
    report_file="$(team_task_state_field "$task_id" report)"
    supervision_artifact="$(team_task_state_field "$task_id" supervision_artifact)"
    supervision_decision="$(team_task_state_field "$task_id" supervision_decision)"
    done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
    architecture_required="$(team_task_state_field "$task_id" architecture_required)"
    architecture="$(team_task_state_field "$task_id" architecture)"
    release_bundle="$(team_task_state_field "$task_id" release_bundle)"
    direction_status="$(team_task_state_field "$task_id" direction_status)"
    direction_artifact="$(team_task_state_field "$task_id" direction_artifact)"

    if [[ "$next_status" == "done" ]]; then
      [[ "$supervision_decision" == "OK" ]] || die_rule \
        "task $task_id cannot be marked done" \
        "supervision_decision is ${supervision_decision:-missing}, but done requires OK" \
        "$supervisor must run make supervision-report TASK=$task_id DECISION=OK"
      [[ "$done_recommendation" == "true" ]] || die_rule \
        "task $task_id cannot be marked done" \
        "supervisor OK is missing done_recommendation=true" \
        "$supervisor must record an OK supervision decision"
      [[ -n "$report_file" && -f "$report_file" ]] || die_rule \
        "task $task_id cannot be marked done" \
        "the implementation report is missing" \
        "$worker must run make report STATUS=needs_supervision and fill the report evidence"
      team_require_report_matches_task_state "$task_id" "$report_file" "$base_commit" "$task_commits"
      team_require_no_placeholders "implementation report" "$report_file"
      [[ -n "$supervision_artifact" && -f "$supervision_artifact" ]] || die_rule \
        "task $task_id cannot be marked done" \
        "the supervision artifact is missing: $supervision_artifact" \
        "$supervisor must write the final supervision artifact and record OK"
      team_require_no_placeholders "supervision artifact" "$supervision_artifact"
      if [[ "$architecture_required" == "true" ]]; then
        [[ -n "$architecture" ]] || die_rule \
          "task $task_id cannot be marked done" \
          "architecture_required=true but no architecture artifact is recorded" \
          "request architecture direction and wait for the recorded note"
        [[ -f "$TEAM_ROOT/$architecture" || -f "$architecture" ]] || die_rule \
          "task $task_id cannot be marked done" \
          "the recorded architecture note does not exist: $architecture" \
          "architect must write the note before Manager marks done"
      fi
    fi

    team_write_task_state \
      "$task_id" "$manager" "$worker" "$supervisor" "$next_status" \
      "$base_commit" "$task_commits" "$report_file" "$supervision_artifact" \
      "$supervision_decision" "$done_recommendation" "$architecture_required" \
      "$architecture" "$release_bundle" "$direction_status" "$direction_artifact"
    team_mark_inbox_processed "$manager" "$task_id" ""
    printf '%s\n' "$state_file"
    ;;
  -h|--help) usage ;;
  *) usage; exit 2 ;;
esac
