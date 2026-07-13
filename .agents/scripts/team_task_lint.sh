#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_task_lint.sh <task_id>" >&2
}

[[ $# -eq 1 ]] || { usage; exit 2; }

task_id="$1"
task_file="$TEAM_QUEUE_DIR/tasks/$task_id.md"

lane="normal"
case "$task_id" in
  T-E-*) lane="express" ;;
esac

ensure_team_dirs

[[ -f "$task_file" ]] || die_rule \
  "task file not found: $task_id" \
  "task lint validates a task contract before dispatch" \
  "create .agents/queue/tasks/$task_id.md first"

worker="$(team_task_markdown_field "$task_file" Worker || true)"
supervisor="$(team_task_markdown_field "$task_file" Supervisor || true)"
architecture_required="$(team_task_markdown_field "$task_file" "Architecture required" || true)"

[[ -n "$worker" ]] || die_rule \
  "task Worker is missing: $task_file" \
  "dispatch needs an explicit implementation worker" \
  "add 'Worker: <general-worker-id|hard-task-worker-id|frontend-worker-id>'"
if [[ "$lane" != "express" ]]; then
  grep -q '^Supervisor:' "$task_file" || die_rule \
    "task Supervisor field is missing: $task_file" \
    "dispatch records the fixed supervisor in the task contract" \
    "add an empty 'Supervisor:' field; dispatch will fill it"
fi
[[ -n "$architecture_required" ]] || die_rule \
  "task Architecture required is missing: $task_file" \
  "dispatch needs an exact architecture gate value" \
  "add 'Architecture required: true' or 'Architecture required: false'"

case "$architecture_required" in
  true|false) ;;
  *) die_rule \
    "invalid Architecture required value: $architecture_required" \
    "Architecture required is machine-read and accepts only true or false" \
    "move explanatory text elsewhere and set Architecture required to true or false" ;;
esac

if ! team_config_agent_record "$worker" >/dev/null; then
  die_rule \
    "task Worker is not configured: $worker" \
    "Worker must name an agent id from $TEAM_CONFIG_FILE" \
    "choose a configured general-worker, hard-task-worker, or frontend-worker id"
fi

worker_role="$(team_config_agent_field "$worker" role)"
if [[ "$lane" == "express" ]]; then
  [[ "$worker_role" == "express-worker" ]] || die_rule \
    "express task Worker is not an express worker: $worker" \
    "$worker has role $worker_role in $TEAM_CONFIG_FILE" \
    "set Worker to a configured express-worker id"
  [[ "$architecture_required" == "false" ]] || die_rule \
    "express task cannot require architecture: $task_id" \
    "architecture direction needs the normal lane with Manager and Supervisor" \
    "set Architecture required to false or create a normal task"
  [[ -z "$supervisor" ]] || die_rule \
    "express task cannot declare a supervisor: $task_id" \
    "express tasks are reviewed by Lead, not a fixed supervisor" \
    "remove the Supervisor field from the express task"
else
  case "$worker_role" in
    general-worker|hard-task-worker|frontend-worker) ;;
    *) die_rule \
      "task Worker is not an implementation worker: $worker" \
      "$worker has role $worker_role in $TEAM_CONFIG_FILE" \
      "choose an agent with role general-worker, hard-task-worker, or frontend-worker" ;;
  esac

  expected_supervisor="$(team_config_agent_field "$worker" supervisor)"
  [[ -n "$expected_supervisor" ]] || die_rule \
    "task Worker has no configured supervisor: $worker" \
    "implementation workers require a fixed supervisor pairing" \
    "add supervisor to the $worker record in $TEAM_CONFIG_FILE"
  if [[ -n "$supervisor" && "$supervisor" != "$expected_supervisor" ]]; then
    die_rule \
      "task Supervisor does not match the Worker pair" \
      "$worker is paired with $expected_supervisor, but the task names $supervisor" \
      "set Supervisor to $expected_supervisor or leave it empty before dispatch"
  fi
fi

