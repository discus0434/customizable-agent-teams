#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_BASE="$(mktemp -d)"
TMP_ROOT="$TMP_BASE/repo"
TMP_CONFIG_FILE="$TMP_ROOT/.agents/config/agent-team.yaml"
trap 'rm -rf "$TMP_BASE"' EXIT

fail() {
  echo "harness test failed: $*" >&2
  exit 1
}

team() {
  PATH="$TMP_BASE/bin:$PATH" \
    TEAM_ROOT="$TMP_ROOT" \
    TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
    TEAM_DISABLE_NUDGE=1 \
    "$@"
}

as_agent() {
  local agent_id="$1"
  shift
  PATH="$TMP_BASE/bin:$PATH" \
    TEAM_AGENT_ID="$agent_id" \
    TEAM_ROOT="$TMP_ROOT" \
    TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
    TEAM_DISABLE_NUDGE=1 \
    "$@"
}

state_field() {
  local scope="$1"
  local id="$2"
  local field="$3"
  TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" bash -c \
    'source "$1/.agents/scripts/team_common.sh"; function_name="team_${2}_state_field"; "$function_name" "$3" "$4"' \
    _ "$TMP_ROOT" "$scope" "$id" "$field"
}

request_research() {
  local caller="$1"
  local body="$2"
  local output
  output="$(team "$TMP_ROOT/.agents/scripts/team_send.sh" --from "$caller" research-worker "$body")"
  printf '%s\n' "$output" | sed -n 's/^request_id=//p'
}

# A checkout provides every queue dir through tracked .gitkeep files; the
# scripts only create the gitignored runtime dirs under queue/state/.
mkdir -p \
  "$TMP_ROOT/.agents/queue/tasks" \
  "$TMP_ROOT/.agents/queue/backlog" \
  "$TMP_ROOT/.agents/queue/inbox" \
  "$TMP_ROOT/.agents/queue/reports" \
  "$TMP_ROOT/.agents/queue/reviews" \
  "$TMP_ROOT/.agents/queue/critiques" \
  "$TMP_ROOT/.agents/queue/direction-critiques" \
  "$TMP_ROOT/.agents/queue/visuals" \
  "$TMP_ROOT/.agents/queue/research" \
  "$TMP_ROOT/.agents/queue/strategy" \
  "$TMP_ROOT/.agents/queue/architecture" \
  "$TMP_ROOT/.agents/queue/memory_proposals" \
  "$TMP_ROOT/.agents/queue/skill_proposals"
cp -R "$ROOT/.agents/scripts" "$TMP_ROOT/.agents/scripts"
cp -R "$ROOT/.agents/config" "$TMP_ROOT/.agents/config"
cp -R "$ROOT/.agents/docs" "$TMP_ROOT/.agents/docs"
cp -R "$ROOT/.agents/state" "$TMP_ROOT/.agents/state"
cp "$ROOT/.agents/agent-team.mk" "$TMP_ROOT/.agents/agent-team.mk"
cp "$ROOT/.gitignore" "$TMP_ROOT/.gitignore"
cp "$ROOT/AGENTS.md" "$TMP_ROOT/AGENTS.md"
cp "$ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md"
cp "$ROOT/.agents/queue/tasks/FRONTEND_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/FRONTEND_TEMPLATE.md"
cp "$ROOT/.agents/queue/tasks/EXPRESS_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/EXPRESS_TEMPLATE.md"
ln -s AGENTS.md "$TMP_ROOT/CLAUDE.md"
mkdir -p "$TMP_ROOT/.codex" "$TMP_ROOT/.claude"
ln -s ../.agents/skills "$TMP_ROOT/.codex/skills"
ln -s ../.codex/skills "$TMP_ROOT/.claude/skills"

cat > "$TMP_ROOT/Makefile" <<'MAKE'
.PHONY: post-change smoke

post-change:
	@git diff --check -- .
	@echo "temp post-change ok"

smoke:
	@if [ -f .agents/queue/state/fail-smoke ]; then echo "forced smoke failure" >&2; exit 1; fi
	@echo "temp smoke ok"

include .agents/agent-team.mk
MAKE

mkdir -p "$TMP_BASE/bin"
cat > "$TMP_BASE/bin/tmux" <<'SH'
#!/usr/bin/env bash
case "$1" in
  has-session)
    [[ "${TEAM_FAKE_TMUX_HAS_SESSION:-0}" == "1" ]]
    ;;
  display-message)
    if [[ -n "${TEAM_FAKE_TMUX_PANE_GONE:-}" ]]; then
      echo "can't find pane" >&2
      exit 1
    fi
    if [[ "$*" == *"#{pane_in_mode}"* ]]; then
      printf '0\n'
    elif [[ "$*" == *"#{session_name}"* ]]; then
      printf 'agent-team\n'
    elif [[ "$*" == *"#{pane_id}"* ]]; then
      printf '%%fake\n'
    elif [[ "$*" == *"#{cursor_x},#{cursor_y}"* ]]; then
      # 実UIに合わせる: 予測やplaceholder(ghost:)はcursorを内容の先頭に
      # 残し、人間が打った文字はcursorを内容の末尾へ進める
      row=1
      [[ -n "${TEAM_FAKE_TMUX_TRANSCRIPT_FILE:-}" && -f "$TEAM_FAKE_TMUX_TRANSCRIPT_FILE" ]] && row=2
      content=""
      if [[ -n "${TEAM_FAKE_TMUX_INPUT_FILE:-}" && -f "$TEAM_FAKE_TMUX_INPUT_FILE" ]]; then
        content="$(head -n 1 "$TEAM_FAKE_TMUX_INPUT_FILE")"
      elif [[ -n "${TEAM_FAKE_TMUX_COMPOSER:-}" && -f "$TEAM_FAKE_TMUX_COMPOSER" ]]; then
        content="$(head -n 1 "$TEAM_FAKE_TMUX_COMPOSER")"
      fi
      case "$content" in
        ghost:*) printf '2,%s\n' "$row" ;;
        "") printf '2,%s\n' "$row" ;;
        *) printf '%s,%s\n' "$(( 2 + ${#content} ))" "$row" ;;
      esac
    fi
    ;;
  capture-pane)
    # 実UIに合わせる: transcriptの過去messageは「❯ + 通常space」、
    # composerは「prompt + non-breaking space」で、空でも表示される
    if [[ -n "${TEAM_FAKE_TMUX_BUSY_FILE:-}" && -f "$TEAM_FAKE_TMUX_BUSY_FILE" ]]; then
      printf '%s\n' "Working (1s - esc to interrupt)"
    else
      printf '%s\n' "Claude Code"
      if [[ -n "${TEAM_FAKE_TMUX_TRANSCRIPT_FILE:-}" && -f "$TEAM_FAKE_TMUX_TRANSCRIPT_FILE" ]]; then
        printf '❯ %s\n' "$(cat "$TEAM_FAKE_TMUX_TRANSCRIPT_FILE")"
      fi
      if [[ -n "${TEAM_FAKE_TMUX_INPUT_FILE:-}" && -f "$TEAM_FAKE_TMUX_INPUT_FILE" ]]; then
        input_render="$(cat "$TEAM_FAKE_TMUX_INPUT_FILE")"
        printf '❯\xc2\xa0%s\n' "${input_render#ghost:}"
      elif [[ -n "${TEAM_FAKE_TMUX_COMPOSER:-}" && -f "$TEAM_FAKE_TMUX_COMPOSER" ]]; then
        if [[ -n "${TEAM_FAKE_TMUX_PASTE_LAG:-}" && -s "$TEAM_FAKE_TMUX_PASTE_LAG" ]] \
          && [[ "$(cat "$TEAM_FAKE_TMUX_PASTE_LAG")" -gt 0 ]]; then
          # 貼り付けのechoが描画に遅れるpaneを再現する: 残count回はcomposerを空で見せる
          printf '%s\n' "$(( $(cat "$TEAM_FAKE_TMUX_PASTE_LAG") - 1 ))" > "$TEAM_FAKE_TMUX_PASTE_LAG"
          printf '%s\xc2\xa0\n' "${TEAM_FAKE_TMUX_PROMPT:-❯}"
        else
          composer_render="$(head -n 1 "$TEAM_FAKE_TMUX_COMPOSER")"
          printf '%s\xc2\xa0%s\n' "${TEAM_FAKE_TMUX_PROMPT:-❯}" "${composer_render#ghost:}"
        fi
      fi
    fi
    ;;
  list-panes)
    [[ -n "${TEAM_FAKE_TMUX_LOG:-}" ]] && printf '%s\n' "$*" >> "$TEAM_FAKE_TMUX_LOG"
    printf '%s\n' '  %fake lead agent=lead role=lead model=claude-opus-4-8'
    printf '%s\n' '  %fake strategist agent=strategist role=strategist model=gpt-5.6-sol'
    ;;
  set-buffer)
    [[ -n "${TEAM_FAKE_TMUX_LOG:-}" ]] && printf '%s\n' "$*" >> "$TEAM_FAKE_TMUX_LOG"
    if [[ -n "${TEAM_FAKE_TMUX_COMPOSER:-}" ]]; then
      for _last; do :; done
      printf '%s\n' "$_last" > "$TEAM_FAKE_TMUX_COMPOSER.buffer"
    fi
    ;;
  paste-buffer)
    [[ -n "${TEAM_FAKE_TMUX_LOG:-}" ]] && printf '%s\n' "$*" >> "$TEAM_FAKE_TMUX_LOG"
    if [[ -n "${TEAM_FAKE_TMUX_COMPOSER:-}" && -f "$TEAM_FAKE_TMUX_COMPOSER.buffer" ]]; then
      cp "$TEAM_FAKE_TMUX_COMPOSER.buffer" "$TEAM_FAKE_TMUX_COMPOSER"
    fi
    ;;
  send-keys)
    [[ -n "${TEAM_FAKE_TMUX_LOG:-}" ]] && printf '%s\n' "$*" >> "$TEAM_FAKE_TMUX_LOG"
    if [[ -n "${TEAM_FAKE_TMUX_COMPOSER:-}" ]]; then
      case "$*" in
        *C-m*)
          if [[ -n "${TEAM_FAKE_TMUX_SWALLOW:-}" && -f "$TEAM_FAKE_TMUX_SWALLOW" ]]; then
            rm -f "$TEAM_FAKE_TMUX_SWALLOW"
          elif [[ -f "$TEAM_FAKE_TMUX_COMPOSER" ]]; then
            : > "$TEAM_FAKE_TMUX_COMPOSER"
          fi
          ;;
        *C-u*)
          if [[ -f "$TEAM_FAKE_TMUX_COMPOSER" ]]; then
            : > "$TEAM_FAKE_TMUX_COMPOSER"
          fi
          ;;
      esac
    fi
    ;;
  set-option|new-session|new-window|kill-session)
    [[ -n "${TEAM_FAKE_TMUX_LOG:-}" ]] && printf '%s\n' "$*" >> "$TEAM_FAKE_TMUX_LOG"
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$TMP_BASE/bin/tmux"

