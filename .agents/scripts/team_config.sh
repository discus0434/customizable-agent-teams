#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

team_config_name() {
  awk '/^  name:/ { sub(/^  name:[[:space:]]*/, ""); print; exit }' "$TEAM_CONFIG_FILE"
}

team_config_session() {
  awk '/^  session:/ { sub(/^  session:[[:space:]]*/, ""); print; exit }' "$TEAM_CONFIG_FILE"
}

team_config_agents() {
  awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function reset() {
      id = ""
      role = ""
      cli = ""
      model = ""
      effort = ""
      window = ""
      supervisor = ""
      mode = ""
    }
    function emit() {
      if (id != "") {
        print id "|" role "|" cli "|" model "|" effort "|" window "|" supervisor "|" mode
      }
    }
    function field_value(line) {
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", line)
      return trim(line)
    }
    BEGIN { in_agents = 0; reset() }
    /^agents:[[:space:]]*$/ {
      in_agents = 1
      next
    }
    in_agents && /^[^[:space:]]/ {
      emit()
      exit
    }
    in_agents && /^  - id:/ {
      emit()
      reset()
      id = field_value($0)
      next
    }
    in_agents && /^    role:/ { role = field_value($0); next }
    in_agents && /^    cli:/ { cli = field_value($0); next }
    in_agents && /^    model:/ { model = field_value($0); next }
    in_agents && /^    effort:/ { effort = field_value($0); next }
    in_agents && /^    window:/ { window = field_value($0); next }
    in_agents && /^    supervisor:/ { supervisor = field_value($0); next }
    in_agents && /^    mode:/ { mode = field_value($0); next }
    END { emit() }
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
    effort) index=5 ;;
    window) index=6 ;;
    supervisor) index=7 ;;
    mode) index=8 ;;
    *) die "unknown agent field: $field" ;;
  esac

  team_config_agent_record "$agent_id" | awk -F'|' -v pos="$index" '{ print $pos }'
}

team_config_role_agent_ids() {
  local role="$1"
  team_config_agents | awk -F'|' -v role="$role" '$2 == role { print $1 }'
}

team_config_agent_command() {
  local agent_id="$1"
  local role
  local cli
  local model
  local effort

  role="$(team_config_agent_field "$agent_id" role)"
  cli="$(team_config_agent_field "$agent_id" cli)"
  model="$(team_config_agent_field "$agent_id" model)"
  effort="$(team_config_agent_field "$agent_id" effort)"

  case "$cli" in
    claude)
      printf 'claude --dangerously-skip-permissions --model %s --effort %s' \
        "$(shell_quote "$model")" \
        "$(shell_quote "$effort")"
      ;;
    codex)
      printf 'codex --dangerously-bypass-approvals-and-sandbox --model %s -c %s' \
        "$(shell_quote "$model")" \
        "$(shell_quote "model_reasoning_effort=\"$effort\"")"
      if [[ "$role" == "research-worker" ]]; then
        printf ' --search'
      fi
      ;;
    *)
      die_rule \
        "unsupported agent CLI: $cli" \
        "$agent_id uses a CLI without a launcher definition" \
        "set cli to claude or codex in $TEAM_CONFIG_FILE"
      ;;
  esac
}

