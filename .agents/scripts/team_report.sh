#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_report.sh <task_id> <needs_supervision|blocked>" >&2
}

[[ $# -eq 2 ]] || { usage; exit 2; }

task_id="$1"
status="$2"
[[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
  "report agent identity is unavailable" \
  "reports are written by the assigned implementation worker pane" \
  "run make report inside the assigned worker pane"
agent_id="$TEAM_AGENT_ID"

case "$status" in
  needs_supervision|blocked) ;;
  *) die "invalid report status: $status" ;;
esac

team_config_agent_record "$agent_id" >/dev/null || die "unknown agent: $agent_id"
agent_role="$(team_config_agent_field "$agent_id" role)"
case "$agent_role" in
  general-worker|hard-task-worker|frontend-worker) ;;
  *) die "$agent_id is not an implementation worker" ;;
esac

ensure_team_dirs
report_file="$TEAM_QUEUE_DIR/reports/${task_id}_${agent_id}.md"
state_file="$(team_task_state_file "$task_id")"
[[ -f "$state_file" ]] || die "task is not dispatched: $task_id"

worker="$(team_task_state_field "$task_id" worker)"
manager="$(team_task_state_field "$task_id" manager)"
supervisor="$(team_task_state_field "$task_id" supervisor)"
base_commit="$(team_task_state_field "$task_id" base_commit)"
architecture_required="$(team_task_state_field "$task_id" architecture_required)"
architecture="$(team_task_state_field "$task_id" architecture)"
release_bundle="$(team_task_state_field "$task_id" release_bundle)"
direction_status="$(team_task_state_field "$task_id" direction_status)"
direction_artifact="$(team_task_state_field "$task_id" direction_artifact)"

[[ "$worker" == "$agent_id" ]] || die "task $task_id is assigned to $worker, not $agent_id"
[[ -n "$manager" ]] || die "task $task_id state is missing manager"
[[ -n "$supervisor" ]] || die "task $task_id state is missing supervisor"
[[ -n "$base_commit" ]] || die "task $task_id state is missing base_commit"

if [[ "$agent_role" == "frontend-worker" ]]; then
  case "$direction_status" in
    proceed|not_needed) ;;
    *) die_rule \
      "frontend direction is not resolved: $task_id" \
      "direction_status=$direction_status, but frontend implementation cannot be reported before critic direction is resolved" \
      "work with $supervisor until direction is PROCEED or NOT_NEEDED" ;;
  esac
fi

head_commit="$(git -C "$TEAM_ROOT" rev-parse HEAD)"
commits="$(git -C "$TEAM_ROOT" log --oneline "$base_commit..$head_commit" -- 2>/dev/null || true)"

if [[ ! -f "$report_file" ]]; then
  {
    printf '# Report: %s by %s\n\n' "$task_id" "$agent_id"
    printf 'Status: %s\n' "$status"
    printf 'Supervisor: %s\n' "$supervisor"
    printf 'Base commit: %s\n' "$base_commit"
    printf 'Head commit: %s\n' "$head_commit"
    printf 'Supervision artifact: none\n'
    printf 'Supervision decision: none\n'
    printf 'Done recommendation: false\n'
    printf 'Architecture required: %s\n' "${architecture_required:-false}"
    printf 'Architecture: %s\n' "${architecture:-none}"
    printf 'Release bundle: %s\n' "${release_bundle:-none}"
    printf 'Direction status: %s\n' "${direction_status:-not_applicable}"
    printf 'Direction artifact: %s\n\n' "${direction_artifact:-none}"
    cat <<'REPORT'
## Summary

<!-- TEAM_PLACEHOLDER: summary -->

## Files changed

<!-- TEAM_PLACEHOLDER: files-changed -->

## Commits

REPORT
    if [[ -n "$commits" ]]; then
      printf '%s\n' "$commits" | sed 's/^/- /'
    else
      printf '%s\n' '- none'
    fi
    cat <<'REPORT'

## Verification

<!-- TEAM_PLACEHOLDER: task-verification -->

## Post-change

<!-- TEAM_PLACEHOLDER: post-change -->

## Smoke

<!-- TEAM_PLACEHOLDER: smoke -->

## Supervision

<!-- TEAM_PLACEHOLDER: supervision -->

## Strategy And Architecture

<!-- TEAM_PLACEHOLDER: specialist-artifacts -->
REPORT
    if [[ "$agent_role" == "frontend-worker" ]]; then
      cat <<'REPORT'

## Visual Evidence

<!-- TEAM_PLACEHOLDER: visual-evidence -->
REPORT
    fi
    cat <<'REPORT'

## Blockers And Questions

<!-- TEAM_PLACEHOLDER: blockers-and-questions -->

## Memory Proposals

<!-- TEAM_PLACEHOLDER: memory-proposals -->
REPORT
  } > "$report_file"
else
  team_update_markdown_field "$report_file" "Status" "$status"
  team_update_markdown_field "$report_file" "Supervisor" "$supervisor"
  team_update_markdown_field "$report_file" "Base commit" "$base_commit"
  team_update_markdown_field "$report_file" "Head commit" "$head_commit"
  team_update_markdown_field "$report_file" "Supervision artifact" "none"
  team_update_markdown_field "$report_file" "Supervision decision" "none"
  team_update_markdown_field "$report_file" "Done recommendation" "false"
  team_update_markdown_field "$report_file" "Architecture required" "${architecture_required:-false}"
  team_update_markdown_field "$report_file" "Architecture" "${architecture:-none}"
  team_update_markdown_field "$report_file" "Release bundle" "${release_bundle:-none}"
  team_update_markdown_field "$report_file" "Direction status" "${direction_status:-not_applicable}"
  team_update_markdown_field "$report_file" "Direction artifact" "${direction_artifact:-none}"
fi

team_write_task_state \
  "$task_id" \
  "$manager" \
  "$agent_id" \
  "$supervisor" \
  "$status" \
  "$base_commit" \
  "$head_commit" \
  "$report_file" \
  "" \
  "" \
  "false" \
  "${architecture_required:-false}" \
  "$architecture" \
  "$release_bundle" \
  "$direction_status" \
  "$direction_artifact"

team_mark_inbox_processed "$agent_id" "$task_id" ""
printf '%s\n' "$report_file"
