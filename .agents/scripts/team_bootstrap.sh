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

prompt="$(cat <<PROMPT
bootstrapを開始してください。
role=lead、agent_id=${lead_id}としてAGENTS.mdに従ってください。
最初に、このpaneの人間へ何を作るかを一つ質問してください。
回答ごとに確定した内容を短く示し、次の質問を一つだけ選んでください。
初期化の要件が決まったら、Managerへintakeを送ってください。
PROMPT
)"

"$SCRIPT_DIR/team_start.sh" --restart --lead-only --prompt "$prompt"

echo "started bootstrap"