cat > "$TMP_BASE/bin/sleep" <<'SH'
#!/usr/bin/env bash
if [[ "${TEAM_FAKE_REAL_SLEEP:-0}" == "1" ]]; then
  /bin/sleep "$@"
fi
exit 0
SH
chmod +x "$TMP_BASE/bin/sleep"

cat > "$TMP_BASE/bin/date" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "+%s" && -n "$TEAM_FAKE_WATCH_EPOCH" ]]; then
  printf '%s\n' "$TEAM_FAKE_WATCH_EPOCH"
  exit 0
fi
exec /bin/date "$@"
SH
chmod +x "$TMP_BASE/bin/date"

cat > "$TMP_BASE/bin/codex" <<'SH'
#!/usr/bin/env bash
if [[ -n "${TEAM_FAKE_CODEX_LOG:-}" ]]; then
  printf 'codex %s\n' "$*" >> "$TEAM_FAKE_CODEX_LOG"
fi
printf '%s\n' '{"type":"thread.started","thread_id":"00000000-0000-4000-8000-000000000000"}'
exit 0
SH
chmod +x "$TMP_BASE/bin/codex"
export TEAM_FAKE_CODEX_LOG="$TMP_BASE/codex.log"
: > "$TEAM_FAKE_CODEX_LOG"

git -C "$TMP_ROOT" init -q
git -C "$TMP_ROOT" config user.email "agent-team-test@example.local"
git -C "$TMP_ROOT" config user.name "Agent Team Test"
git -C "$TMP_ROOT" add .
git -C "$TMP_ROOT" commit -qm "Initial template"

# Config and launcher contracts.
team "$TMP_ROOT/.agents/scripts/team_config.sh" validate
general_command="$(team "$TMP_ROOT/.agents/scripts/team_config.sh" command general-worker-1)"
hard_command="$(team "$TMP_ROOT/.agents/scripts/team_config.sh" command hard-task-worker-1)"
reviewer_command="$(team "$TMP_ROOT/.agents/scripts/team_config.sh" command general-reviewer-1)"
critic_command="$(team "$TMP_ROOT/.agents/scripts/team_config.sh" command frontend-critic-1)"
[[ "$general_command" == *"--dangerously-bypass-approvals-and-sandbox"* ]] || fail "general worker lost Codex permission bypass"
[[ "$general_command" == *"--model gpt-5.6-luna"* ]] || fail "general worker model is not gpt-5.6-luna"
[[ "$general_command" == *'model_reasoning_effort=\"high\"'* ]] || fail "general worker effort is not high"
[[ "$hard_command" == *"--dangerously-bypass-approvals-and-sandbox"* ]] || fail "hard task worker lost Codex permission bypass"
[[ "$hard_command" == *"--model gpt-5.6-sol"* ]] || fail "hard task worker model is not gpt-5.6-sol"
[[ "$hard_command" == *'model_reasoning_effort=\"xhigh\"'* ]] || fail "hard task worker effort is not xhigh"
[[ "$reviewer_command" == *"--model gpt-5.6-sol"* ]] || fail "general reviewer model is not gpt-5.6-sol"
[[ "$reviewer_command" == *'model_reasoning_effort=\"low\"'* ]] || fail "general reviewer effort is not low"
[[ "$critic_command" == *"--dangerously-skip-permissions"* ]] || fail "frontend critic lost Claude permission bypass"
if team "$TMP_ROOT/.agents/scripts/team_config.sh" command research-worker-1 \
  > /dev/null 2> "$TMP_BASE/exec-launcher.err"; then
  fail "on-demand research worker offered a resident launcher"
fi
grep -q 'on-demand role has no resident launcher' "$TMP_BASE/exec-launcher.err"
if team "$TMP_ROOT/.agents/scripts/team_config.sh" command express-worker-1 \
  > /dev/null 2>> "$TMP_BASE/exec-launcher.err"; then
  fail "on-demand express worker offered a resident launcher"
fi
[[ "$(team "$TMP_ROOT/.agents/scripts/team_config.sh" field express-worker-1 model)" == "gpt-5.6-luna" ]] \
  || fail "express worker model does not match the research worker tier"

export TEAM_FAKE_TMUX_LOG="$TMP_BASE/tmux.log"
: > "$TEAM_FAKE_TMUX_LOG"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=0 \
  TEAM_BOOT_NUDGE=1 \
  "$TMP_ROOT/.agents/scripts/team_start.sh" --lead-only > "$TMP_BASE/team-start.out"
grep -q '^started tmux session: agent-team$' "$TMP_BASE/team-start.out"
grep -q '^effort=xhigh$' "$TMP_ROOT/.agents/queue/state/agents/lead.env"
grep -q -- '--dangerously-skip-permissions' "$TEAM_FAKE_TMUX_LOG"
[[ "$(awk '{ count += gsub(/C-m/, "") } END { print count + 0 }' "$TEAM_FAKE_TMUX_LOG")" -eq 1 ]] \
  || fail "boot prompt was not submitted exactly once"
grep -q '^paste-buffer .* -p -d -t ' "$TEAM_FAKE_TMUX_LOG" \
  || fail "boot prompt did not use bracketed paste"

# A pane that never becomes ready (slow machines hit this as a startup race)
# must not abort team-start mid-loop: the start still registers the agent and
# reports the missed nudge at the end, instead of leaving the team half-started.
slow_busy_file="$TMP_BASE/slow-start.busy"
: > "$slow_busy_file"
if PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=0 \
  TEAM_BOOT_NUDGE=1 \
  TEAM_BOOT_NUDGE_READY_TIMEOUT=2 \
  TEAM_FAKE_TMUX_BUSY_FILE="$slow_busy_file" \
  "$TMP_ROOT/.agents/scripts/team_start.sh" --lead-only \
  > "$TMP_BASE/slow-start.out" 2> "$TMP_BASE/slow-start.err"; then
  fail "team-start reported success although a boot nudge was never confirmed"
fi
grep -q 'boot nudge was not confirmed for: lead' "$TMP_BASE/slow-start.err" \
  || fail "team-start did not report the missed boot nudge"
grep -q '^agent_id=lead$' "$TMP_ROOT/.agents/queue/state/agents/lead.env" \
  || fail "missed boot nudge prevented agent registration"
rm "$slow_busy_file"

# An agent whose pane dies during startup is collected the same way: the loop
# moves on, no agent state is registered for the dead pane (so a later
# --complete-existing run recreates exactly the missing agents), and the
# failure is reported at the end instead of aborting the start mid-loop.
if PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=0 \
  TEAM_BOOT_NUDGE=1 \
  TEAM_FAKE_TMUX_PANE_GONE=1 \
  "$TMP_ROOT/.agents/scripts/team_start.sh" --lead-only \
  > "$TMP_BASE/dead-pane.out" 2> "$TMP_BASE/dead-pane.err"; then
  fail "team-start reported success although an agent pane died"
fi
grep -q 'agent panes exited during startup: lead' "$TMP_BASE/dead-pane.err" \
  || fail "team-start did not report the dead pane"
[[ ! -f "$TMP_ROOT/.agents/queue/state/agents/lead.env" ]] \
  || fail "a dead pane still registered agent state"

# Restore the healthy started state that the tests below rely on.
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=0 \
  TEAM_BOOT_NUDGE=1 \
  "$TMP_ROOT/.agents/scripts/team_start.sh" --lead-only > /dev/null

# Busy panes receive one deferred nudge without interrupting current work.
busy_file="$TMP_BASE/pane.busy"
: > "$busy_file"
printf '%s\n' '{"id":"msg_deferred","from":"manager","to":"lead","type":"request","requires_attention":"true","created_at":"2026-01-01T00:00:00Z","body":"deferred"}' \
  >> "$TMP_ROOT/.agents/queue/inbox/lead.jsonl"
paste_count_before="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_REAL_SLEEP=1 \
  TEAM_FAKE_TMUX_BUSY_FILE="$busy_file" \
  "$TMP_ROOT/.agents/scripts/team_nudge.sh" lead > /dev/null 2> "$TMP_BASE/deferred-nudge.err"
grep -q '^\[team\] queued nudge for lead; pane is busy or holds unsent input$' "$TMP_BASE/deferred-nudge.err"
[[ "$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)" == "$paste_count_before" ]] \
  || fail "busy pane was interrupted by an immediate nudge"
rm "$busy_file"
for _attempt in $(seq 1 30); do
  paste_count_after="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
  [[ "$paste_count_after" -gt "$paste_count_before" ]] && break
  /bin/sleep 0.1
done
[[ "${paste_count_after:-0}" -gt "$paste_count_before" ]] \
  || fail "deferred nudge was not delivered after the pane became idle"

# The busy-test waiter holds the nudge lock while it finishes delivering.
# Wait for it to exit so the next deferral test starts its own waiter.
for _attempt in $(seq 1 30); do
  [[ -d "$TMP_ROOT/.agents/queue/state/locks/nudge-lead.lock" ]] || break
  /bin/sleep 0.1
done
[[ ! -d "$TMP_ROOT/.agents/queue/state/locks/nudge-lead.lock" ]] \
  || fail "busy-test waiter did not release its lock"

# Panes holding unsent human input defer the nudge until the input is sent.
input_file="$TMP_BASE/pane.input"
printf '%s\n' '書きかけの依頼文' > "$input_file"
printf '%s\n' '{"id":"msg_input_pending","from":"manager","to":"lead","type":"request","requires_attention":"true","created_at":"2026-01-01T00:00:01Z","body":"pending input"}' \
  >> "$TMP_ROOT/.agents/queue/inbox/lead.jsonl"
paste_count_before="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_REAL_SLEEP=1 \
  TEAM_FAKE_TMUX_INPUT_FILE="$input_file" \
  "$TMP_ROOT/.agents/scripts/team_nudge.sh" lead > /dev/null 2> "$TMP_BASE/input-nudge.err"
grep -q '^\[team\] queued nudge for lead; pane is busy or holds unsent input$' "$TMP_BASE/input-nudge.err"
[[ "$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)" == "$paste_count_before" ]] \
  || fail "unsent human input was clobbered by an immediate nudge"
