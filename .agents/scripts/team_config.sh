#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

team_config_name() {
  awk '/^  name:/ { print $2; exit }' "$TEAM_CONFIG_FILE"
}

team_config_session() {
  awk '/^  session:/ { print $2; exit }' "$TEAM_CONFIG_FILE"
}

team_config_agents() {
  awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function reset(next_role) {
      id = ""
      role = next_role
      cli = ""
      model = ""
      window = ""
      command = ""
    }
    function emit() {
      if (id != "") {
        if (role == "") {
          role = "worker"
        }
        print id "|" role "|" cli "|" model "|" window "|" command
      }
    }
    BEGIN {
      section = ""
      reset("")
    }
    /^  lead:/ {
      emit()
      section = "lead"
      reset("lead")
      next
    }
    /^  workers:/ {
      emit()
      section = "workers"
      reset("worker")
      next
    }
    /^  review:/ {
      emit()
      section = "review"
      reset("")
      next
    }
    /^  [A-Za-z0-9_-]+:/ {
      emit()
      section = "ignore"
      reset("")
      next
    }
    section == "review" {
      next
    }
    section == "ignore" {
      next
    }
    section == "workers" && /^    - id:/ {
      emit()
      reset("worker")
      value = $0
      sub(/^    - id:[[:space:]]*/, "", value)
      id = trim(value)
      next
    }
    section != "workers" && section != "" && /^[[:space:]]+id:/ {
      value = $0
      sub(/^[[:space:]]+id:[[:space:]]*/, "", value)
      id = trim(value)
      next
    }
    section != "" && /^[[:space:]]+role:/ {
      value = $0
      sub(/^[[:space:]]+role:[[:space:]]*/, "", value)
      role = trim(value)
      next
    }
    section != "" && /^[[:space:]]+cli:/ {
      value = $0
      sub(/^[[:space:]]+cli:[[:space:]]*/, "", value)
      cli = trim(value)
      next
    }
    section != "" && /^[[:space:]]+model:/ {
      value = $0
      sub(/^[[:space:]]+model:[[:space:]]*/, "", value)
      model = trim(value)
      next
    }
    section != "" && /^[[:space:]]+window:/ {
      value = $0
      sub(/^[[:space:]]+window:[[:space:]]*/, "", value)
      window = trim(value)
      next
    }
    section != "" && /^[[:space:]]+command:/ {
      value = $0
      sub(/^[[:space:]]+command:[[:space:]]*/, "", value)
      command = trim(value)
      next
    }
    END {
      emit()
    }
  ' "$TEAM_CONFIG_FILE"
}

team_config_agent_record() {
  local agent_id="$1"
  team_config_agents | awk -F'|' -v agent_id="$agent_id" '$1 == agent_id { print; found = 1 } END { exit found ? 0 : 1 }'
}

team_config_agent_field() {
  local agent_id="$1"
  local field="$2"
  local index

  case "$field" in
    id) index=1 ;;
    role) index=2 ;;
    cli) index=3 ;;
    model) index=4 ;;
    window) index=5 ;;
    command) index=6 ;;
    *) die "unknown agent field: $field" ;;
  esac

  team_config_agent_record "$agent_id" | awk -F'|' -v index="$index" '{ print $index }'
}

team_config_review_field() {
  local field="$1"
  awk -v want="$field" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    /^  review:/ {
      in_review = 1
      next
    }
    /^  [A-Za-z0-9_-]+:/ && $0 !~ /^  review:/ {
      in_review = 0
    }
    in_review && $0 ~ "^[[:space:]]+" want ":" {
      value = $0
      sub("^[[:space:]]+" want ":[[:space:]]*", "", value)
      print trim(value)
      found = 1
      exit
    }
    END {
      exit found ? 0 : 1
    }
  ' "$TEAM_CONFIG_FILE"
}

team_config_main() {
  local command="${1:-}"
  case "$command" in
    name)
      team_config_name
      ;;
    session)
      team_config_session
      ;;
    agents)
      team_config_agents
      ;;
    agent)
      [[ $# -eq 2 ]] || die "usage: team_config.sh agent <agent_id>"
      team_config_agent_record "$2"
      ;;
    field)
      [[ $# -eq 3 ]] || die "usage: team_config.sh field <agent_id> <field>"
      team_config_agent_field "$2" "$3"
      ;;
    review-field)
      [[ $# -eq 2 ]] || die "usage: team_config.sh review-field <field>"
      team_config_review_field "$2"
      ;;
    *)
      cat <<'USAGE'
usage:
  team_config.sh name
  team_config.sh session
  team_config.sh agents
  team_config.sh agent <agent_id>
  team_config.sh field <agent_id> <field>
  team_config.sh review-field <field>
USAGE
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  team_config_main "$@"
fi
