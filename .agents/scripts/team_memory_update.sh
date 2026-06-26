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

check_memory_diff() {
  local memory_file="$1"
  local memory_rel

  git -C "$TEAM_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die_rule \
    "MEMORY update requires a git repository" \
    "memory edits are reviewed through git diff and whitespace checks" \
    "run this command from a repository initialized with git"

  memory_rel="$(team_relative_path "$memory_file")"
  git -C "$TEAM_ROOT" diff --check -- "$memory_rel" >/dev/null || die_rule \
    "MEMORY update failed whitespace check" \
    "$memory_rel contains trailing whitespace or blank lines at end of file" \
    "fix $memory_rel, then rerun make post-change"
}

print_without_trailing_blank_lines() {
  local file="$1"
  awk '
    NF {
      while (blank_count > 0) {
        print ""
        blank_count--
      }
      print
      next
    }
    {
      blank_count++
    }
  ' "$file"
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
    check_memory_diff "$memory_file"
    {
      printf '\n## Accepted Proposal %s\n\n' "$(team_now_utc)"
      print_without_trailing_blank_lines "$proposal_file"
    } >> "$memory_file"
    check_memory_diff "$memory_file"
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
