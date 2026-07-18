#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_memory_update.sh list
  team_memory_update.sh append <proposal_file_or_basename>
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

resolve_proposal_file() {
  local proposal="$1"

  if [[ "$proposal" == */* ]]; then
    printf '%s\n' "$proposal"
  else
    printf '%s/%s\n' "$TEAM_QUEUE_DIR/memory_proposals" "$proposal"
  fi
}

extract_proposed_entry() {
  local proposal_file="$1"
  local output_file="$2"
  local entry_count
  local raw_file

  raw_file="$(mktemp "$TEAM_STATE_DIR/tmp/memory-entry-raw.XXXXXX")"

  awk '
    $0 == "## Proposed Entry" {
      in_entry = 1
      next
    }
    in_entry && /^## / {
      exit
    }
    in_entry {
      print
    }
  ' "$proposal_file" > "$raw_file"
  print_without_trailing_blank_lines "$raw_file" > "$output_file"
  rm -f "$raw_file"

  [[ -s "$output_file" ]] || die_rule \
    "memory proposal has no Proposed Entry" \
    "$proposal_file does not contain a filled ## Proposed Entry section" \
    "add exactly one MEMORY entry under ## Proposed Entry"

  entry_count="$(grep -Ec '^- M-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3} ' "$output_file" || true)"
  [[ "$entry_count" == "1" ]] || die_rule \
    "memory proposal must contain exactly one entry" \
    "$proposal_file has $entry_count MEMORY entry lines under ## Proposed Entry" \
    "keep one '- M-YYYY-MM-DD-NNN ...' entry in the proposal"
}

insert_active_entry() {
  local memory_file="$1"
  local entry_file="$2"
  local output_file="$3"

  grep -q '^## Active Entries$' "$memory_file" || die_rule \
    "MEMORY is missing Active Entries" \
    "$memory_file must have an ## Active Entries section" \
    "restore the MEMORY template before appending proposals"

  awk -v entry_file="$entry_file" '
    BEGIN {
      while ((getline line < entry_file) > 0) {
        entry = entry line "\n"
      }
      close(entry_file)
    }
    $0 == "## Active Entries" {
      print
      print ""
      printf "%s", entry
      inserted = 1
      next
    }
    {
      print
    }
    END {
      if (!inserted) {
        exit 42
      }
    }
  ' "$memory_file" > "$output_file"
}

command="${1:-}"

case "$command" in
  list)
    ensure_state_dirs
    find "$TEAM_QUEUE_DIR/memory_proposals" -maxdepth 1 -type f -name '*.md' | sort
    ;;
  append)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    ensure_state_dirs
    proposal_file="$(resolve_proposal_file "$2")"
    [[ -f "$proposal_file" ]] || die "proposal file not found: $proposal_file"
    memory_file="$(team_memory_file)"
    [[ -f "$memory_file" ]] || die "memory file not found: $memory_file"
    check_memory_diff "$memory_file"
    entry_file="$(mktemp "$TEAM_STATE_DIR/tmp/memory-entry.XXXXXX")"
    next_memory_file="$(mktemp "$TEAM_STATE_DIR/tmp/memory-next.XXXXXX")"
    extract_proposed_entry "$proposal_file" "$entry_file"
    entry_id="$(awk '/^- M-/ { print $2; exit }' "$entry_file")"
    if grep -Fq -- "$entry_id " "$memory_file"; then
      rm -f "$entry_file" "$next_memory_file"
      die_rule \
        "MEMORY entry already exists: $entry_id" \
        "$memory_file already contains an entry with this id" \
        "update the existing entry manually or choose a new MEMORY id"
    fi
    insert_active_entry "$memory_file" "$entry_file" "$next_memory_file"
    mv "$next_memory_file" "$memory_file"
    rm -f "$entry_file"
    check_memory_diff "$memory_file"
    rm -f "$proposal_file"
    echo "appended Proposed Entry to $memory_file"
    echo "removed proposal: $proposal_file"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