team_config_validate() {
  local name
  local session
  local agents
  local id
  local role
  local cli
  local model
  local effort
  local window
  local supervisor
  local supervisor_role
  local expected_supervisor_role

  name="$(team_config_name)"
  session="$(team_config_session)"
  agents="$(team_config_agents)"

  [[ -n "$name" ]] || die_rule \
    "team name is missing" \
    "$TEAM_CONFIG_FILE must define team.name" \
    "add '  name: <team-name>' under team"
  [[ -n "$session" ]] || die_rule \
    "tmux session is missing" \
    "$TEAM_CONFIG_FILE must define team.session" \
    "add '  session: <session-name>' under team"
  [[ -n "$agents" ]] || die_rule \
    "agent list is empty" \
    "$TEAM_CONFIG_FILE must define agents as a top-level list" \
    "add at least lead, manager, and implementation agents under agents"

  duplicate_id="$(printf '%s\n' "$agents" | awk -F'|' '{ count[$1]++ } END { for (value in count) if (count[value] > 1) { print value; exit } }')"
  [[ -z "$duplicate_id" ]] || die_rule \
    "duplicate agent id: $duplicate_id" \
    "agent ids are routing identities and must be unique" \
    "rename one of the duplicate agent records"
  duplicate_window="$(printf '%s\n' "$agents" | awk -F'|' '{ count[$6]++ } END { for (value in count) if (value != "" && count[value] > 1) { print value; exit } }')"
  [[ -z "$duplicate_window" ]] || die_rule \
    "duplicate agent window: $duplicate_window" \
    "each agent needs its own tmux window" \
    "give every agent a unique window value"
  duplicate_supervisor="$(printf '%s\n' "$agents" | awk -F'|' '$7 != "" { count[$7]++ } END { for (value in count) if (count[value] > 1) { print value; exit } }')"
  [[ -z "$duplicate_supervisor" ]] || die_rule \
    "supervisor is paired with multiple workers: $duplicate_supervisor" \
    "implementation supervision uses fixed one-to-one pairs" \
    "pair each implementation worker with a different supervisor"

  while IFS='|' read -r id role cli model effort window supervisor mode; do
    [[ -n "$id" ]] || continue
    [[ -n "$role" ]] || die_rule "agent role is missing: $id" "routing uses role as the source of truth" "add '    role: <role>'"
    case "$role" in
      lead|manager|strategist|architect|release-captain|general-reviewer|general-worker|hard-task-worker|research-worker|express-worker|frontend-worker|frontend-critic) ;;
      *) die_rule "unknown agent role: $role" "$id uses a role outside the team protocol" "use a role defined by .agents/docs/TEAM_PROTOCOL.md" ;;
    esac
    case "$cli" in
      claude|codex) ;;
      *) die_rule "unsupported agent CLI: ${cli:-missing}" "$id must use a launcher supported by the team" "set cli to claude or codex" ;;
    esac
    [[ -n "$model" ]] || die_rule "agent model is missing: $id" "the launcher requires an explicit model" "add '    model: <model>'"
    case "$effort" in
      low|medium|high|xhigh|max) ;;
      *) die_rule "invalid agent effort: ${effort:-missing}" "$id effort must be explicit" "set effort to low, medium, high, xhigh, or max" ;;
    esac
    case "$mode" in
      "") ;;
      exec)
        case "$role" in
          research-worker|express-worker) ;;
          *) die_rule \
            "agent cannot run in exec mode: $id" \
            "mode: exec is for on-demand roles, but $id has role $role" \
            "use exec mode only for research-worker and express-worker" ;;
        esac
        [[ "$cli" == "codex" ]] || die_rule \
          "exec mode requires the codex CLI: $id" \
          "on-demand agents run via codex exec" \
          "set cli to codex or remove mode: exec"
        ;;
      *) die_rule "invalid agent mode: $mode" "$id mode must be empty or exec" "remove the mode field or set it to exec" ;;
    esac
    if [[ "$mode" != "exec" ]]; then
      [[ -n "$window" ]] || die_rule "agent window is missing: $id" "each resident agent runs in a named tmux window" "add '    window: <window-name>'"
    fi

    expected_supervisor_role=""
    case "$role" in
      general-worker|hard-task-worker) expected_supervisor_role="general-reviewer" ;;
      frontend-worker) expected_supervisor_role="frontend-critic" ;;
    esac
    if [[ -n "$expected_supervisor_role" ]]; then
      [[ -n "$supervisor" ]] || die_rule \
        "implementation worker has no supervisor: $id" \
        "$role requires a fixed task-local supervisor" \
        "add '    supervisor: <${expected_supervisor_role}-id>'"
      team_config_agent_record "$supervisor" >/dev/null || die_rule \
        "unknown supervisor for $id: $supervisor" \
        "the paired supervisor must be another configured agent" \
        "add $supervisor to agents or correct the supervisor field"
      supervisor_role="$(team_config_agent_field "$supervisor" role)"
      [[ "$supervisor_role" == "$expected_supervisor_role" ]] || die_rule \
        "invalid supervisor role for $id" \
        "$supervisor has role $supervisor_role, but $role requires $expected_supervisor_role" \
        "pair $id with an agent whose role is $expected_supervisor_role"
    elif [[ -n "$supervisor" ]]; then
      die_rule \
        "agent cannot declare a supervisor: $id" \
        "only general-worker, hard-task-worker, and frontend-worker use fixed task supervision" \
        "remove the supervisor field from $id"
    fi
  done <<< "$agents"

  for singleton_role in lead manager strategist architect release-captain; do
    role_count="$(printf '%s\n' "$agents" | awk -F'|' -v role="$singleton_role" '$2 == role { count++ } END { print count + 0 }')"
    [[ "$role_count" -eq 1 ]] || die_rule \
      "role must have exactly one agent: $singleton_role" \
      "$TEAM_CONFIG_FILE currently defines $role_count" \
      "define exactly one $singleton_role agent"
  done

  for pool_role in general-worker hard-task-worker general-reviewer research-worker express-worker frontend-worker frontend-critic; do
    role_count="$(printf '%s\n' "$agents" | awk -F'|' -v role="$pool_role" '$2 == role { count++ } END { print count + 0 }')"
    [[ "$role_count" -gt 0 ]] || die_rule \
      "role has no configured agents: $pool_role" \
      "the team workflow requires this role" \
      "add at least one $pool_role agent"
  done

  while IFS= read -r supervisor_id; do
    [[ -n "$supervisor_id" ]] || continue
    reference_count="$(printf '%s\n' "$agents" | awk -F'|' -v supervisor="$supervisor_id" '$7 == supervisor { count++ } END { print count + 0 }')"
    [[ "$reference_count" -eq 1 ]] || die_rule \
      "implementation supervisor is not paired: $supervisor_id" \
      "every general-reviewer and frontend-critic must supervise exactly one fixed worker" \
      "set one worker supervisor field to $supervisor_id"
  done < <(printf '%s\n' "$agents" | awk -F'|' '$2 == "general-reviewer" || $2 == "frontend-critic" { print $1 }')
}

team_config_main() {
  local command="${1:-}"
  case "$command" in
    name) team_config_name ;;
    session) team_config_session ;;
    agents) team_config_agents ;;
    validate) team_config_validate ;;
    agent)
      [[ $# -eq 2 ]] || die "usage: team_config.sh agent <agent_id>"
      team_config_agent_record "$2"
      ;;
    field)
      [[ $# -eq 3 ]] || die "usage: team_config.sh field <agent_id> <field>"
      team_config_agent_field "$2" "$3"
      ;;
    command)
      [[ $# -eq 2 ]] || die "usage: team_config.sh command <agent_id>"
      team_config_agent_command "$2"
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
  team_config.sh validate
  team_config.sh agent <agent_id>
  team_config.sh field <agent_id> <field>
  team_config.sh command <agent_id>
  team_config.sh role <role>
USAGE
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  team_config_main "$@"
fi