printf '%s\n' 'ghost:Try "fix lint errors"' > "$input_file"
for _attempt in $(seq 1 30); do
  paste_count_after="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
  [[ "$paste_count_after" -gt "$paste_count_before" ]] && break
  /bin/sleep 0.1
done
[[ "${paste_count_after:-0}" -gt "$paste_count_before" ]] \
  || fail "deferred nudge was not delivered after the input became a placeholder"
rm "$input_file"

# Regression (lost wakeup): nudge delivery is a one-shot edge trigger, so a
# lost nudge leaves a pane idle with pending messages and the whole team can
# stall. The team_watch sweep re-nudges exactly that state.
paste_count_before="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
[[ "$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)" -gt "$paste_count_before" ]] \
  || fail "team_watch did not wake an idle pane with pending messages"

# Regression (swallowed Enter): the TUI can drop the submit keystroke while
# re-rendering, leaving the pasted text unsent in the composer. send_text must
# observe the composer and retry the submit until the text is gone, on both
# the claude composer (❯) and the codex composer (›).
composer_file="$TMP_BASE/pane.composer"
swallow_file="$TMP_BASE/pane.swallow"
for composer_prompt in '❯' '›'; do
  rm -f "$composer_file" "$composer_file.buffer"
  : > "$swallow_file"
  cm_before="$(awk '{ count += gsub(/C-m/, "") } END { print count + 0 }' "$TEAM_FAKE_TMUX_LOG")"
  PATH="$TMP_BASE/bin:$PATH" \
    TEAM_ROOT="$TMP_ROOT" \
    TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
    TEAM_DISABLE_NUDGE=0 \
    TEAM_FAKE_TMUX_HAS_SESSION=1 \
    TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
    TEAM_FAKE_TMUX_PROMPT="$composer_prompt" \
    TEAM_FAKE_TMUX_SWALLOW="$swallow_file" \
    "$TMP_ROOT/.agents/scripts/team_nudge.sh" lead >/dev/null
  [[ ! -f "$swallow_file" ]] \
    || fail "the swallowed submit was not consumed by a first Enter ($composer_prompt)"
  [[ ! -s "$composer_file" ]] \
    || fail "send_text left the composer holding unsent text ($composer_prompt)"
  cm_after="$(awk '{ count += gsub(/C-m/, "") } END { print count + 0 }' "$TEAM_FAKE_TMUX_LOG")"
  [[ "$((cm_after - cm_before))" -ge 2 ]] \
    || fail "send_text did not retry the swallowed submit ($composer_prompt)"
done

# Regression (transcript pollution): past user messages stay in the claude
# transcript as "❯ + regular space" lines, while the real composer renders as
# "❯ + non-breaking space". Matching the regular space made the wake detector
# treat the transcript as unsent input and silently starve the pane forever.
transcript_file="$TMP_BASE/pane.transcript"
printf '%s\n' "inbox lead" > "$transcript_file"
rm -f "$composer_file.buffer"
: > "$composer_file"
cm_before="$(awk '{ count += gsub(/C-m/, "") } END { print count + 0 }' "$TEAM_FAKE_TMUX_LOG")"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
  TEAM_FAKE_TMUX_TRANSCRIPT_FILE="$transcript_file" \
  "$TMP_ROOT/.agents/scripts/team_nudge.sh" lead >/dev/null 2> "$TMP_BASE/transcript-nudge.err"
if grep -q 'queued nudge' "$TMP_BASE/transcript-nudge.err"; then
  fail "a transcript line was mistaken for unsent input"
fi
[[ ! -s "$composer_file" ]] \
  || fail "nudge was not submitted on the transcript-polluted pane"
cm_after="$(awk '{ count += gsub(/C-m/, "") } END { print count + 0 }' "$TEAM_FAKE_TMUX_LOG")"
[[ "$((cm_after - cm_before))" -ge 1 ]] \
  || fail "nudge did not deliver on a transcript-polluted pane"
rm -f "$transcript_file"

# Regression (self-deadlock on own residue): a half-delivered injection can
# leave its own text sitting unsent in the composer. Treating that residue as
# human input makes every later nudge defer to it, so the pane starves on the
# machinery's own failure. The nudge must recognize repetitions of its own
# payload, skip the repaste (a repaste appends and doubles the injection when
# the composer's clear key is a no-op), and drive the residue to submission.
printf '%s\n' '{"id":"msg_residue","from":"manager","to":"lead","type":"request","requires_attention":"true","created_at":"2026-01-01T00:00:02Z","body":"residue"}' \
  >> "$TMP_ROOT/.agents/queue/inbox/lead.jsonl"
rm -f "$composer_file.buffer"
printf '%s\n' 'inbox leadinbox lead' > "$composer_file"
paste_count_before="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
cm_before="$(awk '{ count += gsub(/C-m/, "") } END { print count + 0 }' "$TEAM_FAKE_TMUX_LOG")"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
  "$TMP_ROOT/.agents/scripts/team_nudge.sh" lead > /dev/null 2> "$TMP_BASE/residue-nudge.err"
if grep -q 'queued nudge' "$TMP_BASE/residue-nudge.err"; then
  fail "the nudge deferred to its own stuck payload"
fi
[[ "$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)" == "$paste_count_before" ]] \
  || fail "own residue was repasted into a doubled injection"
[[ ! -s "$composer_file" ]] \
  || fail "own residue was not driven to submission"
cm_after="$(awk '{ count += gsub(/C-m/, "") } END { print count + 0 }' "$TEAM_FAKE_TMUX_LOG")"
[[ "$((cm_after - cm_before))" -ge 1 ]] \
  || fail "own residue was left without a submit"

# The residue exception must not weaken the human-draft protection: content
# that starts with the payload but continues as a human draft still defers.
# Drain the previous deferral's waiter first: a live waiter lock makes this
# nudge skip spawning its own waiter, and the old waiter exits after its own
# delivery, leaving the new deferral unwatched.
for _attempt in $(seq 1 100); do
  [[ -d "$TMP_ROOT/.agents/queue/state/locks/nudge-lead.lock" ]] || break
  /bin/sleep 0.1
done
[[ ! -d "$TMP_ROOT/.agents/queue/state/locks/nudge-lead.lock" ]] \
  || fail "input-test waiter did not release its lock before the draft test"
printf '%s\n' 'inbox lead のあとに人間の下書きが続いている' > "$composer_file"
paste_count_before="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_REAL_SLEEP=1 \
  TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
  "$TMP_ROOT/.agents/scripts/team_nudge.sh" lead > /dev/null 2> "$TMP_BASE/draft-nudge.err"
grep -q '^\[team\] queued nudge for lead; pane is busy or holds unsent input$' "$TMP_BASE/draft-nudge.err"
[[ "$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)" == "$paste_count_before" ]] \
  || fail "a human draft containing the payload prefix was clobbered"
: > "$composer_file"
for _attempt in $(seq 1 100); do
  paste_count_after="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
  [[ "$paste_count_after" -gt "$paste_count_before" ]] && break
  /bin/sleep 0.1
done
[[ "${paste_count_after:-0}" -gt "$paste_count_before" ]] \
  || fail "deferred nudge was not delivered after the draft was cleared"
for _attempt in $(seq 1 100); do
  [[ -d "$TMP_ROOT/.agents/queue/state/locks/nudge-lead.lock" ]] || break
  /bin/sleep 0.1
done
[[ ! -d "$TMP_ROOT/.agents/queue/state/locks/nudge-lead.lock" ]] \
  || fail "draft-test waiter did not release its lock"

# Regression (laggy paste echo): the composer can render a paste later than
# the first observation. Concluding a paste miss from a single read caused a
# repaste, which appends a second copy on composers whose clear key is a
# no-op. The sender must confirm over a window before deciding to repaste.
lag_file="$TMP_BASE/pane.paste-lag"
printf '%s\n' '3' > "$lag_file"
rm -f "$composer_file.buffer"
: > "$composer_file"
paste_count_before="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
  TEAM_FAKE_TMUX_PASTE_LAG="$lag_file" \
  bash -c 'source "$1/.agents/scripts/team_common.sh"; team_tmux_send_text %fake "inbox lead"' _ "$TMP_ROOT"
paste_count_after="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
[[ "$((paste_count_after - paste_count_before))" == "1" ]] \
  || fail "a laggy paste echo caused a repaste"
[[ ! -s "$composer_file" ]] \
  || fail "send_text left the laggy composer holding unsent text"
rm -f "$lag_file"

# Regression (history prediction): the composer can render a predicted command
# from input history as ghost text. It reads like typed input, but the cursor
# stays at the head of the content, while typed input moves the cursor along.
# Detection must read predictions as empty input and deliver by pasting over
# them, whatever the predicted text happens to be.
printf '%s\n' '{"id":"msg_prediction","from":"manager","to":"lead","type":"request","requires_attention":"true","created_at":"2026-01-01T00:00:03Z","body":"prediction"}' \
  >> "$TMP_ROOT/.agents/queue/inbox/lead.jsonl"
for predicted in 'inbox lead' '過去に打った長いdirectiveの再提示'; do
  rm -f "$composer_file.buffer"
  printf 'ghost:%s\n' "$predicted" > "$composer_file"
  paste_count_before="$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)"
  PATH="$TMP_BASE/bin:$PATH" \
    TEAM_ROOT="$TMP_ROOT" \
    TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
    TEAM_DISABLE_NUDGE=0 \
    TEAM_FAKE_TMUX_HAS_SESSION=1 \
    TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
    "$TMP_ROOT/.agents/scripts/team_nudge.sh" lead > /dev/null 2> "$TMP_BASE/prediction-nudge.err"
  if grep -q 'queued nudge' "$TMP_BASE/prediction-nudge.err"; then
    fail "a rendered prediction starved the nudge ($predicted)"
  fi
  [[ "$(grep -c '^paste-buffer ' "$TEAM_FAKE_TMUX_LOG" || true)" -gt "$paste_count_before" ]] \
    || fail "the nudge did not paste over the prediction ($predicted)"
  [[ ! -s "$composer_file" ]] \
    || fail "the nudge left the prediction composer unsent ($predicted)"
done

# Regression (invisible stall): a worker that closes its turn without leaving
# any pending message holds an obligation recorded only in task state. The
# watch must derive the obligated agent from the status and wake it.
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" bash -c \
  'source "$1/.agents/scripts/team_common.sh"; team_write_task_state T-STALL manager general-worker-1 general-reviewer-1 dispatched base-commit "" "" "" "" false false "" not_applicable ""' \
  _ "$TMP_ROOT"
