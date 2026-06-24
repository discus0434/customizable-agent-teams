#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

if [[ -n "${TEAM_AGENT_ID:-}" ]]; then
  [[ -n "${TEAM_AGENT_ROLE:-}" ]] || die "TEAM_AGENT_ROLE is missing"
  [[ -n "${TEAM_AGENT_CLI:-}" ]] || die "TEAM_AGENT_CLI is missing"
  [[ -n "${TEAM_AGENT_MODEL:-}" ]] || die "TEAM_AGENT_MODEL is missing"
  [[ -n "${TEAM_SESSION:-}" ]] || die "TEAM_SESSION is missing"

  printf 'agent_id=%s\n' "$TEAM_AGENT_ID"
  printf 'role=%s\n' "$TEAM_AGENT_ROLE"
  printf 'cli=%s\n' "$TEAM_AGENT_CLI"
  printf 'model=%s\n' "$TEAM_AGENT_MODEL"
  printf 'session=%s\n' "$TEAM_SESSION"
  printf 'team_root=%s\n' "$TEAM_ROOT"
  printf 'team_config_file=%s\n' "$TEAM_CONFIG_FILE"
  exit 0
fi

if [[ -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null 2>&1; then
  agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}')"
  role="$(tmux display-message -t "$TMUX_PANE" -p '#{@role}')"
  model="$(tmux display-message -t "$TMUX_PANE" -p '#{@model}')"
  [[ -n "$agent_id" ]] || die "tmux @agent_id is missing"
  [[ -n "$role" ]] || die "tmux @role is missing"
  [[ -n "$model" ]] || die "tmux @model is missing"

  printf 'agent_id=%s\n' "$agent_id"
  printf 'role=%s\n' "$role"
  printf 'model=%s\n' "$model"
  printf 'team_root=%s\n' "$TEAM_ROOT"
  printf 'team_config_file=%s\n' "$TEAM_CONFIG_FILE"
  exit 0
fi

die "agent identity is unavailable; start this process with make team-start"
