#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_report.sh <task_id> <needs_supervision|ready_for_lead|blocked>" >&2
}

[[ $# -eq 2 ]] || { usage; exit 2; }

task_id="$1"
status="$2"
[[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
  "report agent identity is unavailable" \
  "reports are written by the assigned implementation worker pane" \
  "run make report inside the assigned worker pane"
agent_id="$TEAM_AGENT_ID"

lane="normal"
case "$task_id" in
  T-E-*) lane="express" ;;
esac

case "$status" in
  needs_supervision)
    [[ "$lane" == "normal" ]] || die "express tasks report STATUS=ready_for_lead" ;;
  ready_for_lead)
    [[ "$lane" == "express" ]] || die "ready_for_lead is only for express tasks" ;;
  blocked) ;;
  *) die "invalid report status: $status" ;;
esac

team_config_agent_record "$agent_id" >/dev/null || die "unknown agent: $agent_id"
agent_role="$(team_config_agent_field "$agent_id" role)"
if [[ "$lane" == "express" ]]; then
  [[ "$agent_role" == "express-worker" ]] || die "$agent_id is not an express worker"
else
  case "$agent_role" in
    general-worker|hard-task-worker|frontend-worker) ;;
    *) die "$agent_id is not an implementation worker" ;;
  esac
fi

ensure_team_dirs
report_file="$TEAM_QUEUE_DIR/reports/${task_id}_${agent_id}.md"
state_file="$(team_task_state_file "$task_id")"
[[ -f "$state_file" ]] || die "task is not dispatched: $task_id"

worker="$(team_task_state_field "$task_id" worker)"
owner="$(team_task_state_field "$task_id" owner)"
supervisor="$(team_task_state_field "$task_id" supervisor)"
base_commit="$(team_task_state_field "$task_id" base_commit)"
architecture_required="$(team_task_state_field "$task_id" architecture_required)"
architecture="$(team_task_state_field "$task_id" architecture)"
direction_status="$(team_task_state_field "$task_id" direction_status)"
direction_artifact="$(team_task_state_field "$task_id" direction_artifact)"

[[ "$worker" == "$agent_id" ]] || die "task $task_id is assigned to $worker, not $agent_id"
[[ -n "$owner" ]] || die "task $task_id state is missing owner"
if [[ "$lane" != "express" ]]; then
  [[ -n "$supervisor" ]] || die "task $task_id state is missing supervisor"
fi
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

team_require_task_paths_clean "$task_id"
task_commits="$(team_task_commits "$task_id" "$base_commit" | paste -sd ' ' -)"
if [[ -z "$task_commits" ]]; then
  # 外部repoで完結するtaskはteam rootにcommitを作らない。証拠はreport本文が持つ
  if team_task_allowed_paths_all_external "$TEAM_QUEUE_DIR/tasks/$task_id.md"; then
    task_commits="none"
  else
    die_rule \
      "task has no recorded commits: $task_id" \
      "review requires commits created for this task after dispatch base $base_commit" \
      "commit the implementation with make task-commit TASK=$task_id MESSAGE='<summary>'"
  fi
fi

if [[ ! -f "$report_file" ]]; then
  {
    printf '# Report: %s by %s\n\n' "$task_id" "$agent_id"
    printf 'Status: %s\n' "$status"
    if [[ "$lane" == "express" ]]; then
      printf 'Base commit: %s\n' "$base_commit"
      printf 'Task commits: %s\n\n' "$task_commits"
    else
      printf 'Supervisor: %s\n' "$supervisor"
      printf 'Base commit: %s\n' "$base_commit"
      printf 'Task commits: %s\n' "$task_commits"
      printf 'Supervision artifact: none\n'
      printf 'Supervision decision: none\n'
      printf 'Done recommendation: false\n'
      printf 'Architecture required: %s\n' "${architecture_required:-false}"
      printf 'Architecture: %s\n' "${architecture:-none}"
      printf 'Direction status: %s\n' "${direction_status:-not_applicable}"
      printf 'Direction artifact: %s\n\n' "${direction_artifact:-none}"
    fi
    cat <<'REPORT'
## Summary

<!-- TEAM_PLACEHOLDER: summary -->

## Files changed

<!-- TEAM_PLACEHOLDER: files-changed -->

## Commits

## Verification

<!-- TEAM_PLACEHOLDER: task-verification -->

## Post-change

<!-- TEAM_PLACEHOLDER: post-change -->

## Smoke

<!-- TEAM_PLACEHOLDER: smoke -->
REPORT
    if [[ "$lane" != "express" ]]; then
      cat <<'REPORT'

## Supervision

<!-- TEAM_PLACEHOLDER: supervision -->

## Strategy And Architecture

<!-- TEAM_PLACEHOLDER: specialist-artifacts -->
REPORT
    fi
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
elif [[ "$lane" == "express" ]]; then
  team_update_markdown_field "$report_file" "Status" "$status"
  team_update_markdown_field "$report_file" "Base commit" "$base_commit"
  team_update_markdown_field "$report_file" "Task commits" "$task_commits"
else
  team_update_markdown_field "$report_file" "Status" "$status"
  team_update_markdown_field "$report_file" "Supervisor" "$supervisor"
  team_update_markdown_field "$report_file" "Base commit" "$base_commit"
  team_update_markdown_field "$report_file" "Task commits" "$task_commits"
  team_update_markdown_field "$report_file" "Supervision artifact" "none"
  team_update_markdown_field "$report_file" "Supervision decision" "none"
  team_update_markdown_field "$report_file" "Done recommendation" "false"
  team_update_markdown_field "$report_file" "Architecture required" "${architecture_required:-false}"
  team_update_markdown_field "$report_file" "Architecture" "${architecture:-none}"
  team_update_markdown_field "$report_file" "Direction status" "${direction_status:-not_applicable}"
  team_update_markdown_field "$report_file" "Direction artifact" "${direction_artifact:-none}"
fi

commits_file="$(mktemp)"
if [[ "$task_commits" == "none" ]]; then
  printf -- '- none (all allowed paths are outside the team repository)\n' >> "$commits_file"
else
  for commit in $task_commits; do
    printf -- '- %s\n' "$(git -C "$TEAM_ROOT" show -s --format='%H %s' "$commit")" >> "$commits_file"
  done
fi
team_replace_markdown_section "$report_file" "Commits" "$commits_file"
rm -f "$commits_file"

team_write_task_state \
  "$task_id" \
  "$owner" \
  "$agent_id" \
  "$supervisor" \
  "$status" \
  "$base_commit" \
  "$task_commits" \
  "$report_file" \
  "" \
  "" \
  "false" \
  "${architecture_required:-false}" \
  "$architecture" \
  "$direction_status" \
  "$direction_artifact"

team_mark_inbox_processed "$agent_id" "$task_id"
printf '%s\n' "$report_file"
# 散文の待機宣言はどの照合にも映らない。blockedを宣言する瞬間に、
# pendingが立つmessageへの変換を想起させる(stdoutはreport pathの契約)
if [[ "$status" == "blocked" ]]; then
  printf 'next: blockerを解く相手へ、pendingが立つmessage(questionなど)を送ったか確認する。散文の待機宣言は誰にも届かない。\n' >&2
fi
