#!/usr/bin/env bash

set -euo pipefail

TEAM_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_ROOT="${TEAM_ROOT:-$(cd "$TEAM_COMMON_DIR/../.." && pwd)}"
TEAM_CONFIG_FILE="${TEAM_CONFIG_FILE:-$TEAM_ROOT/.agents/config/agent-team.yaml}"
TEAM_QUEUE_DIR="${TEAM_QUEUE_DIR:-$TEAM_ROOT/.agents/queue}"
TEAM_STATE_DIR="${TEAM_STATE_DIR:-$TEAM_QUEUE_DIR/state}"
TEAM_MEMORY_DIR="${TEAM_MEMORY_DIR:-$TEAM_ROOT/.agents/state}"

die() {
  echo "[team] ERROR: $*" >&2
  exit 1
}

die_rule() {
  local message="$1"
  local reason="$2"
  local required_action="$3"

  {
    printf 'error: %s\n' "$message"
    printf 'reason: %s\n' "$reason"
    printf 'required action: %s\n' "$required_action"
  } >&2
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
    sleep 0.5
  done
}

team_tmux_prepare_input() {
  local pane="$1"

  team_tmux_cancel_mode_if_needed "$pane"
  tmux send-keys -t "$pane" Escape
  sleep 0.2
  tmux send-keys -t "$pane" C-u
}

team_tmux_pane_exists() {
  local pane="$1"
  tmux display-message -p -t "$pane" '#{pane_id}' >/dev/null 2>&1
}

team_tmux_pane_in_session() {
  local pane="$1"
  local expected_session="$2"
  local actual_session

  actual_session="$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null || true)"
  [[ "$actual_session" == "$expected_session" ]]
}

team_tmux_require_pane() {
  local agent_id="$1"
  local pane="$2"
  local session="$3"
  local window="$4"

  if ! team_tmux_pane_in_session "$pane" "$session"; then
    die_rule \
      "tmux pane is not running for agent $agent_id" \
      "the configured window $window in session $session exited or could not be found" \
      "fix the agent command in $TEAM_CONFIG_FILE, then run make team-start again"
  fi
}

team_tmux_send_text() {
  local pane="$1"
  local text="$2"

  team_tmux_prepare_input "$pane"
  tmux send-keys -t "$pane" -l "$text"
  team_tmux_submit "$pane"
}

team_send_with_body_file() {
  local from="$1"
  local type="$2"
  local task_id="$3"
  local bundle_id="$4"
  local to="$5"
  local body="$6"
  local body_file
  local status

  ensure_team_dirs
  body_file="$(mktemp "$TEAM_STATE_DIR/tmp/message-body.XXXXXX")"
  printf '%s\n' "$body" > "$body_file"

  if "$TEAM_COMMON_DIR/team_send.sh" \
    --from "$from" \
    --type "$type" \
    --task "$task_id" \
    --bundle "$bundle_id" \
    --body-file "$body_file" \
    "$to"; then
    rm -f "$body_file"
    return 0
  else
    status=$?
    rm -f "$body_file"
    return "$status"
  fi
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
    "$TEAM_MEMORY_DIR" \
    "$TEAM_QUEUE_DIR/tasks" \
    "$TEAM_QUEUE_DIR/inbox" \
    "$TEAM_QUEUE_DIR/reports" \
    "$TEAM_QUEUE_DIR/reviews" \
    "$TEAM_QUEUE_DIR/strategy" \
    "$TEAM_QUEUE_DIR/architecture" \
    "$TEAM_QUEUE_DIR/releases" \
    "$TEAM_QUEUE_DIR/memory_proposals" \
    "$TEAM_QUEUE_DIR/skill_proposals" \
    "$TEAM_STATE_DIR/agents" \
    "$TEAM_STATE_DIR/locks" \
    "$TEAM_STATE_DIR/messages" \
    "$TEAM_STATE_DIR/processed" \
    "$TEAM_STATE_DIR/releases" \
    "$TEAM_STATE_DIR/tmp" \
    "$TEAM_STATE_DIR/tasks"
}

team_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

team_now_compact_utc() {
  date -u +"%Y%m%dT%H%M%SZ"
}

team_message_id() {
  printf 'msg_%s_%s_%s\n' "$(team_now_compact_utc)" "$$" "$RANDOM"
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

team_relative_path() {
  local path="$1"
  if [[ "$path" == "$TEAM_ROOT/"* ]]; then
    printf '%s\n' "${path#"$TEAM_ROOT/"}"
  else
    printf '%s\n' "$path"
  fi
}

team_sanitize_token() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g'
}

team_strategy_artifact_path() {
  local task_id="$1"
  local subtype="$2"
  local scope
  local timestamp

  if [[ -z "$task_id" || "$task_id" == "-" ]]; then
    scope="general"
  else
    scope="$task_id"
  fi
  scope="$(team_sanitize_token "$scope")"
  timestamp="$(team_now_compact_utc)"
  printf '.agents/queue/strategy/%s_%s_%s.md\n' "$scope" "$subtype" "$timestamp"
}