cat > "$TMP_ROOT/.agents/queue/state/agents/general-worker-1.env" <<'ENV'
agent_id='general-worker-1'
role='general-worker'
cli='codex'
pane='%fake'
session='agent-team'
ENV
rm -f "$composer_file.buffer"
: > "$composer_file"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
grep -q '^set-buffer .*task T-STALL が status=dispatched のまま' "$TEAM_FAKE_TMUX_LOG" \
  || fail "team_watch did not wake the obligated worker of an invisible stall"

# When the task has a live pending message anywhere, the pending machinery owns
# the wake and the task reminder must stay silent (e.g. a checkpoint wait).
printf '%s\n' '{"id":"msg_stall_live","from":"general-worker-1","to":"general-reviewer-1","type":"supervision_checkpoint","task_id":"T-STALL","requires_attention":"true","created_at":"2026-01-01T00:00:00Z","body":"checkpoint"}' \
  >> "$TMP_ROOT/.agents/queue/inbox/general-reviewer-1.jsonl"
: > "$TEAM_FAKE_TMUX_LOG"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
if grep -q 'task T-STALL が status=' "$TEAM_FAKE_TMUX_LOG"; then
  fail "task reminder fired although a live pending message owns the wake"
fi
rm -f "$TMP_ROOT/.agents/queue/state/tasks/T-STALL.json" \
  "$TMP_ROOT/.agents/queue/state/agents/general-worker-1.env"
perl -0pi -e 's/^.*msg_stall_live.*\n//m' "$TMP_ROOT/.agents/queue/inbox/general-reviewer-1.jsonl"

# Regression (stall alarm): a stall class nobody anticipated leaves open work
# with no inbox movement, no task-state movement, and no busy pane. The watch
# cannot repair what it cannot classify, so it summons the Lead to diagnose.
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" bash -c \
  'source "$1/.agents/scripts/team_common.sh"; team_write_task_state T-STALL manager general-worker-1 general-reviewer-1 dispatched base-commit "" "" "" "" false false "" not_applicable ""' \
  _ "$TMP_ROOT"
find "$TMP_ROOT/.agents/queue/inbox" -name '*.jsonl' -exec touch -d '2020-01-01T00:00:00' {} +
find "$TMP_ROOT/.agents/queue/state/tasks" -name '*.json' -exec touch -d '2020-01-01T00:00:00' {} +
rm -f "$TMP_ROOT/.agents/queue/state/watch/stall-alarm.at"
: > "$TEAM_FAKE_TMUX_LOG"
rm -f "$composer_file.buffer"
: > "$composer_file"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
grep -q '^set-buffer .*停滞警報' "$TEAM_FAKE_TMUX_LOG" \
  || fail "the stall alarm did not summon the lead"

# A busy pane means somebody is working, so the same state must stay silent.
find "$TMP_ROOT/.agents/queue/inbox" -name '*.jsonl' -exec touch -d '2020-01-01T00:00:00' {} +
find "$TMP_ROOT/.agents/queue/state/tasks" -name '*.json' -exec touch -d '2020-01-01T00:00:00' {} +
rm -f "$TMP_ROOT/.agents/queue/state/watch/stall-alarm.at"
: > "$TEAM_FAKE_TMUX_LOG"
: > "$busy_file"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_TMUX_BUSY_FILE="$busy_file" \
  TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
grep -q '^set-buffer .*停滞警報' "$TEAM_FAKE_TMUX_LOG" \
  && fail "the stall alarm fired while a pane was busy"
rm "$busy_file"

# The firing sweep records its time; the cooldown gate reads this marker and
# keeps later sweeps silent for TEAM_STALL_ALARM_SECONDS.
find "$TMP_ROOT/.agents/queue/inbox" -name '*.jsonl' -exec touch -d '2020-01-01T00:00:00' {} +
find "$TMP_ROOT/.agents/queue/state/tasks" -name '*.json' -exec touch -d '2020-01-01T00:00:00' {} +
rm -f "$TMP_ROOT/.agents/queue/state/watch/stall-alarm.at"
: > "$composer_file"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_DISABLE_NUDGE=0 \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  TEAM_FAKE_TMUX_COMPOSER="$composer_file" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
[[ -s "$TMP_ROOT/.agents/queue/state/watch/stall-alarm.at" ]] \
  || fail "the stall alarm did not record its firing time for the cooldown"
rm -f "$TMP_ROOT/.agents/queue/state/tasks/T-STALL.json" \
  "$TMP_ROOT/.agents/queue/state/watch/stall-alarm.at"

# 根拠: T-071 Acceptanceは初見non-done taskのfirst_seen、strict 7200秒の発火、
# strict 3600秒のcooldown、busy時のlast_alarm保持、done時のmarker削除を要求する。
# 実物とfake: 実物team_watch --once、task state、marker、atomic sendを動かし、
# epoch、Strategist pane、tmux capture/sendだけをfakeにする。
# risk: mtime推測、blocked除外、閾値緩和、送信失敗時のalarm消費、done cleanupを検出する。
# 非対象: task内容分析、Strategist note、watcher置換、template publishはこのtestの責任外とする。
# 内部変更: marker helperや走査順が変わってもbytesとpane summonが同じなら成功する。
TEAM_FAKE_WATCH_EPOCH=10000
export TEAM_FAKE_WATCH_EPOCH
age_composer="$TMP_BASE/task-age.composer"
age_busy="$TMP_BASE/task-age.busy"
age_marker_dir="$TMP_ROOT/.agents/queue/state/watch/task-age"
age_marker="$age_marker_dir/T-AGE.marker"
mkdir -p "$age_marker_dir"
cat > "$TMP_ROOT/.agents/queue/state/agents/strategist.env" <<'ENV'
agent_id='strategist'
role='strategist'
cli='codex'
session='agent-team'
pane='%fake'
ENV
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" bash -c \
  'source "$1/.agents/scripts/team_common.sh"; team_write_task_state T-AGE manager general-worker-1 general-reviewer-1 blocked base "" "" "" "" false false "" not_applicable ""' \
  _ "$TMP_ROOT"
: > "$age_composer"
: > "$TEAM_FAKE_TMUX_LOG"
printf 'task_id=T-AGE\nfirst_seen=2000\nlast_alarm=0\n' > "$age_marker"
TEAM_DISABLE_NUDGE=1 PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 TEAM_FAKE_TMUX_COMPOSER="$age_composer" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
grep -q 'set-buffer .*長生きtask確認: T-AGEが開始から約2時間生存している。' "$TEAM_FAKE_TMUX_LOG" \
  || fail "old blocked task did not summon Strategist with exact hours"
grep -q '^last_alarm=10000$' "$age_marker" \
  || fail "successful summon did not publish last_alarm atomically"

# 初見taskはmarkerだけを作り、そのsweepで召喚しない。
rm -f "$age_marker"
: > "$TEAM_FAKE_TMUX_LOG"
TEAM_FAKE_WATCH_EPOCH=20000 TEAM_DISABLE_NUDGE=1 PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 TEAM_FAKE_TMUX_COMPOSER="$age_composer" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
grep -q '^first_seen=20000$' "$age_marker" || fail "first observation did not publish first_seen"
grep -q '^last_alarm=0$' "$age_marker" || fail "first observation alarmed"
if grep -q '長生きtask確認: T-AGE' "$TEAM_FAKE_TMUX_LOG"; then fail "first observation summoned"; fi

# 前回alarmから3600秒以内は再発火しない。strict greater-than境界を確認する。
printf 'task_id=T-AGE\nfirst_seen=10000\nlast_alarm=16400\n' > "$age_marker"
: > "$TEAM_FAKE_TMUX_LOG"
TEAM_FAKE_WATCH_EPOCH=20000 TEAM_DISABLE_NUDGE=1 PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 TEAM_FAKE_TMUX_COMPOSER="$age_composer" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
if grep -q '長生きtask確認: T-AGE' "$TEAM_FAKE_TMUX_LOG"; then fail "cooldown fired at 3600 seconds"; fi
grep -q '^last_alarm=16400$' "$age_marker" || fail "cooldown changed last_alarm"

# busy paneは送信とlast_alarmを消費せず、次周期のidleで一度だけ配送する。
printf 'task_id=T-AGE\nfirst_seen=10000\nlast_alarm=0\n' > "$age_marker"
: > "$age_busy"; : > "$TEAM_FAKE_TMUX_LOG"
TEAM_FAKE_WATCH_EPOCH=30000 TEAM_DISABLE_NUDGE=1 PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 TEAM_FAKE_TMUX_COMPOSER="$age_composer" TEAM_FAKE_TMUX_BUSY_FILE="$age_busy" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
if grep -q '長生きtask確認: T-AGE' "$TEAM_FAKE_TMUX_LOG"; then fail "busy pane received summon"; fi
grep -q '^last_alarm=0$' "$age_marker" || fail "busy pane consumed last_alarm"
rm "$age_busy"; : > "$TEAM_FAKE_TMUX_LOG"
TEAM_FAKE_WATCH_EPOCH=30000 TEAM_DISABLE_NUDGE=1 PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 TEAM_FAKE_TMUX_COMPOSER="$age_composer" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
[[ "$(grep -c '長生きtask確認: T-AGE' "$TEAM_FAKE_TMUX_LOG" || true)" -eq 1 ]] || fail "idle pane did not receive summon"
grep -q '^last_alarm=30000$' "$age_marker" || fail "idle summon did not publish last_alarm"

# invalid markerはwarningでfail closedし、done遷移だけはexact markerを掃除する。
printf 'task_id=T-AGE\nfirst_seen=not-decimal\nlast_alarm=0\n' > "$age_marker"
: > "$TEAM_FAKE_TMUX_LOG"
TEAM_FAKE_WATCH_EPOCH=40000 TEAM_DISABLE_NUDGE=1 PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 TEAM_FAKE_TMUX_COMPOSER="$age_composer" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once 2> "$TMP_BASE/task-age-invalid.err"
grep -q 'invalid task-age marker; suppressing alarm: T-AGE' "$TMP_BASE/task-age-invalid.err" || fail "invalid marker did not fail closed"
if grep -q '長生きtask確認: T-AGE' "$TEAM_FAKE_TMUX_LOG"; then fail "invalid marker summoned"; fi
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" bash -c \
  'source "$1/.agents/scripts/team_common.sh"; team_write_task_state T-AGE manager general-worker-1 general-reviewer-1 done base "" "" "" "" false false "" not_applicable ""' \
  _ "$TMP_ROOT"
TEAM_FAKE_WATCH_EPOCH=40000 TEAM_DISABLE_NUDGE=1 PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 TEAM_FAKE_TMUX_COMPOSER="$age_composer" \
  "$TMP_ROOT/.agents/scripts/team_watch.sh" --once
