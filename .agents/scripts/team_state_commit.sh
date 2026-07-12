#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

usage() {
  echo "usage: team_state_commit.sh <bundle_id>" >&2
}

[[ $# -eq 1 ]] || { usage; exit 2; }

bundle_id="$1"
[[ -n "$bundle_id" && "$bundle_id" != */* ]] || die_rule \
  "invalid release bundle id: ${bundle_id:-empty}" \
  "completion state commits identify one shipped release" \
  "pass BUNDLE=<bundle_id> without path separators"

[[ -n "${TEAM_AGENT_ID+x}" && -n "$TEAM_AGENT_ID" ]] || die_rule \
  "completion state commit agent identity is unavailable" \
  "the completion state commit belongs to the release Manager" \
  "run make state-commit inside the Manager pane"

manager_id="$TEAM_AGENT_ID"
team_config_agent_record "$manager_id" >/dev/null || die "unknown agent: $manager_id"
manager_role="$(team_config_agent_field "$manager_id" role)"
[[ "$manager_role" == "manager" ]] || die_rule \
  "agent cannot commit completion state: $manager_id" \
  "$manager_id has role $manager_role" \
  "run make state-commit from the Manager pane"

ensure_team_dirs
release_state_file="$(team_release_state_file "$bundle_id")"
[[ -f "$release_state_file" ]] || die_rule \
  "release state not found: $bundle_id" \
  "completion state commits close an existing release" \
  "complete release review for $bundle_id before committing STATE"

release_manager="$(team_release_state_field "$bundle_id" manager)"
release_status="$(team_release_state_field "$bundle_id" status)"
release_decision="$(team_release_state_field "$bundle_id" decision)"
[[ "$release_manager" == "$manager_id" ]] || die_rule \
  "release is owned by another Manager: $bundle_id" \
  "release state assigns $release_manager, but this pane is $manager_id" \
  "run make state-commit from the $release_manager pane"
[[ "$release_status" == "ship" && "$release_decision" == "SHIP" ]] || die_rule \
  "release is not shipped: $bundle_id" \
  "status=$release_status decision=$release_decision" \
  "wait for Release Captain SHIP before closing completion state"

inbox_file="$TEAM_QUEUE_DIR/inbox/$manager_id.jsonl"
processed_dir="$TEAM_STATE_DIR/processed/$manager_id"
ack_ids=()
if [[ -f "$inbox_file" ]]; then
  while IFS= read -r line; do
    message_type="$(printf '%s\n' "$line" | extract_json_field type)"
    message_bundle="$(printf '%s\n' "$line" | extract_json_field bundle_id)"
    [[ "$message_type" == "completion_ack" && "$message_bundle" == "$bundle_id" ]] || continue

    message_id="$(printf '%s\n' "$line" | extract_json_field id)"
    [[ -n "$message_id" && ! -f "$processed_dir/$message_id" ]] && ack_ids+=("$message_id")
  done < "$inbox_file"
fi

case "${#ack_ids[@]}" in
  1) ack_id="${ack_ids[0]}" ;;
  0)
    die_rule \
      "completion acknowledgment is not pending: $bundle_id" \
      "Manager commits final STATE only after Lead reports completion to the human" \
      "ask Lead to send completion_ack for BUNDLE=$bundle_id, compress STATE, then rerun make state-commit"
    ;;
  *)
    die_rule \
      "multiple completion acknowledgments are pending: $bundle_id" \
      "one release completion must have one acknowledgment" \
      "resolve duplicate completion_ack messages before committing STATE"
    ;;
esac

state_file="$(team_state_file)"
state_rel="$(team_relative_path "$state_file")"
[[ -f "$state_file" ]] || die_rule \
  "STATE file not found: $state_rel" \
  "the completion state commit requires the shared current-state document" \
  "restore $state_rel before running make state-commit"
git -C "$TEAM_ROOT" ls-files --error-unmatch -- "$state_rel" >/dev/null 2>&1 || die_rule \
  "STATE file is not tracked: $state_rel" \
  "completion state must persist in Git" \
  "add $state_rel to the repository, then rerun make state-commit"

acquire_team_lock "git-commit"

other_paths=()
while IFS= read -r path; do
  [[ -n "$path" ]] && other_paths+=("$path")
done < <(team_git_changed_paths_except "$state_rel")
[[ "${#other_paths[@]}" -eq 0 ]] || die_rule \
  "completion state commit requires a clean repository outside $state_rel" \
  "these paths still differ from HEAD: $(printf '%s\n' "${other_paths[@]}" | paste -sd ',' - | sed 's/,/, /g')" \
  "finish and commit the owning work, then rerun make state-commit BUNDLE=$bundle_id"

state_changed="false"
git -C "$TEAM_ROOT" diff --quiet -- "$state_rel" || state_changed="true"
git -C "$TEAM_ROOT" diff --cached --quiet -- "$state_rel" || state_changed="true"
[[ "$state_changed" == "true" ]] || die_rule \
  "STATE has no completion update to commit: $bundle_id" \
  "$state_rel matches HEAD" \
  "compress STATE after completion_ack, then rerun make state-commit"

git -C "$TEAM_ROOT" add -A -- "$state_rel"
staged_paths="$(git -C "$TEAM_ROOT" diff --cached --name-only --)"
[[ "$staged_paths" == "$state_rel" ]] || die_rule \
  "Git index is not isolated to $state_rel" \
  "staged paths are: ${staged_paths:-none}" \
  "unstage unrelated paths, then rerun make state-commit BUNDLE=$bundle_id"

git -C "$TEAM_ROOT" commit \
  -m "Record $bundle_id completion state" \
  -m "Agent-State: $bundle_id"
commit="$(git -C "$TEAM_ROOT" rev-parse HEAD)"

remaining_changes="$(git -C "$TEAM_ROOT" status --short --untracked-files=all)"
[[ -z "$remaining_changes" ]] || die_rule \
  "repository is not clean after the completion state commit" \
  "$remaining_changes" \
  "resolve the listed changes before starting the next task"

team_mark_message_processed "$manager_id" "$ack_id"
release_team_lock

printf 'bundle=%s\n' "$bundle_id"
printf 'ack=%s\n' "$ack_id"
printf 'commit=%s\n' "$commit"
