#!/usr/bin/env bash

set -euo pipefail

TEAM_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_ROOT="${TEAM_ROOT:-$(cd "$TEAM_COMMON_DIR/../.." && pwd)}"
TEAM_CONFIG_FILE="${TEAM_CONFIG_FILE:-$TEAM_ROOT/.agents/config/agent-team.yaml}"
TEAM_QUEUE_DIR="${TEAM_QUEUE_DIR:-$TEAM_ROOT/.agents/queue}"
TEAM_STATE_DIR="${TEAM_STATE_DIR:-$TEAM_QUEUE_DIR/state}"

die() {
  echo "[team] ERROR: $*" >&2
  exit 1
}

warn() {
  echo "[team] WARN: $*" >&2
}

require_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi
  die "required command not found: $name"
}

team_tmux_capture_pane() {
  local pane="$1"
  tmux capture-pane -t "$pane" -p -S -80
}

team_tmux_cancel_mode_if_needed() {
  local pane="$1"
  local pane_in_mode

  pane_in_mode="$(tmux display-message -p -t "$pane" '#{pane_in_mode}')"
  if [[ "$pane_in_mode" == "1" ]]; then
    tmux send-keys -t "$pane" -X cancel
  fi
}

team_tmux_submit() {
  local pane="$1"
  local count="${2:-3}"
  local _index

  for _index in $(seq 1 "$count"); do
    tmux send-keys -t "$pane" C-m
    sleep 0.2
  done
}

team_tmux_send_text() {
  local pane="$1"
  local text="$2"

  team_tmux_cancel_mode_if_needed "$pane"
  tmux send-keys -t "$pane" C-u
  tmux send-keys -t "$pane" -l "$text"
  team_tmux_submit "$pane"
}

team_tmux_content_is_ready() {
  local content="$1"
  local cli="$2"
  local pattern

  case "$cli" in
    claude)
      pattern='Claude Code|Try "edit|bypass permissions'
      ;;
    codex)
      pattern='Codex|What can I help|Ask for'
      ;;
    *)
      pattern='Claude Code|Try "edit|bypass permissions|Codex|What can I help|Ask for'
      ;;
  esac

  printf '%s\n' "$content" | grep -Eq "$pattern"
}

team_tmux_accept_startup_prompt() {
  local pane="$1"
  local cli="$2"
  local timeout_seconds="$3"
  local content
  local _attempt

  for _attempt in $(seq 1 "$timeout_seconds"); do
    content="$(team_tmux_capture_pane "$pane")"
    if printf '%s\n' "$content" | grep -Eq 'Do you trust the contents of this directory|Press enter to continue|Quick safety check: Is this a project you created or one you trust|Enter to confirm'; then
      team_tmux_cancel_mode_if_needed "$pane"
      team_tmux_submit "$pane"
      sleep 1
      return 0
    fi
    if team_tmux_content_is_ready "$content" "$cli"; then
      return 0
    fi
    sleep 1
  done
}

team_tmux_wait_for_ready() {
  local pane="$1"
  local cli="$2"
  local timeout_seconds="$3"
  local content
  local _attempt

  for _attempt in $(seq 1 "$timeout_seconds"); do
    content="$(team_tmux_capture_pane "$pane")"
    if team_tmux_content_is_ready "$content" "$cli"; then
      return 0
    fi
    sleep 1
  done

  die "tmux pane did not become ready for input: $pane"
}

ensure_team_dirs() {
  mkdir -p \
    "$TEAM_QUEUE_DIR/tasks" \
    "$TEAM_QUEUE_DIR/inbox" \
    "$TEAM_QUEUE_DIR/reports" \
    "$TEAM_QUEUE_DIR/reviews" \
    "$TEAM_QUEUE_DIR/integrations" \
    "$TEAM_QUEUE_DIR/memory_proposals" \
    "$TEAM_STATE_DIR/agents" \
    "$TEAM_STATE_DIR/integrations" \
    "$TEAM_STATE_DIR/locks" \
    "$TEAM_STATE_DIR/messages" \
    "$TEAM_STATE_DIR/processed" \
    "$TEAM_STATE_DIR/tmp" \
    "$TEAM_STATE_DIR/tasks"
}

team_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

team_message_id() {
  date -u +"msg_%Y%m%dT%H%M%SZ_$$"
}

json_escape() {
  awk 'BEGIN { ORS = "" }
    {
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      gsub(/\r/, "\\r")
      gsub(/\t/, "\\t")
      if (NR > 1) {
        printf "\\n"
      }
      printf "%s", $0
    }'
}

json_string() {
  printf '%s' "$1" | json_escape
}

shell_quote() {
  printf '%q' "$1"
}