[[ ! -e "$age_marker" ]] || fail "done task did not remove marker"

# Make wrappers preserve multiline and quoted message bodies.
message_body="$TMP_BASE/message.md"
printf '%s\n' 'line one' 'requires-python >=3.14 "quoted"' > "$message_body"
message_output="$(
  TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 TEAM_AGENT_ID=lead \
    make -s -C "$TMP_ROOT" team-send TO=manager TYPE=request BODY_FILE="$message_body"
)"
message_id="$(printf '%s\n' "$message_output" | sed -n 's/^message_id=//p')"
[[ -n "$message_id" ]] || fail "make team-send returned no message id"
raw_manager_inbox="$(team "$TMP_ROOT/.agents/scripts/team_inbox.sh" manager --raw)"
grep -q 'line one\\nrequires-python >=3.14 \\"quoted\\"' <<<"$raw_manager_inbox"
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 TEAM_AGENT_ID=manager \
  make -s -C "$TMP_ROOT" team-reply IN_REPLY_TO="$message_id" TYPE=note BODY="Recorded." >/dev/null

# A plain note is record-only and never wakes the recipient. Milestone reports
# need REQUIRES_ATTENTION=1 so the note becomes pending and gets a nudge.
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 TEAM_AGENT_ID=lead \
  make -s -C "$TMP_ROOT" team-send TO=manager TYPE=note BODY="Phase milestone done" REQUIRES_ATTENTION=1 >/dev/null
raw_manager_inbox="$(team "$TMP_ROOT/.agents/scripts/team_inbox.sh" manager --raw)"
grep -q '"type":"note".*"requires_attention":"true".*Phase milestone done' <<<"$raw_manager_inbox" \
  || fail "REQUIRES_ATTENTION=1 did not mark the note as requiring attention"

# General implementation lifecycle and fixed-pair availability.
cp "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-GENERAL.md"
perl -0pi -e 's/T-XXX/T-GENERAL/g; s#\x60path/to/file\x60#\x60general-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-GENERAL.md"
team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-GENERAL >/dev/null
general_state="$(team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --owner manager T-GENERAL 2> "$TMP_BASE/dispatch-next.err")"
grep -q '"worker":"general-worker-1"' "$general_state"
# Dispatch is where the batch habit and forgotten research pre-orders happen,
# so its stderr carries the option reminder while stdout stays a state path.
grep -q 'next: 並列にdispatchできるtask' "$TMP_BASE/dispatch-next.err" \
  || fail "dispatch output did not carry the parallel/research reminder"
grep -q '"supervisor":"general-reviewer-1"' "$general_state"
grep -q '^Supervisor: general-reviewer-1$' "$TMP_ROOT/.agents/queue/tasks/T-GENERAL.md"

# A narrow allowed path inside a broad protection is the natural exception
# contract ("this one file is OK, the rest of the tree is frozen") and passes.
cp "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-CONFLICT.md"
perl -0pi -e 's/T-XXX/T-CONFLICT/g; s#\x60path/to/file\x60#\x60conflict-output.txt\x60#; s#- \x60\.agents/state/STATE\.md\x60#- \x60*.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-CONFLICT.md"
team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-CONFLICT >/dev/null \
  || fail "task lint rejected a narrow allowed path inside a broad protection"

# Claiming the very same boundary from both sections stays a contradiction.
perl -0pi -e 's#- \x60\*\.txt\x60#- \x60conflict-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-CONFLICT.md"
if team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-CONFLICT \
  > /dev/null 2> "$TMP_BASE/path-conflict.err"; then
  fail "task lint accepted the same boundary as allowed and protected"
fi
grep -q '^error: task path ownership patterns conflict: conflict-output.txt and conflict-output.txt$' "$TMP_BASE/path-conflict.err"

cp "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-BUSY.md"
perl -0pi -e 's/T-XXX/T-BUSY/g; s#\x60path/to/file\x60#\x60busy-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-BUSY.md"
if team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --owner manager T-BUSY > /dev/null 2> "$TMP_BASE/busy.err"; then
  fail "dispatch accepted a busy fixed pair"
fi
grep -q '^error: implementation worker is busy: general-worker-1$' "$TMP_BASE/busy.err"

checkpoint_output="$(
  team "$TMP_ROOT/.agents/scripts/team_send.sh" \
    --from general-worker-1 --type supervision_checkpoint --task T-GENERAL \
    general-reviewer-1 "Parser boundary is ready."
)"
checkpoint_id="$(printf '%s\n' "$checkpoint_output" | sed -n 's/^message_id=//p')"
# Regression (read-then-idle): a checkpoint demands a response, so reading it
# must NOT mark it processed. Otherwise a reviewer that reads and idles drops
# the obligation from the pending state and team_watch can never recover it.
team "$TMP_ROOT/.agents/scripts/team_inbox.sh" general-reviewer-1 >/dev/null
[[ ! -f "$TMP_ROOT/.agents/queue/state/processed/general-reviewer-1/$checkpoint_id" ]] \
  || fail "supervision checkpoint was auto-processed on read"

strategy_request_output="$(
  team "$TMP_ROOT/.agents/scripts/team_send.sh" \
    --from general-reviewer-1 --task T-GENERAL strategist "Compare the parser boundary options."
)"
grep -q '^cc_to=manager$' <<<"$strategy_request_output"
# A task-scoped responding action processes the checkpoint through the
# existing send-time mark; no separate acknowledgement mechanism exists.
[[ -f "$TMP_ROOT/.agents/queue/state/processed/general-reviewer-1/$checkpoint_id" ]] \
  || fail "the reviewer's task-scoped action did not process the checkpoint"
strategy_result_output="$(
  team "$TMP_ROOT/.agents/scripts/team_send.sh" \
    --from strategist --type strategy_result --task T-GENERAL \
    general-reviewer-1 "Use the narrow parser boundary."
)"
grep -q '^cc_to=manager$' <<<"$strategy_result_output"

printf '%s\n' "concurrent change" > "$TMP_ROOT/concurrent-output.txt"
git -C "$TMP_ROOT" add concurrent-output.txt
git -C "$TMP_ROOT" commit -qm "Concurrent task result"
concurrent_commit="$(git -C "$TMP_ROOT" rev-parse HEAD)"

printf '%s\n' "general change" > "$TMP_ROOT/general-output.txt"
# The same boundary claimed by both sections fails before any commit is made.
perl -0pi -e 's/(## Do not modify\n\n)/$1- `general-output.txt`\n/' "$TMP_ROOT/.agents/queue/tasks/T-GENERAL.md"
head_before_conflict="$(git -C "$TMP_ROOT" rev-parse HEAD)"
if TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 TEAM_AGENT_ID=general-worker-1 \
  make -s -C "$TMP_ROOT" task-commit TASK=T-GENERAL MESSAGE="add output" \
  > /dev/null 2> "$TMP_BASE/commit-path-conflict.err"; then
  fail "task commit accepted the same boundary as allowed and protected"
fi
grep -q '^error: task path ownership conflict: general-output.txt and general-output.txt are the same file$' "$TMP_BASE/commit-path-conflict.err"
[[ "$(git -C "$TMP_ROOT" rev-parse HEAD)" == "$head_before_conflict" ]] \
  || fail "task commit created a partial commit after path validation failed"
# Keep a broad protection around the narrow allowed path: the later successful
# commits must select general-output.txt as the exception that wins.
perl -0pi -e 's/(## Do not modify\n\n)- `general-output\.txt`\n/$1- `*.txt`\n/' "$TMP_ROOT/.agents/queue/tasks/T-GENERAL.md"

printf '%s\n' "staged elsewhere" > "$TMP_ROOT/staged-elsewhere.txt"
git -C "$TMP_ROOT" add staged-elsewhere.txt
if TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 TEAM_AGENT_ID=general-worker-1 \
  make -s -C "$TMP_ROOT" task-commit TASK=T-GENERAL MESSAGE="add output" \
  > /dev/null 2> "$TMP_BASE/staged-elsewhere.err"; then
  fail "task commit accepted staged changes outside the task"
fi
grep -q '^error: Git index contains changes outside task T-GENERAL$' "$TMP_BASE/staged-elsewhere.err"
git -C "$TMP_ROOT" restore --staged staged-elsewhere.txt
rm "$TMP_ROOT/staged-elsewhere.txt"

# A SIGKILLed lock holder cannot run its trap, so its lock dir stays behind.
# A lock whose recorded holder pid is dead must be reclaimed, not waited on.
/bin/sleep 0 & stale_lock_pid=$!
wait "$stale_lock_pid" 2>/dev/null || true
mkdir -p "$TMP_ROOT/.agents/queue/state/locks/git-commit.lock"
printf '%s\n' "$stale_lock_pid" > "$TMP_ROOT/.agents/queue/state/locks/git-commit.lock/pid"

general_commit_output="$(
  TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 TEAM_AGENT_ID=general-worker-1 \
    make -s -C "$TMP_ROOT" task-commit TASK=T-GENERAL MESSAGE="add output"
)"
general_commit="$(printf '%s\n' "$general_commit_output" | sed -n 's/^commit=//p')"
[[ -n "$general_commit" ]] || fail "task commit returned no commit hash"
git -C "$TMP_ROOT" show -s --format=%B "$general_commit" | grep -q '^Agent-Task: T-GENERAL$'
[[ "$(git -C "$TMP_ROOT" show --format= --name-only "$general_commit")" == "general-output.txt" ]] \
  || fail "task commit included paths outside the task"

printf '%s\n' "uncommitted task change" > "$TMP_ROOT/general-output.txt"
if as_agent general-worker-1 "$TMP_ROOT/.agents/scripts/team_report.sh" T-GENERAL needs_supervision \
  > /dev/null 2> "$TMP_BASE/dirty-task.err"; then
  fail "report accepted uncommitted task-owned changes"
fi
grep -q '^error: task-owned changes are not committed: T-GENERAL$' "$TMP_BASE/dirty-task.err"
git -C "$TMP_ROOT" restore general-output.txt

general_base="$(state_field task T-GENERAL base_commit)"
general_report="$(as_agent general-worker-1 "$TMP_ROOT/.agents/scripts/team_report.sh" T-GENERAL needs_supervision)"
general_commits="$(state_field task T-GENERAL task_commits)"
[[ "$general_commits" == "$general_commit" ]] || fail "report did not isolate the task commit"
[[ "$general_commits" != *"$concurrent_commit"* ]] || fail "report included a concurrent commit"

