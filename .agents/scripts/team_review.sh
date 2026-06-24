#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_review.sh <task_id> <worker_id>" >&2
}

[[ $# -eq 2 ]] || { usage; exit 2; }

task_id="$1"
worker_id="$2"

[[ "$task_id" != */* ]] || die "task_id must not contain '/': $task_id"
[[ "$worker_id" != */* ]] || die "worker_id must not contain '/': $worker_id"

if ! team_config_agent_record "$worker_id" >/dev/null; then
  die "unknown worker: $worker_id"
fi

worker_role="$(team_config_agent_field "$worker_id" role)"
[[ "$worker_role" == "worker" ]] || die "$worker_id is not a worker agent"

review_cli="$(team_config_review_field cli)" || die "team.review.cli is missing in $TEAM_CONFIG_FILE"
review_model="$(team_config_review_field model)" || die "team.review.model is missing in $TEAM_CONFIG_FILE"
review_effort="$(team_config_review_field effort)" || die "team.review.effort is missing in $TEAM_CONFIG_FILE"
review_timeout_seconds="$(team_config_review_field timeout_seconds)" || die "team.review.timeout_seconds is missing in $TEAM_CONFIG_FILE"
review_output_dir="$(team_config_review_field output_dir)" || die "team.review.output_dir is missing in $TEAM_CONFIG_FILE"

case "$review_cli" in
  claude|codex) ;;
  *) die "unsupported team.review.cli: $review_cli" ;;
esac
require_command "$review_cli"

case "$review_timeout_seconds" in
  ''|*[!0-9]*) die "team.review.timeout_seconds must be a positive integer: $review_timeout_seconds" ;;
esac
(( review_timeout_seconds > 0 )) || die "team.review.timeout_seconds must be greater than zero"

ensure_team_dirs

task_file="$TEAM_QUEUE_DIR/tasks/$task_id.md"
report_file="$TEAM_QUEUE_DIR/reports/${task_id}_${worker_id}.md"
state_file="$(team_task_state_file "$task_id")"

[[ -f "$task_file" ]] || die "task file not found: $task_file"
[[ -f "$report_file" ]] || die "report file not found: $report_file"
[[ -f "$state_file" ]] || die "task is not assigned: $task_id"

state_owner="$(team_task_state_field "$task_id" owner)"
base_commit="$(team_task_state_field "$task_id" base_commit)"
previous_integration="$(team_task_state_field "$task_id" integration)"

[[ "$state_owner" == "$worker_id" ]] || die "task $task_id is owned by $state_owner, not $worker_id"
[[ -n "$base_commit" ]] || die "task $task_id state is missing base_commit"

if ! team_git_is_clean "$TEAM_ROOT"; then
  team_git_dirty_summary "$TEAM_ROOT" >&2
  die "team root must be clean before review: $TEAM_ROOT"
fi

head_commit="$(git -C "$TEAM_ROOT" rev-parse HEAD)"

if grep -q '未記入' "$report_file"; then
  die "report still contains 未記入 placeholders: $report_file"
fi

