#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_memory_update.sh list
  team_memory_update.sh append <proposal_file>
USAGE
}

command="${1:-}"

case "$command" in
  list)
    ensure_team_dirs
    find "$TEAM_QUEUE_DIR/memory_proposals" -maxdepth 1 -type f -name '*.md' | sort
    ;;
  append)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    proposal_file="$2"
    [[ -f "$proposal_file" ]] || die "proposal file not found: $proposal_file"
    memory_file="$(team_memory_file)"
    [[ -f "$memory_file" ]] || die "memory file not found: $memory_file"
    {
      printf '\n## Accepted Proposal %s\n\n' "$(team_now_utc)"
      cat "$proposal_file"
      printf '\n'
    } >> "$memory_file"
    echo "appended proposal to $memory_file"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