# Declaring blocked is where prose-waiting starts, so the blocked report must
# remind the worker to convert the blocker into a pending-creating message.
as_agent general-worker-1 "$TMP_ROOT/.agents/scripts/team_report.sh" T-GENERAL blocked \
  > /dev/null 2> "$TMP_BASE/blocked-next.err"
grep -q 'next: blockerを解く相手へ' "$TMP_BASE/blocked-next.err" \
  || fail "blocked report did not carry the pending-message reminder"
as_agent general-worker-1 "$TMP_ROOT/.agents/scripts/team_report.sh" T-GENERAL needs_supervision >/dev/null

printf '%s\n' "general change refined" > "$TMP_ROOT/general-output.txt"
general_fix_output="$(as_agent general-worker-1 "$TMP_ROOT/.agents/scripts/team_task_commit.sh" T-GENERAL "refine output")"
general_fix_commit="$(printf '%s\n' "$general_fix_output" | sed -n 's/^commit=//p')"
if team "$TMP_ROOT/.agents/scripts/team_send.sh" \
  --from general-worker-1 --type ready_for_supervision --task T-GENERAL \
  general-reviewer-1 "Report is ready." > /dev/null 2> "$TMP_BASE/stale-report.err"; then
  fail "ready_for_supervision accepted a stale report"
fi
grep -q '^error: task report is stale: T-GENERAL$' "$TMP_BASE/stale-report.err"
general_report="$(as_agent general-worker-1 "$TMP_ROOT/.agents/scripts/team_report.sh" T-GENERAL needs_supervision)"
general_commits="$general_commit $general_fix_commit"
[[ "$(state_field task T-GENERAL task_commits)" == "$general_commits" ]] || fail "updated report lost task commits"
cat > "$general_report" <<REPORT
# Report: T-GENERAL by general-worker-1

Status: needs_supervision
Supervisor: general-reviewer-1
Base commit: $general_base
Task commits: $general_commits
Supervision artifact: none
Supervision decision: none
Done recommendation: false
Architecture required: false
Architecture: none
Direction status: not_applicable
Direction artifact: none

## Summary

- Added the requested output.

## Files changed

- general-output.txt

## Commits

- $general_commit T-GENERAL: add output
- $general_fix_commit T-GENERAL: refine output

## Verification

- Content assertion passed.

## Post-change

- make post-change passed.

## Smoke

- make smoke passed.

## Supervision

- Checkpoint shared with general-reviewer-1.

## Strategy And Architecture

- None required.

## Blockers And Questions

- None.

## Memory Proposals

- None.
REPORT
team "$TMP_ROOT/.agents/scripts/team_send.sh" \
  --from general-worker-1 --type ready_for_supervision --task T-GENERAL \
  general-reviewer-1 "Report is ready." >/dev/null
general_reviewer_raw="$(team "$TMP_ROOT/.agents/scripts/team_inbox.sh" general-reviewer-1 --raw)"
grep -q "Task commits: $general_commits" <<<"$general_reviewer_raw"
[[ "$general_reviewer_raw" != *"Task commits: $concurrent_commit"* ]] || fail "review entrypoint included a concurrent commit"

general_review="$TMP_ROOT/.agents/queue/reviews/T-GENERAL_general-reviewer-1.md"
cat > "$general_review" <<REVIEW
# Review: T-GENERAL

Decision: OK
Done recommendation: yes
Task: .agents/queue/tasks/T-GENERAL.md
Worker: general-worker-1
Report: .agents/queue/reports/T-GENERAL_general-worker-1.md
Base commit: $general_base
Task commits: $general_commits

## Summary

- Contract is satisfied.

## Findings

- No blocking findings.

## Evidence Reviewed

- Task, commit, report, post-change, and smoke evidence.

## Coordination

- Checkpoint was reviewed.
REVIEW
as_agent general-reviewer-1 "$TMP_ROOT/.agents/scripts/team_supervision_report.sh" T-GENERAL OK >/dev/null
grep -q '"status":"supervision_ok"' "$general_state"
team "$TMP_ROOT/.agents/scripts/team_state_update.sh" update T-GENERAL done >/dev/null
grep -q '"status":"done"' "$general_state"

# Hard task dispatch uses the general task contract and its fixed reviewer.
cp "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-HARD.md"
perl -0pi -e 's/T-XXX/T-HARD/g; s/Worker: general-worker-1/Worker: hard-task-worker-1/; s#\x60path/to/file\x60#\x60hard-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-HARD.md"
team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-HARD >/dev/null
hard_state="$(team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --owner manager T-HARD)"
grep -q '"worker":"hard-task-worker-1"' "$hard_state"
grep -q '"supervisor":"general-reviewer-4"' "$hard_state"
grep -q '^Supervisor: general-reviewer-4$' "$TMP_ROOT/.agents/queue/tasks/T-HARD.md"

hard_checkpoint_output="$(
  team "$TMP_ROOT/.agents/scripts/team_send.sh" \
    --from hard-task-worker-1 --type supervision_checkpoint --task T-HARD \
    general-reviewer-4 "The decisive hypothesis is confirmed."
)"
hard_checkpoint_id="$(printf '%s\n' "$hard_checkpoint_output" | sed -n 's/^message_id=//p')"
hard_reviewer_inbox="$(team "$TMP_ROOT/.agents/scripts/team_inbox.sh" general-reviewer-4)"
grep -q "$hard_checkpoint_id" <<<"$hard_reviewer_inbox" \
  || fail "hard task checkpoint did not reach its fixed reviewer"
# Reading alone must not process a checkpoint; the explicit MARK is the
# no-response acknowledgement path.
[[ ! -f "$TMP_ROOT/.agents/queue/state/processed/general-reviewer-4/$hard_checkpoint_id" ]] \
  || fail "hard task checkpoint was auto-processed on read"
team "$TMP_ROOT/.agents/scripts/team_inbox.sh" general-reviewer-4 --mark "$hard_checkpoint_id" >/dev/null
[[ -f "$TMP_ROOT/.agents/queue/state/processed/general-reviewer-4/$hard_checkpoint_id" ]] \
  || fail "explicit MARK did not process the checkpoint"

# Frontend direction and critic lifecycle.
cp "$TMP_ROOT/.agents/queue/tasks/FRONTEND_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-FRONTEND.md"
perl -0pi -e 's/T-XXX/T-FRONTEND/g; s#\x60path/to/frontend/file\x60#\x60frontend-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-FRONTEND.md"
team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-FRONTEND >/dev/null
frontend_state="$(team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --owner manager T-FRONTEND)"
grep -q '"direction_status":"pending"' "$frontend_state"

if as_agent frontend-worker-1 "$TMP_ROOT/.agents/scripts/team_report.sh" T-FRONTEND needs_supervision \
  > /dev/null 2> "$TMP_BASE/direction-pending.err"; then
  fail "frontend report accepted unresolved view direction"
fi
grep -q '^error: frontend direction is not resolved: T-FRONTEND$' "$TMP_BASE/direction-pending.err"

team "$TMP_ROOT/.agents/scripts/team_send.sh" \
  --from frontend-worker-1 --type view_direction_ready --task T-FRONTEND \
  frontend-critic-1 "Direction proposal is ready." >/dev/null
direction_file="$TMP_ROOT/.agents/queue/direction-critiques/T-FRONTEND_frontend-critic-1.md"
cat > "$direction_file" <<'DIRECTION'
# Direction Critique: T-FRONTEND

Decision: PROCEED
Task: .agents/queue/tasks/T-FRONTEND.md
Worker: frontend-worker-1

## Direction Reviewed

- Primary content hierarchy and responsive behavior.

## Critique

- Proceed with the proposed hierarchy and verify the narrow viewport.
DIRECTION
as_agent frontend-critic-1 "$TMP_ROOT/.agents/scripts/team_direction_report.sh" T-FRONTEND PROCEED >/dev/null
grep -q '"direction_status":"proceed"' "$frontend_state"

printf '%s\n' "frontend change" > "$TMP_ROOT/frontend-output.txt"
frontend_commit_output="$(as_agent frontend-worker-1 "$TMP_ROOT/.agents/scripts/team_task_commit.sh" T-FRONTEND "add output")"
frontend_commit="$(printf '%s\n' "$frontend_commit_output" | sed -n 's/^commit=//p')"
frontend_base="$(state_field task T-FRONTEND base_commit)"
frontend_report="$(as_agent frontend-worker-1 "$TMP_ROOT/.agents/scripts/team_report.sh" T-FRONTEND needs_supervision)"
mkdir -p "$TMP_ROOT/.agents/queue/visuals/T-FRONTEND"
printf '%s\n' "representative visual evidence" > "$TMP_ROOT/.agents/queue/visuals/T-FRONTEND/desktop.txt"
cat > "$frontend_report" <<REPORT
# Report: T-FRONTEND by frontend-worker-1

Status: needs_supervision
Supervisor: frontend-critic-1
Base commit: $frontend_base
Task commits: $frontend_commit
Supervision artifact: none
Supervision decision: none
Done recommendation: false
Architecture required: false
Architecture: none
Direction status: proceed
Direction artifact: .agents/queue/direction-critiques/T-FRONTEND_frontend-critic-1.md

## Summary

- Added the frontend output.

## Files changed

- frontend-output.txt

## Commits

- $frontend_commit T-FRONTEND: add output

## Verification

- Target state was rendered.

## Post-change

- make post-change passed.

## Smoke

- make smoke passed.

## Supervision

- Direction critique was applied.

## Strategy And Architecture

- None required.

## Visual Evidence

- .agents/queue/visuals/T-FRONTEND/desktop.txt

## Blockers And Questions

- None.

## Memory Proposals

- None.
REPORT

frontend_critique="$TMP_ROOT/.agents/queue/critiques/T-FRONTEND_frontend-critic-1.md"
cat > "$frontend_critique" <<CRITIQUE
# Frontend Critique: T-FRONTEND

Decision: OK
Done recommendation: yes
Task: .agents/queue/tasks/T-FRONTEND.md
Worker: frontend-worker-1
Report: .agents/queue/reports/T-FRONTEND_frontend-worker-1.md
Base commit: $frontend_base
Task commits: $frontend_commit

## Summary

- The rendered result satisfies the task.

## Findings

- No blocking findings.

## Evidence Reviewed

- Task, diff, report, post-change, and smoke evidence.

## Visual Evidence Reviewed

- Desktop evidence and the narrow target state.

## Coordination

- Direction was approved before implementation.
CRITIQUE
as_agent frontend-critic-1 "$TMP_ROOT/.agents/scripts/team_supervision_report.sh" T-FRONTEND OK >/dev/null
team "$TMP_ROOT/.agents/scripts/team_state_update.sh" update T-FRONTEND done >/dev/null
grep -q '"status":"done"' "$frontend_state"

