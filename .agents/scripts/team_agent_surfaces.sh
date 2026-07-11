#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

ensure_team_dirs

printf 'Repository: %s\n' "$TEAM_ROOT"
printf 'HEAD: '
git -C "$TEAM_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'none\n'
printf '\n'

printf 'Tracked symlinks:\n'
symlink_count=0
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  symlink_count=$((symlink_count + 1))
  target="$(git -C "$TEAM_ROOT" show "HEAD:$path" 2>/dev/null || readlink "$TEAM_ROOT/$path")"
  resolved="$(team_resolve_existing_path "$path" || true)"
  if [[ -n "$resolved" ]]; then
    printf '  %s -> %s (real: %s)\n' "$path" "$target" "$(team_relative_path "$resolved")"
  else
    printf '  %s -> %s (dangling)\n' "$path" "$target"
  fi
done < <(git -C "$TEAM_ROOT" ls-files -s | awk '$1 == 120000 { print $4 }' | sort)
[[ "$symlink_count" -gt 0 ]] || printf '  none\n'
printf '\n'

printf 'Agent surfaces:\n'
for path in AGENTS.md CLAUDE.md .agents/skills .codex/skills .claude/skills; do
  if [[ -L "$TEAM_ROOT/$path" ]]; then
    printf '  %s -> %s\n' "$path" "$(readlink "$TEAM_ROOT/$path")"
  elif [[ -e "$TEAM_ROOT/$path" ]]; then
    printf '  %s\n' "$path"
  else
    printf '  %s missing\n' "$path"
  fi
done
