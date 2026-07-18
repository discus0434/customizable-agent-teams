#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

main() {
  ensure_state_dirs

  managers="$(team_config_role_agent_ids manager)"
  manager_count="$(printf '%s\n' "$managers" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$manager_count" -gt 0 ]] || die_rule \
    "manager is not configured" \
    "bootstrap team startup needs a manager to receive the lead intake" \
    "add a manager agent to $TEAM_CONFIG_FILE"

  "$SCRIPT_DIR/team_start.sh" --complete-existing
}

main "$@"