# Express lane: lint guards, lead-only dispatch, exec launch, fix loop, lead done.
cp "$TMP_ROOT/.agents/queue/tasks/EXPRESS_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-E-001.md"
perl -0pi -e 's/T-E-XXX/T-E-001/g; s#\x60path/to/file\x60#\x60express-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-E-001.md"
team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-E-001 >/dev/null

cp "$TMP_ROOT/.agents/queue/tasks/EXPRESS_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-E-BAD.md"
perl -0pi -e 's/T-E-XXX/T-E-BAD/g; s#\x60path/to/file\x60#\x60.agents/scripts/team_send.sh\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-E-BAD.md"
if team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-E-BAD \
  > /dev/null 2> "$TMP_BASE/express-governance.err"; then
  fail "express lint accepted a governance path"
fi
grep -q 'express task cannot own a governance path' "$TMP_BASE/express-governance.err"

if team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --owner manager T-E-001 \
  > /dev/null 2> "$TMP_BASE/express-manager.err"; then
  fail "express dispatch accepted the manager as dispatcher"
fi
grep -q 'express dispatch sender is not lead' "$TMP_BASE/express-manager.err"

express_state="$(team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --owner lead T-E-001)"
grep -q '"worker":"express-worker-1"' "$express_state"
grep -q '"supervisor":""' "$express_state"
grep -q '"owner":"lead"' "$express_state"
for _attempt in $(seq 1 50); do
  grep -q 'T-E-001' "$TEAM_FAKE_CODEX_LOG" 2>/dev/null && break
  /bin/sleep 0.1
done
grep -q 'T-E-001' "$TEAM_FAKE_CODEX_LOG" || fail "express exec run did not receive the task id"

cp "$TMP_ROOT/.agents/queue/tasks/EXPRESS_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-E-002.md"
perl -0pi -e 's/T-E-XXX/T-E-002/g; s#\x60path/to/file\x60#\x60second-express-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-E-002.md"
if team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --owner lead T-E-002 \
  > /dev/null 2> "$TMP_BASE/express-flight.err"; then
  fail "express dispatch accepted a second in-flight task"
fi
grep -q 'another express task is in flight' "$TMP_BASE/express-flight.err"

printf '%s\n' "express change" > "$TMP_ROOT/express-output.txt"
express_commit_output="$(as_agent express-worker-1 "$TMP_ROOT/.agents/scripts/team_task_commit.sh" T-E-001 "add express output")"
express_commit="$(printf '%s\n' "$express_commit_output" | sed -n 's/^commit=//p')"
[[ -n "$express_commit" ]] || fail "express task commit returned no commit hash"
express_base="$(state_field task T-E-001 base_commit)"
express_report="$(as_agent express-worker-1 "$TMP_ROOT/.agents/scripts/team_report.sh" T-E-001 ready_for_lead)"
grep -q '"status":"ready_for_lead"' "$express_state"
if grep -q '^## Supervision$' "$express_report"; then
  fail "express report skeleton included a supervision section"
fi

write_express_report() {
  local commits="$1"
  local commit_lines="$2"
  cat > "$express_report" <<REPORT
# Report: T-E-001 by express-worker-1

Status: ready_for_lead
Base commit: $express_base
Task commits: $commits

## Summary

- Added the express output.

## Files changed

- express-output.txt

## Commits

$commit_lines

## Verification

- Content assertion passed.

## Post-change

- make post-change passed.

## Smoke

- make smoke passed.

## Blockers And Questions

- None.

## Memory Proposals

- None.
REPORT
}

write_express_report "$express_commit" "- $express_commit T-E-001: add express output"
team "$TMP_ROOT/.agents/scripts/team_send.sh" \
  --from express-worker-1 --type express_ready --task T-E-001 \
  lead "Express task is ready." >/dev/null
lead_inbox_raw="$(team "$TMP_ROOT/.agents/scripts/team_inbox.sh" lead --raw)"
grep -q "Task commits: $express_commit" <<<"$lead_inbox_raw"

# Regression (2026-07-18 T-E-001): express fix must validate the resumable
# session before any shared-state mutation. A failed fix used to leave the
# status regressed to dispatched, which both state-update and a retried
# express-fix then rejected.
express_exec_env="$TMP_ROOT/.agents/queue/state/exec/express-worker-1.env"
for _attempt in $(seq 1 50); do
  grep -q '^session_id=' "$express_exec_env" 2>/dev/null && break
  /bin/sleep 0.1
done
grep -q '^session_id=' "$express_exec_env" \
  || fail "express exec did not record its session id before the fix test"
cp "$express_exec_env" "$TMP_BASE/express-exec-env.backup"
grep -v '^session_id=' "$TMP_BASE/express-exec-env.backup" > "$express_exec_env"
if as_agent lead "$TMP_ROOT/.agents/scripts/team_express_fix.sh" T-E-001 "Refine the express output." \
  > /dev/null 2> "$TMP_BASE/express-fix-no-session.err"; then
  fail "express fix accepted a run with no recorded session id"
fi
grep -q 'no session to resume' "$TMP_BASE/express-fix-no-session.err"
[[ "$(state_field task T-E-001 status)" == "ready_for_lead" ]] \
  || fail "failed express fix (no session) changed the task status"

# While the previous exec process is still alive, the fix must refuse cleanly
# instead of mutating state and failing on the missing session id.
grep -v '^pid=' "$TMP_BASE/express-exec-env.backup" > "$express_exec_env"
printf "pid='%s'\n" "$$" >> "$express_exec_env"
if as_agent lead "$TMP_ROOT/.agents/scripts/team_express_fix.sh" T-E-001 "Refine the express output." \
  > /dev/null 2> "$TMP_BASE/express-fix-running.err"; then
  fail "express fix accepted a still-running exec"
fi
grep -q 'has not finished its exec run' "$TMP_BASE/express-fix-running.err"
[[ "$(state_field task T-E-001 status)" == "ready_for_lead" ]] \
  || fail "refused express fix (running exec) changed the task status"

cp "$TMP_BASE/express-exec-env.backup" "$express_exec_env"
lead_inbox_raw="$(team "$TMP_ROOT/.agents/scripts/team_inbox.sh" lead --raw)"
grep -q "Task commits: $express_commit" <<<"$lead_inbox_raw" \
  || fail "failed express fix consumed the pending express_ready report"

as_agent lead "$TMP_ROOT/.agents/scripts/team_express_fix.sh" T-E-001 "Refine the express output." >/dev/null
[[ "$(state_field task T-E-001 status)" == "dispatched" ]] || fail "express fix did not return the task to dispatched"
for _attempt in $(seq 1 50); do
  grep -q 'codex exec resume 00000000-0000-4000-8000-000000000000' "$TEAM_FAKE_CODEX_LOG" 2>/dev/null && break
  /bin/sleep 0.1
done
grep -q 'codex exec resume 00000000-0000-4000-8000-000000000000' "$TEAM_FAKE_CODEX_LOG" \
  || fail "express fix did not resume the recorded codex session"
printf '%s\n' "express change refined" > "$TMP_ROOT/express-output.txt"
express_fix_output="$(as_agent express-worker-1 "$TMP_ROOT/.agents/scripts/team_task_commit.sh" T-E-001 "refine express output")"
express_fix_commit="$(printf '%s\n' "$express_fix_output" | sed -n 's/^commit=//p')"
express_report="$(as_agent express-worker-1 "$TMP_ROOT/.agents/scripts/team_report.sh" T-E-001 ready_for_lead)"
write_express_report "$express_commit $express_fix_commit" "- $express_commit T-E-001: add express output
- $express_fix_commit T-E-001: refine express output"
team "$TMP_ROOT/.agents/scripts/team_send.sh" \
  --from express-worker-1 --type express_ready --task T-E-001 \
  lead "Fix feedback is applied." >/dev/null
# The dispatch barrier habit forms at the moment done is written, so the done
# output must carry the re-evaluation reminder for the owner (on stderr, so
# stdout stays a machine-readable state file path).
express_done_output="$(team "$TMP_ROOT/.agents/scripts/team_state_update.sh" update T-E-001 done 2>&1)"
grep -q 'next: このdoneで依存が解けたtask' <<<"$express_done_output" \
  || fail "done output did not remind the owner to re-evaluate dispatchable tasks"
grep -q '"status":"done"' "$express_state"

# External-repo task: when every allowed path lives outside the team root,
# the report accepts zero task commits and records them as none, so no
# ceremony evidence file in the team repository is needed.
external_dir="$TMP_BASE/external-repo"
mkdir -p "$external_dir"
cp "$TMP_ROOT/.agents/queue/tasks/EXPRESS_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-E-003.md"
perl -0pi -e 's/T-E-XXX/T-E-003/g; s#\x60path/to/file\x60#\x60'"$external_dir"'/**\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-E-003.md"
team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --owner lead T-E-003 >/dev/null
printf '%s\n' "external work" > "$external_dir/notes.md"
external_report="$(as_agent express-worker-1 "$TMP_ROOT/.agents/scripts/team_report.sh" T-E-003 ready_for_lead)"
grep -q '^Task commits: none$' "$external_report" \
  || fail "external task report did not record its commits as none"
grep -q 'none (all allowed paths are outside the team repository)' "$external_report" \
  || fail "external task report commits section is missing the none marker"
external_base="$(state_field task T-E-003 base_commit)"
cat > "$external_report" <<REPORT
# Report: T-E-003 by express-worker-1

Status: ready_for_lead
Base commit: $external_base
Task commits: none

## Summary

- Reorganized the external knowledge base.

## Files changed

- $external_dir/notes.md

## Commits

- none (all allowed paths are outside the team repository)

## Verification

- External content assertion passed.

## Post-change

- make post-change passed.

## Smoke

- make smoke passed.

## Blockers And Questions

- None.

## Memory Proposals

- None.
REPORT
team "$TMP_ROOT/.agents/scripts/team_state_update.sh" update T-E-003 done >/dev/null
[[ "$(state_field task T-E-003 status)" == "done" ]] \
  || fail "external express task did not reach done without a team-root commit"

if team "$TMP_ROOT/.agents/scripts/team_state_update.sh" update T-GENERAL ready_for_lead \
  > /dev/null 2> "$TMP_BASE/express-status.err"; then
  fail "normal task accepted the express status"
fi
grep -q 'normal task cannot use express status' "$TMP_BASE/express-status.err"

