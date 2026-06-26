#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

lead_id=""
while IFS='|' read -r id role _cli _model _window _command; do
  [[ -n "$id" ]] || continue
  if [[ "$role" == "lead" ]]; then
    [[ -z "$lead_id" ]] || die "multiple lead agents configured in $TEAM_CONFIG_FILE"
    lead_id="$id"
  fi
done < <(team_config_agents)

[[ -n "$lead_id" ]] || die "no lead agent configured in $TEAM_CONFIG_FILE"

TEAM_BOOT_NUDGE=0 "$SCRIPT_DIR/team_start.sh" --restart --lead-only

state_file="$TEAM_STATE_DIR/agents/$lead_id.env"
[[ -f "$state_file" ]] || die "no pane state for lead agent: $lead_id"

# shellcheck disable=SC1090
source "$state_file"

if [[ -z "${pane:-}" || -z "${session:-}" || -z "${cli:-}" ]]; then
  die "pane state for lead agent is incomplete: $lead_id"
fi

require_command tmux

if ! tmux has-session -t "$session" 2>/dev/null; then
  die "tmux session is not running: $session"
fi

prompt="bootstrap を開始してください。role=lead agent_id=$lead_id として AGENTS.md に従い、project code の編集や dispatch は行わないでください。一度に質問を並べず、まずこの pane のユーザーに「何を作るか」を1問だけ聞いてください。回答ごとに分かったことを短く反映し、次に必要な1問だけを選んで、協調しながら project shape、stack、entrypoint、make smoke を狭めてください。実装が必要になったら manager に依頼する前提で進めてください。"

team_tmux_wait_for_ready "$pane" "$cli" 30
team_tmux_send_text "$pane" "$prompt"

echo "started bootstrap in tmux session: $session"
echo "attach with: make team-attach"