for section in "## Verification" "## Post-change" "## Smoke"; do
  awk -v section="$section" '
    $0 == section { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && /^- Result:[[:space:]]*[^[:space:]]/ { result = 1 }
    in_section && /^- Evidence:[[:space:]]*[^[:space:]]/ { evidence = 1 }
    END {
      if (!in_section || !result || !evidence) {
        exit 1
      }
    }
  ' "$report_file" || die "report section requires non-empty Result and Evidence before review: $section in $report_file"
done

output_dir="$(abs_path "$review_output_dir")"
mkdir -p "$output_dir"

summary_file="$output_dir/${task_id}_${worker_id}_review.md"
raw_file="$output_dir/${task_id}_${worker_id}_review_${review_cli}.txt"
prompt_file="$output_dir/${task_id}_${worker_id}_review_prompt.txt"
status_file="$output_dir/${task_id}_${worker_id}_git_status.txt"
committed_diff_file="$output_dir/${task_id}_${worker_id}_committed_diff.patch"
exec_log="$output_dir/${task_id}_${worker_id}_review.exec.log"

git -C "$TEAM_ROOT" status --short > "$status_file"
git -C "$TEAM_ROOT" diff --no-ext-diff "$base_commit..$head_commit" -- . > "$committed_diff_file"

{
cat <<PROMPT
You are a read-only verifier for a tmux-based agent team. Return review only and leave files unchanged.

Review the worker's implementation against the task. The worker is responsible for implementation, post-change checks, smoke checks, and follow-up fixes. Your job is only to review and return findings.

Use only the embedded evidence below. Do not run commands, do not inspect files, and do not ask another agent.

Paths:
- Task file: $task_file
- Worker report: $report_file
- Team root: $TEAM_ROOT
- Base commit: $base_commit
- Head commit: $head_commit
- Git status snapshot: $status_file
- Committed task diff: $committed_diff_file

Focus:
- Task acceptance and explicit constraints.
- User-visible behavior, API/data/event contracts, ownership boundaries, side effects, failure behavior, and verification evidence.
- Scope discipline: implementation matches the requested acceptance without extra compatibility APIs, aliases, default-value fallbacks, or ad-hoc alternate paths.
- Test quality: prefer public contract, structural, or integration evidence; do not request brittle, fragile, flaky, or implementation-detail-heavy tests.

Use the evidence already produced by the worker. Skip nested review commands and additional verification runs.

Output exactly these sections:

Decision: OK | FIX | ASK_LEAD

## Findings

- Severity: Critical | Major | Minor | Info
  Task section:
  File/path:
  Issue:
  Required worker action:

## Verification Gaps

## Notes

Use OK only when there are no Critical or Major issues.
Use FIX when the worker can make a clear correction within the assigned task.
Use ASK_LEAD when the remaining decision changes scope, contract, ownership, or user-visible behavior.

## Embedded Evidence

### Task File

BEGIN TASK FILE
PROMPT
cat "$task_file"
cat <<PROMPT
END TASK FILE

### Worker Report

BEGIN WORKER REPORT
PROMPT
cat "$report_file"
cat <<PROMPT
END WORKER REPORT

### Git Status Snapshot

BEGIN GIT STATUS
PROMPT
cat "$status_file"
cat <<PROMPT
END GIT STATUS

### Committed Task Diff

BEGIN COMMITTED DIFF
PROMPT
cat "$committed_diff_file"
cat <<'PROMPT'
END COMMITTED DIFF
PROMPT
} > "$prompt_file"

run_review_command() {
  local timeout_seconds="$1"
  local cwd="$2"
  local stdout_file="$3"
  local stderr_file="$4"
  shift 4
  local pid
  local elapsed=0

  if [[ "$stdout_file" == "$stderr_file" ]]; then
    (
      cd "$cwd"
      exec "$@"
    ) > "$stdout_file" 2>&1 &
  else
    (
      cd "$cwd"
      exec "$@"
    ) > "$stdout_file" 2> "$stderr_file" &
  fi
  pid="$!"

  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= timeout_seconds )); then
      printf '[team] review command timed out after %s seconds\n' "$timeout_seconds" >> "$stderr_file"
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
}

status=0
prompt="$(<"$prompt_file")"
case "$review_cli" in
  claude)
    cmd=(
      claude
      --print
      --model "$review_model"
      --permission-mode bypassPermissions
      --output-format text
      --no-session-persistence
      "$prompt"
    )
    run_review_command "$review_timeout_seconds" "$TEAM_ROOT" "$raw_file" "$exec_log" env CLAUDE_CODE_EFFORT_LEVEL="$review_effort" "${cmd[@]}" || status=$?
    ;;
  codex)
    cmd=(
      codex
      exec
      --model "$review_model"
      --dangerously-bypass-approvals-and-sandbox
      --cd "$TEAM_ROOT"
      -c "model_reasoning_effort=\"$review_effort\""
      --output-last-message "$raw_file"
      "$prompt"
    )
    run_review_command "$review_timeout_seconds" "$TEAM_ROOT" "$exec_log" "$exec_log" "${cmd[@]}" || status=$?
    ;;
esac

if [[ "$status" -ne 0 ]]; then
  die "review failed with exit status $status. See $exec_log"
fi

[[ -s "$raw_file" ]] || die "review did not write output: $raw_file"

{
  echo "# Review: $task_id by $worker_id"
  echo
  echo "Model: $review_model"
  echo "Effort: $review_effort"
  echo "Task: $task_file"
  echo "Report: $report_file"
  echo "Team root: $TEAM_ROOT"
  echo "Base commit: $base_commit"
  echo "Head commit: $head_commit"
  echo "Git status: $status_file"
  echo "Committed diff: $committed_diff_file"
  echo "Raw output: $raw_file"
  echo "Exec log: $exec_log"
  echo
  echo "## Result"
  echo
  cat "$raw_file"
} > "$summary_file"

decision="$(team_review_decision "$summary_file")"
[[ -n "$decision" ]] || die "review did not include a valid Decision line: $summary_file"

case "$decision" in
  OK) next_status="review-ok" ;;
  FIX) next_status="review-fix" ;;
  ASK_LEAD) next_status="review-ask-lead" ;;
  *) die "invalid review decision: $decision" ;;
esac

team_write_task_state \
  "$task_id" \
  "$worker_id" \
  "$next_status" \
  "$base_commit" \
  "$head_commit" \
  "$(team_task_state_field "$task_id" integration_commit)" \
  "$report_file" \
  "$summary_file" \
  "$previous_integration" \
  "$decision"

message="Review Decision: $decision. $summary_file を読んでください。明確に有効な Critical/Major は修正し、修正後に make post-change と make smoke を再実行してください。判断に迷う指摘は lead に相談してください。"
"$SCRIPT_DIR/team_send.sh" --from verifier "$worker_id" review "$task_id" "$message" >/dev/null

echo "$summary_file"