team_architecture_artifact_path() {
  local task_id="$1"
  local bundle_id="$2"
  local subtype="$3"
  local scope
  local timestamp

  if [[ -n "$task_id" && "$task_id" != "-" ]]; then
    scope="$task_id"
  elif [[ -n "$bundle_id" && "$bundle_id" != "-" ]]; then
    scope="release-$bundle_id"
  else
    scope="general"
  fi
  scope="$(team_sanitize_token "$scope")"
  timestamp="$(team_now_compact_utc)"
  printf '.agents/queue/architecture/%s_%s_%s.md\n' "$scope" "$subtype" "$timestamp"
}

team_release_bundle_file() {
  local bundle_id="$1"
  printf '%s/releases/%s.md\n' "$TEAM_QUEUE_DIR" "$bundle_id"
}

team_release_review_file() {
  local bundle_id="$1"
  printf '%s/releases/%s_review.md\n' "$TEAM_QUEUE_DIR" "$bundle_id"
}

team_placeholder_pattern() {
  printf '^<!--[[:space:]]*TEAM_PLACEHOLDER:[^>]*-->[[:space:]]*$\n'
}

team_file_has_placeholders() {
  local file="$1"
  grep -Eq "$(team_placeholder_pattern)" "$file"
}

team_require_no_placeholders() {
  local label="$1"
  local file="$2"

  if team_file_has_placeholders "$file"; then
    die_rule \
      "$label has unfilled sections" \
      "$file still contains structured placeholder comments" \
      "fill the placeholder sections in $file, remove the placeholder comments, then rerun the command"
  fi
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

team_mark_inbox_processed() {
  local agent_id="$1"
  local task_id="$2"
  local bundle_id="$3"
  shift 3

  local inbox_file="$TEAM_QUEUE_DIR/inbox/$agent_id.jsonl"
  local processed_dir="$TEAM_STATE_DIR/processed/$agent_id"
  local line message_id message_task message_bundle message_type wanted_type type_matches

  if [[ ( -z "$task_id" || "$task_id" == "-" ) && ( -z "$bundle_id" || "$bundle_id" == "-" ) && $# -eq 0 ]]; then
    return 0
  fi

  [[ -f "$inbox_file" ]] || return 0
  mkdir -p "$processed_dir"

  while IFS= read -r line; do
    message_id="$(printf '%s\n' "$line" | extract_json_field id)"
    [[ -n "$message_id" ]] || continue

    if [[ -n "$task_id" && "$task_id" != "-" ]]; then
      message_task="$(printf '%s\n' "$line" | extract_json_field task_id)"
      [[ "$message_task" == "$task_id" ]] || continue
    fi

    if [[ -n "$bundle_id" && "$bundle_id" != "-" ]]; then
      message_bundle="$(printf '%s\n' "$line" | extract_json_field bundle_id)"
      [[ "$message_bundle" == "$bundle_id" ]] || continue
    fi

    if [[ $# -gt 0 ]]; then
      message_type="$(printf '%s\n' "$line" | extract_json_field type)"
      type_matches=0
      for wanted_type in "$@"; do
        if [[ "$message_type" == "$wanted_type" ]]; then
          type_matches=1
          break
        fi
      done
      [[ "$type_matches" == "1" ]] || continue
    fi

    printf '%s\n' "$(team_now_utc)" > "$processed_dir/$message_id"
  done < "$inbox_file"
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

team_release_state_file() {
  local bundle_id="$1"
  printf '%s/releases/%s.json\n' "$TEAM_STATE_DIR" "$bundle_id"
}

team_release_state_field() {
  local bundle_id="$1"
  local field="$2"
  local state_file
  state_file="$(team_release_state_file "$bundle_id")"
  [[ -f "$state_file" ]] || return 0
  extract_json_field "$field" < "$state_file"
}

team_write_task_state() {
  local task_id="$1"
  local manager="$2"
  local owner="$3"
  local reviewer="$4"
  local status="$5"
  local base_commit="$6"
  local head_commit="$7"
  local report="$8"
  local review="$9"
  local review_decision="${10}"
  local done_recommendation="${11}"
  local architecture_required="${12}"
  local architecture="${13}"
  local release_bundle="${14}"
  local state_file
  local updated_at

  state_file="$(team_task_state_file "$task_id")"
  updated_at="$(team_now_utc)"
  mkdir -p "$(dirname "$state_file")"

  printf '{"task_id":"%s","manager":"%s","owner":"%s","reviewer":"%s","status":"%s","base_commit":"%s","head_commit":"%s","report":"%s","review":"%s","review_decision":"%s","done_recommendation":"%s","architecture_required":"%s","architecture":"%s","release_bundle":"%s","updated_at":"%s"}\n' \
    "$(json_string "$task_id")" \
    "$(json_string "$manager")" \
    "$(json_string "$owner")" \
    "$(json_string "$reviewer")" \
    "$(json_string "$status")" \
    "$(json_string "$base_commit")" \
    "$(json_string "$head_commit")" \
    "$(json_string "$report")" \
    "$(json_string "$review")" \
    "$(json_string "$review_decision")" \
    "$(json_string "$done_recommendation")" \
    "$(json_string "$architecture_required")" \
    "$(json_string "$architecture")" \
    "$(json_string "$release_bundle")" \
    "$updated_at" > "$state_file"
}

team_write_release_state() {
  local bundle_id="$1"
  local manager="$2"
  local release_captain="$3"
  local status="$4"
  local decision="$5"
  local bundle_artifact="$6"
  local review_artifact="$7"
  local tasks="$8"
  local state_file
  local updated_at

  state_file="$(team_release_state_file "$bundle_id")"
  updated_at="$(team_now_utc)"
  mkdir -p "$(dirname "$state_file")"

  printf '{"bundle_id":"%s","manager":"%s","release_captain":"%s","status":"%s","decision":"%s","bundle_artifact":"%s","review_artifact":"%s","tasks":"%s","updated_at":"%s"}\n' \
    "$(json_string "$bundle_id")" \
    "$(json_string "$manager")" \
    "$(json_string "$release_captain")" \
    "$(json_string "$status")" \
    "$(json_string "$decision")" \
    "$(json_string "$bundle_artifact")" \
    "$(json_string "$review_artifact")" \
    "$(json_string "$tasks")" \
    "$updated_at" > "$state_file"
}

team_require_release_task_ready() {
  local bundle_id="$1"
  local task_id="$2"
  local task_state_file
  local task_status
  local review_decision
  local done_recommendation
  local report_file
  local task_review_file
  local architecture_required
  local architecture

  task_state_file="$(team_task_state_file "$task_id")"
  [[ -f "$task_state_file" ]] || die_rule \
    "release task state is missing: $task_id" \
    "release review requires every included task to have current machine state" \
    "dispatch, review, and mark $task_id done before including it in $bundle_id"

  task_status="$(team_task_state_field "$task_id" status)"
  review_decision="$(team_task_state_field "$task_id" review_decision)"
  done_recommendation="$(team_task_state_field "$task_id" done_recommendation)"
  report_file="$(team_task_state_field "$task_id" report)"
  task_review_file="$(team_task_state_field "$task_id" review)"
  architecture_required="$(team_task_state_field "$task_id" architecture_required)"
  architecture="$(team_task_state_field "$task_id" architecture)"

  [[ "$task_status" == "done" ]] || die_rule \
    "release task is not done: $task_id" \
    "task state has status=$task_status, but release review requires status=done" \
    "manager must finish $task_id or remove it from release bundle $bundle_id"
  [[ "$review_decision" == "OK" ]] || die_rule \
    "release task review is not OK: $task_id" \
    "task state has review_decision=$review_decision, but release review requires review_decision=OK" \
    "reviewer must record OK before manager includes $task_id in release bundle $bundle_id"
  [[ "$done_recommendation" == "true" ]] || die_rule \
    "release task is not recommended done: $task_id" \
    "task state has done_recommendation=$done_recommendation, but release review requires done_recommendation=true" \
    "reviewer must recommend done before manager includes $task_id in release bundle $bundle_id"
  [[ -n "$report_file" && -f "$report_file" ]] || die_rule \
    "release task report is missing: $task_id" \
    "task state points to report=$report_file" \
    "worker must write the report before $task_id is included in release bundle $bundle_id"
  [[ -n "$task_review_file" && -f "$task_review_file" ]] || die_rule \
    "release task review artifact is missing: $task_id" \
    "task state points to review=$task_review_file" \
    "reviewer must write the review artifact before $task_id is included in release bundle $bundle_id"

  if [[ "$architecture_required" == "true" ]]; then
    [[ -n "$architecture" && -f "$TEAM_ROOT/$architecture" ]] || die_rule \
      "release task architecture note is missing: $task_id" \
      "task state has architecture_required=true and architecture=$architecture" \
      "architect must write the recorded architecture note before release review"
  fi
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

team_require_report_field() {
  local report_file="$1"
  local field="$2"
  local expected="$3"
  local actual

  actual="$(team_report_field "$report_file" "$field" || true)"
  [[ "$actual" == "$expected" ]] || die_rule \
    "report field mismatch: $field" \
    "$report_file has '$field: ${actual:-missing}', but task state requires '$field: $expected'" \
    "run make report for the task again, then preserve the generated $field value when filling evidence"
}

team_require_report_matches_task_state() {
  local task_id="$1"
  local report_file="$2"
  local base_commit="$3"
  local head_commit="$4"

  [[ -n "$report_file" && -f "$report_file" ]] || die_rule \
    "report file not found for $task_id" \
    "task state points to a report that does not exist" \
    "worker must run make report TASK=$task_id AGENT=<worker_id> STATUS=needs_review"
  team_require_report_field "$report_file" "Base commit" "$base_commit"
  team_require_report_field "$report_file" "Head commit" "$head_commit"
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
    /^Decision:[[:space:]]*(OK|FIX|ASK_MANAGER)[[:space:]]*$/ {
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

team_state_file() {
  printf '%s/STATE.md\n' "$TEAM_MEMORY_DIR"
}

team_memory_file() {
  printf '%s/MEMORY.md\n' "$TEAM_MEMORY_DIR"
}
