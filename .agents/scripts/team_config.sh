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
    function singular_role(section_name) {
      if (section_name == "reviewers") return "reviewer"
      if (section_name == "workers") return "worker"
      return section_name
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
          role = singular_role(section)
        }
        print id "|" role "|" cli "|" model "|" window "|" command
      }
    }
    function known_section(name) {
      return name == "lead" || name == "manager" || name == "strategist" || name == "reviewers" || name == "workers"
    }
    BEGIN {
      section = ""
      list_section = 0
      reset("")
    }
    /^  [A-Za-z0-9_-]+:/ {
      value = $0
      sub(/^  /, "", value)
      sub(/:.*/, "", value)
      emit()
      if (known_section(value)) {
        section = value
        list_section = (section == "reviewers" || section == "workers")
        reset(singular_role(section))
      } else {
        section = "ignore"
        list_section = 0
        reset("")
      }
      next
    }
    section == "ignore" {
      next
    }
    list_section && /^    - id:/ {
      emit()
      reset(singular_role(section))
      value = $0
      sub(/^    - id:[[:space:]]*/, "", value)
      id = trim(value)
      next
    }
    !list_section && section != "" && /^[[:space:]]+id:/ {
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

team_config_role_agent_ids() {
  local role="$1"
  team_config_agents | awk -F'|' -v role="$role" '$2 == role { print $1 }'
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
    role)
      [[ $# -eq 2 ]] || die "usage: team_config.sh role <role>"
      team_config_role_agent_ids "$2"
      ;;
    *)
      cat <<'USAGE'
usage:
  team_config.sh name
  team_config.sh session
  team_config.sh agents
  team_config.sh agent <agent_id>
  team_config.sh field <agent_id> <field>
  team_config.sh role <role>
USAGE
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  team_config_main "$@"
fi
