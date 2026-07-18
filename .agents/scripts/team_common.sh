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

team_tmux_pane_is_busy() {
  local pane="$1"

  team_tmux_capture_pane "$pane" | tail -n 20 | grep -Fq 'esc to interrupt'
}

team_tmux_input_is_pending() {
  local pane="$1"
  local cli="$2"
  local input_line
  local content

  # 人間が入力するpaneはclaudeのLeadだけという設計を前提に、
  # placeholderの語彙が固定できないcodex paneは判定しない。
  [[ "$cli" == "claude" ]] || return 1

  input_line="$(team_tmux_capture_pane "$pane" | grep -E '^❯ ' | tail -n 1)"
  content="${input_line#❯ }"
  content="${content#"${content%%[![:space:]]*}"}"
  [[ -n "$content" ]] || return 1
  case "$content" in
    'Try "'*) return 1 ;;
  esac
  return 0
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

  tmux send-keys -t "$pane" C-m
}

team_tmux_prepare_input() {
  local pane="$1"

  team_tmux_cancel_mode_if_needed "$pane"
  tmux send-keys -t "$pane" Escape
  sleep 0.2
  tmux send-keys -t "$pane" C-u
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

# paneのcomposer(最後の入力行)を返す。claudeは「❯ 」、codexは「› 」で始まる。
# composer行が無いpaneでは空を返す(呼び出し側はset -eなので失敗にしない)
team_tmux_composer_line() {
  local pane="$1"
  team_tmux_capture_pane "$pane" | grep -E '^(❯|›) ' | tail -n 1 || true
}

# composer行が変わるまでEnterを送り直す。TUIは再描画中にEnterだけを
# 飲むことがあり、撃ちっぱなしの送信は未送信のまま残ることがある
team_tmux_submit_verified() {
  local pane="$1"
  local before after attempt

  before="$(team_tmux_composer_line "$pane")"
  if [[ -z "$before" ]]; then
    # composerが観測できないpaneでは検証できないので一発送信に落とす
    team_tmux_submit "$pane"
    return 0
  fi
  for attempt in 1 2 3 4; do
    team_tmux_submit "$pane"
    sleep 0.4
    after="$(team_tmux_composer_line "$pane")"
    if [[ "$after" != "$before" ]]; then
      return 0
    fi
    sleep "$attempt"
  done
  return 1
}

# textをpaneへ貼り、composerから消える(=送信された)ことを観測できるまで
# 貼り直しとEnterの再送を行う。貼り付けと送信は開ループでは百発百中に
# ならないので、pane状態の観測で閉ループにする
team_tmux_send_text() {
  local pane="$1"
  local text="$2"
  local buffer_name marker composer paste_attempt enter_attempt

  marker="${text%%$'\n'*}"
  marker="${marker:0:16}"

  for paste_attempt in 1 2 3; do
    team_tmux_prepare_input "$pane"
    buffer_name="agent-team-$$_$RANDOM"
    tmux set-buffer -b "$buffer_name" -- "$text"
    tmux paste-buffer -b "$buffer_name" -p -d -t "$pane"
    sleep 0.3
    composer="$(team_tmux_composer_line "$pane")"
    if [[ -z "$composer" ]]; then
      # composerが観測できないpaneでは検証できないので一発送信に落とす
      team_tmux_submit "$pane"
      return 0
    fi
    if [[ "$composer" != *"$marker"* ]]; then
      # 貼り付けが反映されていない。composerを空にして貼り直す
      continue
    fi
    for enter_attempt in 1 2 3 4; do
      team_tmux_submit "$pane"
      sleep 0.4
      composer="$(team_tmux_composer_line "$pane")"
      if [[ "$composer" != *"$marker"* ]]; then
        return 0
      fi
      sleep "$enter_attempt"
    done
  done
  warn "tmux send was not confirmed for pane $pane"
  return 1
}

team_send_with_body_file() {
  local from="$1"
  local type="$2"
  local task_id="$3"
  local to="$4"
  local body="$5"
  local body_file
  local status

  ensure_team_dirs
  body_file="$(mktemp "$TEAM_STATE_DIR/tmp/message-body.XXXXXX")"
  printf '%s\n' "$body" > "$body_file"

  if "$TEAM_COMMON_DIR/team_send.sh" \
    --from "$from" \
    --type "$type" \
    --task "$task_id" \
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
    # Bypass Permissionsの確認は既定が「No, exit」なので、素のEnterを送ると
    # paneごと終了する。先に「Yes, I accept」の番号へ選択を移す
    if printf '%s\n' "$content" | grep -q 'Yes, I accept'; then
      local accept_option
      accept_option="$(printf '%s\n' "$content" | grep -Eo '[0-9]+\. Yes, I accept' | head -1 | cut -d. -f1)"
      team_tmux_cancel_mode_if_needed "$pane"
      tmux send-keys -t "$pane" "${accept_option:-2}"
      sleep 1
      continue
    fi
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
    "$TEAM_QUEUE_DIR/critiques" \
    "$TEAM_QUEUE_DIR/direction-critiques" \
    "$TEAM_QUEUE_DIR/visuals" \
    "$TEAM_QUEUE_DIR/research" \
    "$TEAM_QUEUE_DIR/strategy" \
    "$TEAM_QUEUE_DIR/architecture" \
    "$TEAM_QUEUE_DIR/memory_proposals" \
    "$TEAM_QUEUE_DIR/skill_proposals" \
    "$TEAM_STATE_DIR/agents" \
    "$TEAM_STATE_DIR/exec" \
    "$TEAM_STATE_DIR/locks" \
    "$TEAM_STATE_DIR/messages" \
    "$TEAM_STATE_DIR/processed" \
    "$TEAM_STATE_DIR/research" \
    "$TEAM_STATE_DIR/task_progress" \
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
  local subtype="$2"
  local scope
  local timestamp

  if [[ -n "$task_id" && "$task_id" != "-" ]]; then
    scope="$task_id"
  else
    scope="general"
  fi
  scope="$(team_sanitize_token "$scope")"
  timestamp="$(team_now_compact_utc)"
  printf '.agents/queue/architecture/%s_%s_%s.md\n' "$scope" "$subtype" "$timestamp"
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

  local attempt holder_pid
  for attempt in $(seq 1 100); do
    if mkdir "$TEAM_LOCK_DIR" 2>/dev/null; then
      printf '%s\n' "$$" > "$TEAM_LOCK_DIR/pid"
      trap 'release_team_lock' EXIT INT TERM
      return 0
    fi
    # trapはSIGKILLに効かない。保持processが死んでいる残骸lockは回収する
    holder_pid="$(cat "$TEAM_LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ -n "$holder_pid" ]]; then
      if ! kill -0 "$holder_pid" 2>/dev/null; then
        rm -rf "$TEAM_LOCK_DIR" 2>/dev/null || true
        continue
      fi
    elif [[ -n "$(find "$TEAM_LOCK_DIR" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; then
      # pidを記録する前に死んだ残骸。1分以上残っていれば回収する
      rm -rf "$TEAM_LOCK_DIR" 2>/dev/null || true
      continue
    fi
    sleep 0.1
  done

  die "could not acquire lock: $name"
}

release_team_lock() {
  if [[ -n "${TEAM_LOCK_DIR:-}" && -d "$TEAM_LOCK_DIR" ]]; then
    rm -rf "$TEAM_LOCK_DIR"
    TEAM_LOCK_DIR=""
  fi
  trap - EXIT INT TERM
}

extract_json_field() {
  local field="$1"
  awk -v field="$field" '
    {
      needle = "\"" field "\":\""
      start = index($0, needle)
      if (!start) {
        next
      }
      i = start + length(needle)
      value = ""
      escaped = 0
      for (; i <= length($0); i++) {
        char = substr($0, i, 1)
        if (escaped) {
          if (char == "n") {
            value = value "\n"
          } else if (char == "r") {
            value = value "\r"
          } else if (char == "t") {
            value = value "\t"
          } else {
            value = value char
          }
          escaped = 0
          continue
        }
        if (char == "\\") {
          escaped = 1
          continue
        }
        if (char == "\"") {
          print value
          found = 1
          exit
        }
        value = value char
      }
    }
  '
}

team_resolve_existing_path() {
  local relative_path="$1"
  local path
  local target
  local dir

  path="$TEAM_ROOT/$relative_path"
  [[ -e "$path" || -L "$path" ]] || return 0

  while [[ -L "$path" ]]; do
    dir="$(dirname "$path")"
    target="$(readlink "$path")"
    if [[ "$target" == /* ]]; then
      path="$target"
    else
      path="$dir/$target"
    fi
  done

  [[ -e "$path" ]] || return 0
  dir="$(cd "$(dirname "$path")" && pwd -P)"
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

team_task_markdown_section_paths() {
  local task_file="$1"
  local section="$2"
  awk -v section="$section" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function parse_path(line, value, parts, token) {
      if (match(line, /`[^`]+`/)) {
        return substr(line, RSTART + 1, RLENGTH - 2)
      }
      value = line
      sub(/^[[:space:]]*-[[:space:]]+/, "", value)
      value = trim(value)
      split(value, parts, /[[:space:]]+/)
      token = parts[1]
      gsub(/[,:;。）、)]$/, "", token)
      if (token ~ /^[A-Za-z0-9._\/@%+=:,{}*?[\]-]+$/ && (token ~ /^([.][\/A-Za-z0-9._-]|\/)/ || token ~ /\// || token ~ /[.][A-Za-z0-9_*?[\]-]+$/ || token ~ /^(Makefile|Dockerfile|LICENSE|README|AGENTS|CLAUDE)$/)) {
        return token
      }
      return ""
    }
    $0 == "## " section {
      in_section = 1
      next
    }
    /^## / && in_section {
      exit
    }
    in_section && /^[[:space:]]*-[[:space:]]+/ {
      value = parse_path($0)
      if (value != "") {
        print value
      }
    }
  ' "$task_file"
}

team_task_markdown_section_invalid_path_bullets() {
  local task_file="$1"
  local section="$2"
  awk -v section="$section" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function parse_path(line, value, parts, token) {
      if (match(line, /`[^`]+`/)) {
        return substr(line, RSTART + 1, RLENGTH - 2)
      }
      value = line
      sub(/^[[:space:]]*-[[:space:]]+/, "", value)
      value = trim(value)
      split(value, parts, /[[:space:]]+/)
      token = parts[1]
      gsub(/[,:;。）、)]$/, "", token)
      if (token ~ /^[A-Za-z0-9._\/@%+=:,{}*?[\]-]+$/ && (token ~ /^([.][\/A-Za-z0-9._-]|\/)/ || token ~ /\// || token ~ /[.][A-Za-z0-9_*?[\]-]+$/ || token ~ /^(Makefile|Dockerfile|LICENSE|README|AGENTS|CLAUDE)$/)) {
        return token
      }
      return ""
    }
    $0 == "## " section {
      in_section = 1
      next
    }
    /^## / && in_section {
      exit
    }
    in_section && /^[[:space:]]*-[[:space:]]+/ {
      if (parse_path($0) == "") {
        print FNR ":" $0
      }
    }
  ' "$task_file"
}

team_path_matches_contract_path() {
  local path="${1#./}"
  local contract_path
  local contract_type

  contract_path="$(team_expand_path "$2")"
  contract_path="${contract_path#./}"
  contract_type="$(git -C "$TEAM_ROOT" cat-file -t "HEAD:$contract_path" 2>/dev/null || true)"

  if [[ "$contract_path" == */ ]]; then
    [[ "$path" == "$contract_path"* ]]
  elif [[ -d "$TEAM_ROOT/$contract_path" || "$contract_type" == "tree" ]]; then
    [[ "$path" == "$contract_path" || "$path" == "$contract_path/"* ]]
  else
    [[ "$path" == $contract_path ]]
  fi
}

team_path_matches_task_section() {
  local task_file="$1"
  local section="$2"
  local path="$3"
  local contract_path

  while IFS= read -r contract_path; do
    if team_path_matches_contract_path "$path" "$contract_path"; then
      return 0
    fi
  done < <(team_task_markdown_section_paths "$task_file" "$section")
  return 1
}

team_git_changed_paths() {
  {
    git -C "$TEAM_ROOT" diff --name-only --no-renames --relative HEAD --
    git -C "$TEAM_ROOT" ls-files --others --exclude-standard
  } | sed '/^$/d' | LC_ALL=C sort -u
}

team_git_changed_paths_except() {
  local path allowed_path allowed

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    allowed="false"
    for allowed_path in "$@"; do
      if [[ "$path" == "$allowed_path" ]]; then
        allowed="true"
        break
      fi
    done
    [[ "$allowed" == "true" ]] || printf '%s\n' "$path"
  done < <(team_git_changed_paths)
}

# Allowed pathsがすべてteam rootの外(絶対path)のtaskは、team rootにcommitを作らない。
# その場合reportはtask commitなしで受け付け、成果の場所と検証は本文が持つ
team_task_allowed_paths_all_external() {
  local task_file="$1"
  local entry expanded found=0

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    found=1
    expanded="$(team_expand_path "$entry")"
    case "$expanded" in
      "$TEAM_ROOT"/*|"$TEAM_ROOT") return 1 ;;
      /*) ;;
      *) return 1 ;;
    esac
  done < <(team_task_markdown_section_paths "$task_file" "Allowed paths")
  [[ "$found" == "1" ]]
}

team_task_changed_allowed_paths() {
  local task_id="$1"
  local task_file="$TEAM_QUEUE_DIR/tasks/$task_id.md"
  local path entry a b allowed_specific protected_specific
  local -a allowed_entries protected_entries matched_allowed matched_protected

  [[ -f "$task_file" ]] || die "task file not found: $task_id"
  allowed_entries=()
  while IFS= read -r entry; do
    [[ -n "$entry" ]] && allowed_entries+=("$entry")
  done < <(team_task_markdown_section_paths "$task_file" "Allowed paths")
  protected_entries=()
  while IFS= read -r entry; do
    [[ -n "$entry" ]] && protected_entries+=("$entry")
  done < <(team_task_markdown_section_paths "$task_file" "Do not modify")

  while IFS= read -r path; do
    matched_allowed=()
    for a in "${allowed_entries[@]}"; do
      if team_path_matches_contract_path "$path" "$a"; then
        matched_allowed+=("$a")
      fi
    done
    [[ "${#matched_allowed[@]}" -gt 0 ]] || continue

    matched_protected=()
    for b in "${protected_entries[@]}"; do
      if team_path_matches_contract_path "$path" "$b"; then
        matched_protected+=("$b")
      fi
    done

    if [[ "${#matched_protected[@]}" -gt 0 ]]; then
      # 例外契約: 変更pathが両sectionに合致する場合、包含関係にあれば狭い方の主張が勝つ
      allowed_specific=0
      protected_specific=0
      for a in "${matched_allowed[@]}"; do
        for b in "${matched_protected[@]}"; do
          if team_path_matches_contract_path "$a" "$b"; then
            allowed_specific=1
          fi
          if team_path_matches_contract_path "$b" "$a"; then
            protected_specific=1
          fi
        done
      done
      if [[ "$allowed_specific" == "1" && "$protected_specific" == "0" ]]; then
        : # 広い保護の中の狭い許可。taskが所有する
      elif [[ "$protected_specific" == "1" && "$allowed_specific" == "0" ]]; then
        continue # 広い許可の中の狭い保護。taskは所有しない
      else
        die_rule \
          "task path is both allowed and protected: $path" \
          "$task_file assigns conflicting ownership to the same changed path, and neither contract path contains the other" \
          "make one of the overlapping contract paths strictly narrower than the other"
      fi
    fi
    printf '%s\n' "$path"
  done < <(team_git_changed_paths)
}

team_require_task_paths_clean() {
  local task_id="$1"
  local dirty_paths

  dirty_paths="$(team_task_changed_allowed_paths "$task_id")"
  [[ -z "$dirty_paths" ]] || die_rule \
    "task-owned changes are not committed: $task_id" \
    "the following paths still differ from HEAD: $(printf '%s' "$dirty_paths" | paste -sd ',' - | sed 's/,/, /g')" \
    "commit them with make task-commit TASK=$task_id MESSAGE='<summary>', then rerun make report"
}

team_task_commits() {
  local task_id="$1"
  local base_commit="$2"
  local commit

  git -C "$TEAM_ROOT" merge-base --is-ancestor "$base_commit" HEAD >/dev/null 2>&1 || die_rule \
    "task base is not an ancestor of HEAD: $task_id" \
    "the repository history no longer contains dispatch base $base_commit on the current line" \
    "ask Manager to reconcile the task with the current repository history"

  while IFS= read -r commit; do
    if git -C "$TEAM_ROOT" show -s --format=%B "$commit" \
      | git -C "$TEAM_ROOT" interpret-trailers --parse \
      | grep -Fqx "Agent-Task: $task_id"; then
      printf '%s\n' "$commit"
    fi
  done < <(git -C "$TEAM_ROOT" rev-list --reverse "$base_commit..HEAD")
}

team_replace_markdown_section() {
  local file="$1"
  local section="$2"
  local content_file="$3"
  local tmp

  tmp="$(mktemp)"
  awk -v section="$section" -v content_file="$content_file" '
    $0 == "## " section {
      print
      print ""
      while ((getline line < content_file) > 0) {
        print line
      }
      close(content_file)
      replacing = 1
      found = 1
      next
    }
    replacing && /^## / {
      print ""
      replacing = 0
    }
    !replacing { print }
    END { exit found ? 0 : 1 }
  ' "$file" > "$tmp" || {
    rm -f "$tmp"
    die "markdown section not found: $section in $file"
  }
  mv "$tmp" "$file"
}

team_message_body_summary() {
  awk '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "") {
        print line
        found = 1
        exit
      }
    }
    END {
      if (!found) {
        print ""
      }
    }
  '
}

team_task_progress_file() {
  local task_id="$1"
  printf '%s/task_progress/%s.jsonl\n' "$TEAM_STATE_DIR" "$task_id"
}

team_message_auto_process_on_read() {
  local message_type="$1"
  case "$message_type" in
    supervision_checkpoint|supervision_assigned|research_cancelled)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

team_inbox_has_pending() {
  local agent_id="$1"
  local inbox_file="$TEAM_QUEUE_DIR/inbox/$agent_id.jsonl"
  local processed_dir="$TEAM_STATE_DIR/processed/$agent_id"
  local line
  local message_id

  [[ -f "$inbox_file" ]] || return 1
  while IFS= read -r line; do
    message_id="$(printf '%s\n' "$line" | extract_json_field id)"
    [[ -n "$message_id" ]] || continue
    [[ -f "$processed_dir/$message_id" ]] || return 0
  done < "$inbox_file"
  return 1
}

team_mark_message_processed() {
  local agent_id="$1"
  local message_id="$2"

  [[ -n "$agent_id" && -n "$message_id" ]] || return 0
  mkdir -p "$TEAM_STATE_DIR/processed/$agent_id"
  printf '%s\n' "$(team_now_utc)" > "$TEAM_STATE_DIR/processed/$agent_id/$message_id"
}

team_mark_research_inbox_processed() {
  local agent_id="$1"
  local request_id="$2"
  shift 2

  local inbox_file="$TEAM_QUEUE_DIR/inbox/$agent_id.jsonl"
  local line message_id message_request message_type wanted_type type_matches

  [[ -n "$agent_id" && -n "$request_id" && -f "$inbox_file" ]] || return 0
  while IFS= read -r line; do
    message_request="$(printf '%s\n' "$line" | extract_json_field research_id)"
    [[ "$message_request" == "$request_id" ]] || continue

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

    message_id="$(printf '%s\n' "$line" | extract_json_field id)"
    team_mark_message_processed "$agent_id" "$message_id"
  done < "$inbox_file"
}

team_record_task_message_activity() {
  local message_id="$1"
  local message_file="$TEAM_STATE_DIR/messages/$message_id.json"
  local line
  local task_id
  local message_type
  local message_from
  local message_to
  local created_at
  local body
  local summary
  local progress_file

  [[ -f "$message_file" ]] || return 0
  line="$(cat "$message_file")"
  task_id="$(printf '%s\n' "$line" | extract_json_field task_id)"
  [[ -n "$task_id" && "$task_id" != "-" ]] || return 0

  message_type="$(printf '%s\n' "$line" | extract_json_field type)"
  message_from="$(printf '%s\n' "$line" | extract_json_field from)"
  message_to="$(printf '%s\n' "$line" | extract_json_field to)"
  created_at="$(printf '%s\n' "$line" | extract_json_field created_at)"
  body="$(printf '%s\n' "$line" | extract_json_field body)"
  summary="$(printf '%s\n' "$body" | team_message_body_summary)"
  progress_file="$(team_task_progress_file "$task_id")"

  mkdir -p "$(dirname "$progress_file")"
  printf '{"message_id":"%s","task_id":"%s","type":"%s","from":"%s","to":"%s","created_at":"%s","summary":"%s"}\n' \
    "$(json_string "$message_id")" \
    "$(json_string "$task_id")" \
    "$(json_string "$message_type")" \
    "$(json_string "$message_from")" \
    "$(json_string "$message_to")" \
    "$(json_string "$created_at")" \
    "$(json_string "$summary")" >> "$progress_file"
}

team_mark_inbox_processed() {
  local agent_id="$1"
  local task_id="$2"
  shift 2

  local inbox_file="$TEAM_QUEUE_DIR/inbox/$agent_id.jsonl"
  local processed_dir="$TEAM_STATE_DIR/processed/$agent_id"
  local line message_id message_task message_type wanted_type type_matches

  if [[ ( -z "$task_id" || "$task_id" == "-" ) && $# -eq 0 ]]; then
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

team_research_id() {
  printf 'research_%s_%s_%s\n' "$(team_now_compact_utc)" "$$" "$RANDOM"
}

team_research_state_file() {
  local request_id="$1"
  printf '%s/research/%s.json\n' "$TEAM_STATE_DIR" "$request_id"
}

team_research_state_field() {
  local request_id="$1"
  local field="$2"
  local state_file
  state_file="$(team_research_state_file "$request_id")"
  [[ -f "$state_file" ]] || return 0
  extract_json_field "$field" < "$state_file"
}

team_write_research_state() {
  local request_id="$1"
  local caller="$2"
  local worker="$3"
  local status="$4"
  local request_message_id="$5"
  local artifact="$6"
  local task_id="$7"
  local created_at="$8"
  local state_file
  local updated_at

  state_file="$(team_research_state_file "$request_id")"
  updated_at="$(team_now_utc)"
  mkdir -p "$(dirname "$state_file")"
  printf '{"request_id":"%s","caller":"%s","worker":"%s","status":"%s","request_message_id":"%s","artifact":"%s","task_id":"%s","created_at":"%s","updated_at":"%s"}\n' \
    "$(json_string "$request_id")" \
    "$(json_string "$caller")" \
    "$(json_string "$worker")" \
    "$(json_string "$status")" \
    "$(json_string "$request_message_id")" \
    "$(json_string "$artifact")" \
    "$(json_string "$task_id")" \
    "$(json_string "$created_at")" \
    "$updated_at" > "$state_file"
}

team_research_worker_active_request() {
  local worker="$1"
  local state_file
  local state_worker
  local state_status

  while IFS= read -r state_file; do
    state_worker="$(extract_json_field worker < "$state_file")"
    [[ "$state_worker" == "$worker" ]] || continue
    state_status="$(extract_json_field status < "$state_file")"
    case "$state_status" in
      assigning|active)
        basename "$state_file" .json
        return 0
        ;;
    esac
  done < <(find "$TEAM_STATE_DIR/research" -maxdepth 1 -type f -name '*.json' | sort)
  return 1
}

team_markdown_section_has_content() {
  local file="$1"
  local section="$2"
  awk -v section="$section" '
    $0 == "## " section { in_section = 1; next }
    /^## / && in_section { exit }
    in_section {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "" && line !~ /^<!--/ && line !~ /^Status:/) {
        found = 1
        exit
      }
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

team_write_task_state() {
  local task_id="$1"
  local owner="$2"
  local worker="$3"
  local supervisor="$4"
  local status="$5"
  local base_commit="$6"
  local task_commits="$7"
  local report="$8"
  local supervision_artifact="$9"
  local supervision_decision="${10}"
  local done_recommendation="${11}"
  local architecture_required="${12}"
  local architecture="${13}"
  local direction_status="${14}"
  local direction_artifact="${15}"
  local state_file
  local updated_at

  state_file="$(team_task_state_file "$task_id")"
  updated_at="$(team_now_utc)"
  mkdir -p "$(dirname "$state_file")"

  printf '{"task_id":"%s","owner":"%s","worker":"%s","supervisor":"%s","status":"%s","base_commit":"%s","task_commits":"%s","report":"%s","supervision_artifact":"%s","supervision_decision":"%s","done_recommendation":"%s","architecture_required":"%s","architecture":"%s","direction_status":"%s","direction_artifact":"%s","updated_at":"%s"}\n' \
    "$(json_string "$task_id")" \
    "$(json_string "$owner")" \
    "$(json_string "$worker")" \
    "$(json_string "$supervisor")" \
    "$(json_string "$status")" \
    "$(json_string "$base_commit")" \
    "$(json_string "$task_commits")" \
    "$(json_string "$report")" \
    "$(json_string "$supervision_artifact")" \
    "$(json_string "$supervision_decision")" \
    "$(json_string "$done_recommendation")" \
    "$(json_string "$architecture_required")" \
    "$(json_string "$architecture")" \
    "$(json_string "$direction_status")" \
    "$(json_string "$direction_artifact")" \
    "$updated_at" > "$state_file"
}

team_task_worker_is_busy() {
  local worker="$1"
  local state_file
  local state_worker
  local state_status

  while IFS= read -r state_file; do
    state_worker="$(extract_json_field worker < "$state_file")"
    [[ "$state_worker" == "$worker" ]] || continue
    state_status="$(extract_json_field status < "$state_file")"
    if [[ "$state_status" != "done" ]]; then
      basename "$state_file" .json
      return 0
    fi
  done < <(find "$TEAM_STATE_DIR/tasks" -maxdepth 1 -type f -name '*.json' | sort)
  return 1
}

team_task_supervisor_is_busy() {
  local supervisor="$1"
  local state_file
  local state_supervisor
  local state_status

  while IFS= read -r state_file; do
    state_supervisor="$(extract_json_field supervisor < "$state_file")"
    [[ "$state_supervisor" == "$supervisor" ]] || continue
    state_status="$(extract_json_field status < "$state_file")"
    if [[ "$state_status" != "done" ]]; then
      basename "$state_file" .json
      return 0
    fi
  done < <(find "$TEAM_STATE_DIR/tasks" -maxdepth 1 -type f -name '*.json' | sort)
  return 1
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
  local task_commits="$4"
  local current_task_commits

  [[ -n "$report_file" && -f "$report_file" ]] || die_rule \
    "report file not found for $task_id" \
    "task state points to a report that does not exist" \
    "the assigned worker must run make report TASK=$task_id STATUS=needs_supervision"
  team_require_report_field "$report_file" "Base commit" "$base_commit"
  team_require_report_field "$report_file" "Task commits" "$task_commits"
  team_require_task_paths_clean "$task_id"
  current_task_commits="$(team_task_commits "$task_id" "$base_commit" | paste -sd ' ' -)"
  # 外部repoのtaskはtask_commits='none'で記録される。現在もcommitが無ければ一致とみなす
  if [[ "$task_commits" == "none" && -z "$current_task_commits" ]]; then
    current_task_commits="none"
  fi
  [[ "$current_task_commits" == "$task_commits" ]] || die_rule \
    "task report is stale: $task_id" \
    "task state records '${task_commits:-no commits}', but current task commits are '${current_task_commits:-no commits}'" \
    "rerun make report TASK=$task_id STATUS=needs_supervision and refresh its evidence"
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

team_state_file() {
  printf '%s/STATE.md\n' "$TEAM_MEMORY_DIR"
}

team_memory_file() {
  printf '%s/MEMORY.md\n' "$TEAM_MEMORY_DIR"
}