team_root_name() {
  basename "$TEAM_ROOT"
}

team_expand_path() {
  local path="$1"
  local root_name

  root_name="$(team_root_name)"
  path="${path//\{team_root\}/$root_name}"
  printf '%s\n' "$path"
}

abs_path() {
  local path

  path="$(team_expand_path "$1")"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$TEAM_ROOT/$path"
  fi
}

TEAM_LOCK_DIR=""

acquire_team_lock() {
  local name="$1"
  ensure_team_dirs
  TEAM_LOCK_DIR="$TEAM_STATE_DIR/locks/$name.lock"

  local attempt
  for attempt in $(seq 1 100); do
    if mkdir "$TEAM_LOCK_DIR" 2>/dev/null; then
      trap 'release_team_lock' EXIT INT TERM
      return 0
    fi
    sleep 0.1
  done

  die "could not acquire lock: $name"
}

release_team_lock() {
  if [[ -n "${TEAM_LOCK_DIR:-}" && -d "$TEAM_LOCK_DIR" ]]; then
    rmdir "$TEAM_LOCK_DIR"
    TEAM_LOCK_DIR=""
  fi
  trap - EXIT INT TERM
}

extract_json_field() {
  local field="$1"
  sed -n "s/.*\"$field\":\"\\([^\"]*\\)\".*/\\1/p"
}

team_task_state_file() {
  local task_id="$1"
  printf '%s/tasks/%s.json\n' "$TEAM_STATE_DIR" "$task_id"
}

team_task_state_field() {
  local task_id="$1"
  local field="$2"
  local state_file
  state_file="$(team_task_state_file "$task_id")"
  [[ -f "$state_file" ]] || return 0
  extract_json_field "$field" < "$state_file"
}

team_write_task_state() {
  local task_id="$1"
  local owner="$2"
  local status="$3"
  local base_commit="$4"
  local head_commit="$5"
  local integration_commit="$6"
  local report="$7"
  local review="$8"
  local integration="$9"
  local review_decision="${10}"
  local state_file
  local updated_at

  state_file="$(team_task_state_file "$task_id")"
  updated_at="$(team_now_utc)"
  mkdir -p "$(dirname "$state_file")"

  printf '{"task_id":"%s","owner":"%s","status":"%s","base_commit":"%s","head_commit":"%s","integration_commit":"%s","report":"%s","review":"%s","integration":"%s","review_decision":"%s","updated_at":"%s"}\n' \
    "$(json_string "$task_id")" \
    "$(json_string "$owner")" \
    "$(json_string "$status")" \
    "$(json_string "$base_commit")" \
    "$(json_string "$head_commit")" \
    "$(json_string "$integration_commit")" \
    "$(json_string "$report")" \
    "$(json_string "$review")" \
    "$(json_string "$integration")" \
    "$(json_string "$review_decision")" \
    "$updated_at" > "$state_file"
}

team_task_markdown_field() {
  local task_file="$1"
  local field="$2"
  awk -v field="$field" '
    index($0, field ":") == 1 {
      value = $0
      sub("^[^:]+:[[:space:]]*", "", value)
      print value
      found = 1
      exit
    }
    END {
      exit found ? 0 : 1
    }
  ' "$task_file"
}

team_git_is_clean() {
  local repo="$1"
  git -C "$repo" diff --quiet -- .
  git -C "$repo" diff --cached --quiet -- .
  [[ -z "$(git -C "$repo" ls-files --others --exclude-standard)" ]]
}

team_git_dirty_summary() {
  local repo="$1"
  git -C "$repo" status --short
}

team_report_field() {
  local report_file="$1"
  local field="$2"
  [[ -f "$report_file" ]] || return 0
  awk -v field="$field" '
    index($0, field ":") == 1 {
      value = $0
      sub("^[^:]+:[[:space:]]*", "", value)
      print value
      found = 1
      exit
    }
    END {
      exit found ? 0 : 1
    }
  ' "$report_file"
}

team_update_markdown_field() {
  local file="$1"
  local field="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"
  awk -v field="$field" -v value="$value" '
    BEGIN {
      prefix = field ":"
      replacement = field ": " value
      done = 0
    }
    index($0, prefix) == 1 {
      print replacement
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print replacement
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

team_review_decision() {
  local review_file="$1"
  [[ -f "$review_file" ]] || return 0
  awk '
    /^Decision:[[:space:]]*(OK|FIX|ASK_LEAD)[[:space:]]*$/ {
      value = $0
      sub(/^Decision:[[:space:]]*/, "", value)
      print value
      found = 1
      exit
    }
    END {
      exit found ? 0 : 1
    }
  ' "$review_file"
}
