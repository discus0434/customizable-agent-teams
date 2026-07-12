#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_task_commit.sh <task_id> <summary>" >&2
}

[[ $# -eq 2 ]] || { usage; exit 2; }

task_id="$1"
summary="$2"

[[ -n "$summary" && "$summary" != *$'\n'* ]] || die_rule \
  "task commit summary must be one non-empty line" \
  "the summary becomes the Git commit subject" \
  "pass MESSAGE='<concise summary>'"
[[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
  "task commit agent identity is unavailable" \
  "implementation commits belong to the assigned worker pane" \
  "run make task-commit inside the assigned worker pane"

agent_id="$TEAM_AGENT_ID"
team_config_agent_record "$agent_id" >/dev/null || die "unknown agent: $agent_id"
agent_role="$(team_config_agent_field "$agent_id" role)"
case "$agent_role" in
  general-worker|hard-task-worker|frontend-worker) ;;
  *) die_rule \
    "agent cannot create implementation task commits: $agent_id" \
    "$agent_id has role $agent_role" \
    "run the command from the assigned implementation worker pane" ;;
esac

ensure_team_dirs
task_file="$TEAM_QUEUE_DIR/tasks/$task_id.md"
state_file="$(team_task_state_file "$task_id")"
[[ -f "$task_file" && -f "$state_file" ]] || die_rule \
  "task is not dispatched: $task_id" \
  "task commits require an existing task contract and machine state" \
  "ask Manager to dispatch $task_id before committing"

worker="$(team_task_state_field "$task_id" worker)"
status="$(team_task_state_field "$task_id" status)"
[[ "$worker" == "$agent_id" ]] || die_rule \
  "task is assigned to another worker: $task_id" \
  "task state assigns $worker, but this pane is $agent_id" \
  "commit from the $worker pane"
case "$status" in
  dispatched|needs_supervision|supervision_fix|manager_fix) ;;
  *) die_rule \
    "task does not accept implementation commits: $task_id" \
    "task status is $status" \
    "resolve the current supervision or Manager decision before committing" ;;
esac

"$SCRIPT_DIR/team_task_lint.sh" "$task_id" >/dev/null
acquire_team_lock "git-commit"

task_paths_file="$(mktemp)"
if ! team_task_changed_allowed_paths "$task_id" > "$task_paths_file"; then
  rm -f "$task_paths_file"
  exit 1
fi
task_paths=()
while IFS= read -r path; do
  [[ -n "$path" ]] && task_paths+=("$path")
done < "$task_paths_file"
rm -f "$task_paths_file"

[[ "${#task_paths[@]}" -gt 0 ]] || die_rule \
  "task has no changed files to commit: $task_id" \
  "no current change matches the task Allowed paths" \
  "implement the task or correct its Allowed paths before committing"

unowned_staged_paths=()
while IFS= read -r staged_path; do
  [[ -n "$staged_path" ]] || continue
  staged_path_is_owned="false"
  for task_path in "${task_paths[@]}"; do
    if [[ "$staged_path" == "$task_path" ]]; then
      staged_path_is_owned="true"
      break
    fi
  done
  [[ "$staged_path_is_owned" == "true" ]] || unowned_staged_paths+=("$staged_path")
done < <(git -C "$TEAM_ROOT" diff --cached --name-only --)

[[ "${#unowned_staged_paths[@]}" -eq 0 ]] || die_rule \
  "Git index contains changes outside task $task_id" \
  "task commit cannot include staged paths owned elsewhere: $(printf '%s\n' "${unowned_staged_paths[@]}" | paste -sd ',' - | sed 's/,/, /g')" \
  "finish or unstage those paths, then rerun make task-commit"

git -C "$TEAM_ROOT" add -A -- "${task_paths[@]}"
git -C "$TEAM_ROOT" diff --cached --quiet -- && die_rule \
  "task has no staged content after path selection: $task_id" \
  "the selected paths no longer differ from HEAD" \
  "inspect the current changes and rerun the command when task work is ready"

git -C "$TEAM_ROOT" commit \
  -m "$task_id: $summary" \
  -m "Agent-Task: $task_id"
commit="$(git -C "$TEAM_ROOT" rev-parse HEAD)"
release_team_lock

printf 'task=%s\n' "$task_id"
printf 'commit=%s\n' "$commit"