# Research pool FIFO, exec launch, completion, and cancellation.
research_ids=()
for index in 1 2 3 4 5; do
  research_ids+=("$(request_research lead "Research question $index")")
done
[[ "$(state_field research "${research_ids[0]}" worker)" == "research-worker-1" ]] || fail "first research request did not use worker 1"
[[ "$(state_field research "${research_ids[3]}" worker)" == "research-worker-4" ]] || fail "fourth research request did not use worker 4"
[[ "$(state_field research "${research_ids[4]}" status)" == "queued" ]] || fail "fifth research request was not queued"

first_request="${research_ids[0]}"
first_assignment="$(state_field research "$first_request" request_message_id)"
for _attempt in $(seq 1 50); do
  grep -q "$first_request" "$TEAM_FAKE_CODEX_LOG" 2>/dev/null && break
  /bin/sleep 0.1
done
grep -q "$first_request" "$TEAM_FAKE_CODEX_LOG" || fail "research exec run did not receive the request id"
grep -q 'tools.web_search=true' "$TEAM_FAKE_CODEX_LOG" || fail "research exec run did not enable Web search"
grep -q -- '--model gpt-5.6-luna' "$TEAM_FAKE_CODEX_LOG" || fail "research exec run did not use the configured model"
[[ -f "$TMP_ROOT/.agents/queue/state/exec/research-worker-1.env" ]] || fail "research exec run left no state"

first_artifact_rel="$(state_field research "$first_request" artifact)"
cat >> "$TMP_ROOT/$first_artifact_rel" <<'RESULT'

### Conclusion

The repository contract is authoritative.

### Evidence

- The current task and source agree.
RESULT
as_agent research-worker-1 "$TMP_ROOT/.agents/scripts/team_reply.sh" \
  --in-reply-to "$first_assignment" >/dev/null
[[ "$(state_field research "$first_request" status)" == "completed" ]] || fail "research request did not complete"
[[ "$(state_field research "${research_ids[4]}" worker)" == "research-worker-1" ]] || fail "FIFO request was not assigned after completion"
[[ "$(state_field research "${research_ids[4]}" status)" == "active" ]] || fail "FIFO request did not become active"

sixth_request="$(request_research lead "Queued request to cancel")"
[[ "$(state_field research "$sixth_request" status)" == "queued" ]] || fail "sixth research request was not queued"
as_agent lead "$TMP_ROOT/.agents/scripts/team_reply.sh" \
  --in-reply-to "$sixth_request" --type cancel "No longer needed." >/dev/null
[[ "$(state_field research "$sixth_request" status)" == "cancelled" ]] || fail "queued research request did not cancel"

research_status="$(team "$TMP_ROOT/.agents/scripts/team_status.sh")"
[[ "$research_status" != *"$first_request"* ]] || fail "completed research appeared in active team status"
[[ "$research_status" != *"$sixth_request"* ]] || fail "cancelled research appeared in active team status"

# Completion flow: completion_ready, acceptance ack, and the STATE commit gate.
if as_agent manager "$TMP_ROOT/.agents/scripts/team_state_commit.sh" \
  > /dev/null 2> "$TMP_BASE/state-no-ack.err"; then
  fail "completion state commit accepted a completion without completion_ack"
fi
grep -q '^error: completion acknowledgment is not pending$' "$TMP_BASE/state-no-ack.err"

if team "$TMP_ROOT/.agents/scripts/team_send.sh" \
  --from lead --type completion_ready \
  manager "Wrong direction." > /dev/null 2> "$TMP_BASE/completion-route.err"; then
  fail "completion_ready accepted a non-manager sender"
fi
grep -q '^error: invalid completion_ready route$' "$TMP_BASE/completion-route.err"

printf '%s\n' "incomplete work" > "$TMP_ROOT/incomplete.txt"
if team "$TMP_ROOT/.agents/scripts/team_send.sh" \
  --from manager --type completion_ready \
  lead "Dirty tree." > /dev/null 2> "$TMP_BASE/completion-dirty.err"; then
  fail "completion_ready accepted uncommitted project changes"
fi
grep -q '^error: completion verification requires committed project changes$' \
  "$TMP_BASE/completion-dirty.err"
grep -q 'incomplete.txt' "$TMP_BASE/completion-dirty.err"
rm "$TMP_ROOT/incomplete.txt"

touch "$TMP_ROOT/.agents/queue/state/fail-smoke"
if team "$TMP_ROOT/.agents/scripts/team_send.sh" \
  --from manager --type completion_ready \
  lead "Failing smoke." > /dev/null 2> "$TMP_BASE/completion-smoke.err"; then
  fail "completion_ready accepted a failing smoke check"
fi
grep -q '^error: completion verification failed: make smoke$' "$TMP_BASE/completion-smoke.err"
rm "$TMP_ROOT/.agents/queue/state/fail-smoke"

team "$TMP_ROOT/.agents/scripts/team_send.sh" \
  --from manager --type completion_ready \
  lead "T-GENERAL and T-FRONTEND are done and ready for acceptance." >/dev/null 2>&1
lead_completion_raw="$(team "$TMP_ROOT/.agents/scripts/team_inbox.sh" lead --raw)"
grep -q "Verified commit: $(git -C "$TMP_ROOT" rev-parse HEAD)" <<<"$lead_completion_raw" \
  || fail "completion_ready did not record the verified commit"
ack_output="$(
  team "$TMP_ROOT/.agents/scripts/team_send.sh" \
    --from lead --type completion_ack \
    manager "Completion was reported to the human." 2> "$TMP_BASE/ack-next.err"
)"
ack_id="$(printf '%s\n' "$ack_output" | sed -n 's/^message_id=//p')"
[[ -n "$ack_id" ]] || fail "completion_ack returned no message id"
# Sending completion_ack is the moment the Lead should look at the backlog.
grep -q 'next: backlogを確認' "$TMP_BASE/ack-next.err" \
  || fail "completion_ack did not carry the backlog reminder"

printf '\n- The intake is complete and the team is waiting for the next one.\n' \
  >> "$TMP_ROOT/.agents/state/STATE.md"
printf '%s\n' "unfinished change" > "$TMP_ROOT/unfinished.txt"
if as_agent manager "$TMP_ROOT/.agents/scripts/team_state_commit.sh" \
  > /dev/null 2> "$TMP_BASE/state-dirty.err"; then
  fail "completion state commit accepted unrelated repository changes"
fi
grep -q '^error: completion state commit requires a clean repository outside .agents/state/STATE.md$' \
  "$TMP_BASE/state-dirty.err"
grep -q 'unfinished.txt' "$TMP_BASE/state-dirty.err"
[[ ! -f "$TMP_ROOT/.agents/queue/state/processed/manager/$ack_id" ]] \
  || fail "failed completion state commit consumed completion_ack"
rm "$TMP_ROOT/unfinished.txt"

state_commit_output="$(as_agent manager "$TMP_ROOT/.agents/scripts/team_state_commit.sh")"
state_commit="$(printf '%s\n' "$state_commit_output" | sed -n 's/^commit=//p')"
[[ -n "$state_commit" ]] || fail "completion state commit returned no commit hash"
[[ "$(git -C "$TMP_ROOT" show --format= --name-only "$state_commit")" == ".agents/state/STATE.md" ]] \
  || fail "completion state commit included paths outside STATE.md"
git -C "$TMP_ROOT" show -s --format=%B "$state_commit" | grep -q "^Agent-State: $ack_id$"
[[ -f "$TMP_ROOT/.agents/queue/state/processed/manager/$ack_id" ]] \
  || fail "completion state commit did not process completion_ack"
[[ -z "$(git -C "$TMP_ROOT" status --short --untracked-files=all)" ]] \
  || fail "completion state commit did not leave a clean repository"

if as_agent manager "$TMP_ROOT/.agents/scripts/team_state_commit.sh" \
  > /dev/null 2> "$TMP_BASE/state-reuse.err"; then
  fail "completion state commit reused a processed completion_ack"
fi
grep -q '^error: completion acknowledgment is not pending$' "$TMP_BASE/state-reuse.err"

# Backlog: intents parked as cards, ordered high priority first, consumed into
# an intake with a traceable Intake ref. Only open cards can be consumed.
card_one="$(team "$TMP_ROOT/.agents/scripts/team_backlog.sh" add \
  --title "Second intake idea" --priority normal | sed -n 's/^card_id=//p')"
card_two="$(team "$TMP_ROOT/.agents/scripts/team_backlog.sh" add \
  --title "Urgent wish" --priority high --body "spec detail" | sed -n 's/^card_id=//p')"
[[ -n "$card_one" && -n "$card_two" ]] || fail "backlog add returned no card id"
backlog_list="$(team "$TMP_ROOT/.agents/scripts/team_backlog.sh" list)"
first_open="$(printf '%s\n' "$backlog_list" | sed -n '/^open:/{n;p;}' | awk '{print $1}')"
[[ "$first_open" == "$card_two" ]] \
  || fail "backlog did not order the high-priority card first"

team "$TMP_ROOT/.agents/scripts/team_backlog.sh" pull "$card_two" --intake "msg_backlog_intake" >/dev/null
grep -q '^Status: consumed$' "$TMP_ROOT/.agents/queue/backlog/$card_two.md" \
  || fail "backlog pull did not mark the card consumed"
grep -q '^Intake ref: msg_backlog_intake$' "$TMP_ROOT/.agents/queue/backlog/$card_two.md" \
  || fail "backlog pull did not record the intake ref"
if team "$TMP_ROOT/.agents/scripts/team_backlog.sh" pull "$card_two" --intake msg_y >/dev/null 2>&1; then
  fail "backlog consumed the same card twice"
fi

# A clarified card carries a ## Spec section in its body and outranks priority:
# it can become an intake without another clarification pass, so the Lead's
# "pull the first open card" norm depends on it sorting first.
printf '\n## Spec\n\nGoal and acceptance settled with the human.\n' \
  >> "$TMP_ROOT/.agents/queue/backlog/$card_one.md"
team "$TMP_ROOT/.agents/scripts/team_backlog.sh" add \
  --title "Newer high wish" --priority high >/dev/null
backlog_list="$(team "$TMP_ROOT/.agents/scripts/team_backlog.sh" list)"
first_open="$(printf '%s\n' "$backlog_list" | sed -n '/^open:/{n;p;}' | awk '{print $1}')"
[[ "$first_open" == "$card_one" ]] \
  || fail "backlog did not order the spec-ready card first"
printf '%s\n' "$backlog_list" | grep -q "$card_one \[normal/spec\]" \
  || fail "backlog list did not mark the spec-ready card"

echo "harness lifecycle ok"