if [[ "$worker_role" == "frontend-worker" ]]; then
  grep -q '^## View Direction$' "$task_file" || die_rule \
    "frontend task View Direction section is missing" \
    "frontend-critic decides whether direction critique is required before implementation" \
    "create the task from .agents/queue/tasks/FRONTEND_TEMPLATE.md"
  grep -q '^## Visual Verification$' "$task_file" || die_rule \
    "frontend task Visual Verification section is missing" \
    "frontend-worker and frontend-critic need a shared way to reproduce the target UI" \
    "create the task from .agents/queue/tasks/FRONTEND_TEMPLATE.md"
fi

allowed_paths=()
while IFS= read -r path; do
  allowed_paths+=("$path")
done < <(team_task_markdown_section_paths "$task_file" "Allowed paths")

protected_paths=()
while IFS= read -r path; do
  protected_paths+=("$path")
done < <(team_task_markdown_section_paths "$task_file" "Do not modify")

invalid_allowed="$(team_task_markdown_section_invalid_path_bullets "$task_file" "Allowed paths")"
invalid_protected="$(team_task_markdown_section_invalid_path_bullets "$task_file" "Do not modify")"

if [[ -n "$invalid_allowed" ]]; then
  first_invalid="$(printf '%s\n' "$invalid_allowed" | sed -n '1p')"
  invalid_line="${first_invalid%%:*}"
  invalid_bullet="${first_invalid#*:}"
  die_rule \
    "task Allowed paths has an unreadable path bullet" \
    "$task_file line $invalid_line starts with '$invalid_bullet', which is not a path" \
    "write path bullets as '- path/to/file optional note', '- src/**/*.py optional note', or '- \`path/to/file\` optional note'"
fi
if [[ -n "$invalid_protected" ]]; then
  first_invalid="$(printf '%s\n' "$invalid_protected" | sed -n '1p')"
  invalid_line="${first_invalid%%:*}"
  invalid_bullet="${first_invalid#*:}"
  die_rule \
    "task Do not modify has an unreadable path bullet" \
    "$task_file line $invalid_line starts with '$invalid_bullet', which is not a path" \
    "write path bullets as '- path/to/file optional note', '- src/**/*.py optional note', or '- \`path/to/file\` optional note'"
fi

[[ "${#allowed_paths[@]}" -gt 0 ]] || die_rule \
  "task Allowed paths is empty: $task_file" \
  "implementation ownership must be explicit before dispatch" \
  "add at least one path under ## Allowed paths"
[[ "${#protected_paths[@]}" -gt 0 ]] || die_rule \
  "task Do not modify is empty: $task_file" \
  "protected ownership must be explicit before dispatch" \
  "add at least .agents/state/STATE.md and .agents/state/MEMORY.md under ## Do not modify"

if [[ "$lane" == "express" ]]; then
  for allowed in "${allowed_paths[@]}"; do
    case "$allowed" in
      .agents|.agents/*|AGENTS.md|CLAUDE.md|Makefile|\**)
        die_rule \
          "express task cannot own a governance path: $allowed" \
          "express tasks skip Manager and Supervisor, so protocol, config, and harness paths stay out of scope" \
          "route this change through a normal task, or narrow the allowed path" ;;
    esac
  done
fi

for allowed in "${allowed_paths[@]}"; do
  allowed_real="$(team_resolve_existing_path "$allowed" || true)"
  if [[ -n "$allowed_real" ]]; then
    for protected in "${protected_paths[@]}"; do
      protected_real="$(team_resolve_existing_path "$protected" || true)"
      [[ -n "$protected_real" ]] || continue
      if [[ "$allowed_real" == "$protected_real" ]]; then
        die_rule \
          "task path ownership conflict: $allowed and $protected are the same file" \
          "one path is allowed while the same real file is protected" \
          "make the task contract name the real ownership boundary once"
      fi
    done
  fi

  for protected in "${protected_paths[@]}"; do
    if team_path_matches_contract_path "$allowed" "$protected" \
      || team_path_matches_contract_path "$protected" "$allowed"; then
      die_rule \
        "task path ownership patterns overlap: $allowed and $protected" \
        "Allowed paths and Do not modify both claim the same path boundary" \
        "rewrite the task contract with non-overlapping ownership paths before dispatch"
    fi
  done

  if git -C "$TEAM_ROOT" check-ignore -q "$allowed" 2>/dev/null; then
    warn "allowed path is ignored by git: $allowed"
  fi
done

printf 'task_lint=%s ok\n' "$task_id"
