#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"
source "$SCRIPT_DIR/team_config.sh"

lead_id=""
while IFS='|' read -r id role _cli _model _effort _window _supervisor; do
  [[ -n "$id" ]] || continue
  if [[ "$role" == "lead" ]]; then
    [[ -z "$lead_id" ]] || die "multiple lead agents configured in $TEAM_CONFIG_FILE"
    lead_id="$id"
  fi
done < <(team_config_agents)

[[ -n "$lead_id" ]] || die "no lead agent configured in $TEAM_CONFIG_FILE"

"$SCRIPT_DIR/team_start.sh" --restart --lead-only

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

prompt="$(cat <<PROMPT
bootstrapを開始してください。
role=lead、agent_id=${lead_id}としてAGENTS.mdに従ってください。
最初に、このpaneの人間へ何を作るかを一つ質問してください。
回答ごとに確定した内容を短く示し、次の質問を一つだけ選んでください。
初期化の要件が決まったら、Managerへintakeを送ってください。
PROMPT
)"

team_tmux_wait_for_ready "$pane" "$cli" 30
team_tmux_send_text "$pane" "$prompt"

echo "started bootstrap in tmux session: $session"
echo "attach with: make team-attach"
