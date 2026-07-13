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
  TEAM_ROOT="$TMP_ROOT" \
    TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
    TEAM_DISABLE_NUDGE=1 \
    "$@"
}

as_agent() {
  local agent_id="$1"
  shift
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

mkdir -p "$TMP_ROOT/.agents/queue/tasks"
cp -R "$ROOT/.agents/scripts" "$TMP_ROOT/.agents/scripts"
cp -R "$ROOT/.agents/config" "$TMP_ROOT/.agents/config"
cp -R "$ROOT/.agents/docs" "$TMP_ROOT/.agents/docs"
cp -R "$ROOT/.agents/state" "$TMP_ROOT/.agents/state"
cp "$ROOT/.agents/agent-team.mk" "$TMP_ROOT/.agents/agent-team.mk"
cp "$ROOT/.gitignore" "$TMP_ROOT/.gitignore"
cp "$ROOT/AGENTS.md" "$TMP_ROOT/AGENTS.md"
cp "$ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md"
cp "$ROOT/.agents/queue/tasks/FRONTEND_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/FRONTEND_TEMPLATE.md"
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
	@if [ -f .agents/queue/state/fail-release-smoke ]; then echo "forced release smoke failure" >&2; exit 1; fi
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
    if [[ "$*" == *"#{pane_in_mode}"* ]]; then
      printf '0\n'
    elif [[ "$*" == *"#{session_name}"* ]]; then
      printf 'agent-team\n'
    elif [[ "$*" == *"#{pane_id}"* ]]; then
      printf '%%fake\n'
    fi
    ;;
  capture-pane)
    if [[ -n "${TEAM_FAKE_TMUX_BUSY_FILE:-}" && -f "$TEAM_FAKE_TMUX_BUSY_FILE" ]]; then
      printf '%s\n' "Working (1s - esc to interrupt)"
    else
      printf '%s\n' "Claude Code"
    fi
    ;;
  list-panes)
    [[ -n "${TEAM_FAKE_TMUX_LOG:-}" ]] && printf '%s\n' "$*" >> "$TEAM_FAKE_TMUX_LOG"
    printf '%s\n' '  %fake lead agent=lead role=lead model=claude-opus-4-8'
    ;;
  send-keys|set-buffer|paste-buffer|set-option|new-session|new-window|kill-session)
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

git -C "$TMP_ROOT" init -q
git -C "$TMP_ROOT" config user.email "agent-team-test@example.local"
git -C "$TMP_ROOT" config user.name "Agent Team Test"
git -C "$TMP_ROOT" add .
git -C "$TMP_ROOT" commit -qm "Initial template"

# Config and launcher contracts.
team "$TMP_ROOT/.agents/scripts/team_config.sh" validate
research_command="$(team "$TMP_ROOT/.agents/scripts/team_config.sh" command research-worker-1)"
general_command="$(team "$TMP_ROOT/.agents/scripts/team_config.sh" command general-worker-1)"
hard_command="$(team "$TMP_ROOT/.agents/scripts/team_config.sh" command hard-task-worker-1)"
reviewer_command="$(team "$TMP_ROOT/.agents/scripts/team_config.sh" command general-reviewer-1)"
critic_command="$(team "$TMP_ROOT/.agents/scripts/team_config.sh" command frontend-critic-1)"
[[ "$research_command" == *"--dangerously-bypass-approvals-and-sandbox"* ]] || fail "research worker lost Codex permission bypass"
[[ "$research_command" == *"--search"* ]] || fail "research worker is not launched with Web search"
[[ "$general_command" == *"--dangerously-bypass-approvals-and-sandbox"* ]] || fail "general worker lost Codex permission bypass"
[[ "$general_command" == *"--model gpt-5.6-luna"* ]] || fail "general worker model is not gpt-5.6-luna"
[[ "$general_command" == *'model_reasoning_effort=\"high\"'* ]] || fail "general worker effort is not high"
[[ "$general_command" != *"--search"* ]] || fail "general worker unexpectedly enables Web search"
[[ "$hard_command" == *"--dangerously-bypass-approvals-and-sandbox"* ]] || fail "hard task worker lost Codex permission bypass"
[[ "$hard_command" == *"--model gpt-5.6-sol"* ]] || fail "hard task worker model is not gpt-5.6-sol"
[[ "$hard_command" == *'model_reasoning_effort=\"xhigh\"'* ]] || fail "hard task worker effort is not xhigh"
[[ "$hard_command" != *"--search"* ]] || fail "hard task worker unexpectedly enables Web search"
[[ "$reviewer_command" == *"--model gpt-5.6-sol"* ]] || fail "general reviewer model is not gpt-5.6-sol"
[[ "$reviewer_command" == *'model_reasoning_effort=\"low\"'* ]] || fail "general reviewer effort is not low"
[[ "$critic_command" == *"--dangerously-skip-permissions"* ]] || fail "frontend critic lost Claude permission bypass"

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
grep -q '^\[team\] queued nudge for lead; pane is busy$' "$TMP_BASE/deferred-nudge.err"
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

# General implementation lifecycle and fixed-pair availability.
cp "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-GENERAL.md"
perl -0pi -e 's/T-XXX/T-GENERAL/g; s#\x60path/to/file\x60#\x60general-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-GENERAL.md"
team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-GENERAL >/dev/null
general_state="$(team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --manager manager T-GENERAL)"
grep -q '"worker":"general-worker-1"' "$general_state"
grep -q '"supervisor":"general-reviewer-1"' "$general_state"
grep -q '^Supervisor: general-reviewer-1$' "$TMP_ROOT/.agents/queue/tasks/T-GENERAL.md"

cp "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-CONFLICT.md"
perl -0pi -e 's/T-XXX/T-CONFLICT/g; s#\x60path/to/file\x60#\x60conflict-output.txt\x60#; s#- \x60\.agents/state/STATE\.md\x60#- \x60*.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-CONFLICT.md"
if team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-CONFLICT \
  > /dev/null 2> "$TMP_BASE/path-conflict.err"; then
  fail "task lint accepted overlapping ownership patterns"
fi
grep -q '^error: task path ownership patterns overlap: conflict-output.txt and \*.txt$' "$TMP_BASE/path-conflict.err"

cp "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-BUSY.md"
perl -0pi -e 's/T-XXX/T-BUSY/g; s#\x60path/to/file\x60#\x60busy-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-BUSY.md"
if team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --manager manager T-BUSY > /dev/null 2> "$TMP_BASE/busy.err"; then
  fail "dispatch accepted a busy fixed pair"
fi
grep -q '^error: implementation worker is busy: general-worker-1$' "$TMP_BASE/busy.err"

checkpoint_output="$(
  team "$TMP_ROOT/.agents/scripts/team_send.sh" \
    --from general-worker-1 --type supervision_checkpoint --task T-GENERAL \
    general-reviewer-1 "Parser boundary is ready."
)"
checkpoint_id="$(printf '%s\n' "$checkpoint_output" | sed -n 's/^message_id=//p')"
reviewer_inbox="$(team "$TMP_ROOT/.agents/scripts/team_inbox.sh" general-reviewer-1)"
grep -q 'processed_on_read: true' <<<"$reviewer_inbox"
[[ -f "$TMP_ROOT/.agents/queue/state/processed/general-reviewer-1/$checkpoint_id" ]] \
  || fail "supervision checkpoint did not close on read"

strategy_request_output="$(
  team "$TMP_ROOT/.agents/scripts/team_send.sh" \
    --from general-reviewer-1 --task T-GENERAL strategist "Compare the parser boundary options."
)"
grep -q '^cc_to=manager$' <<<"$strategy_request_output"
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
perl -0pi -e 's/(## Do not modify\n\n)/$1- `*.txt`\n/' "$TMP_ROOT/.agents/queue/tasks/T-GENERAL.md"
head_before_conflict="$(git -C "$TMP_ROOT" rev-parse HEAD)"
if TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 TEAM_AGENT_ID=general-worker-1 \
  make -s -C "$TMP_ROOT" task-commit TASK=T-GENERAL MESSAGE="add output" \
  > /dev/null 2> "$TMP_BASE/commit-path-conflict.err"; then
  fail "task commit accepted overlapping ownership patterns"
fi
grep -q '^error: task path ownership patterns overlap: general-output.txt and \*.txt$' "$TMP_BASE/commit-path-conflict.err"
[[ "$(git -C "$TMP_ROOT" rev-parse HEAD)" == "$head_before_conflict" ]] \
  || fail "task commit created a partial commit after path validation failed"
perl -0pi -e 's/- `\*\.txt`\n//' "$TMP_ROOT/.agents/queue/tasks/T-GENERAL.md"

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
Release bundle: none
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
hard_state="$(team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --manager manager T-HARD)"
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
grep -q 'processed_on_read: true' <<<"$hard_reviewer_inbox"
[[ -f "$TMP_ROOT/.agents/queue/state/processed/general-reviewer-4/$hard_checkpoint_id" ]] \
  || fail "hard task checkpoint did not reach its fixed reviewer"

# Frontend direction and critic lifecycle.
cp "$TMP_ROOT/.agents/queue/tasks/FRONTEND_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-FRONTEND.md"
perl -0pi -e 's/T-XXX/T-FRONTEND/g; s#\x60path/to/frontend/file\x60#\x60frontend-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-FRONTEND.md"
team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-FRONTEND >/dev/null
frontend_state="$(team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --manager manager T-FRONTEND)"
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
Release bundle: none
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

# Research pool FIFO, clarification, completion, and cancellation.
research_ids=()
for index in 1 2 3 4 5; do
  research_ids+=("$(request_research lead "Research question $index")")
done
[[ "$(state_field research "${research_ids[0]}" worker)" == "research-worker-1" ]] || fail "first research request did not use worker 1"
[[ "$(state_field research "${research_ids[3]}" worker)" == "research-worker-4" ]] || fail "fourth research request did not use worker 4"
[[ "$(state_field research "${research_ids[4]}" status)" == "queued" ]] || fail "fifth research request was not queued"

first_request="${research_ids[0]}"
first_assignment="$(state_field research "$first_request" request_message_id)"
question_output="$(
  as_agent research-worker-1 "$TMP_ROOT/.agents/scripts/team_reply.sh" \
    --in-reply-to "$first_assignment" --type question "Which source is authoritative?"
)"
question_id="$(printf '%s\n' "$question_output" | sed -n 's/^message_id=//p')"
[[ "$(state_field research "$first_request" status)" == "waiting_for_caller" ]] || fail "research question did not pause the request"

as_agent lead "$TMP_ROOT/.agents/scripts/team_reply.sh" \
  --in-reply-to "$question_id" "Use the repository contract." >/dev/null
[[ "$(state_field research "$first_request" status)" == "active" ]] || fail "research answer did not resume the request"

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

# Whole-system release gate.
team "$TMP_ROOT/.agents/scripts/team_release_prepare.sh" \
  --manager manager R-001 T-GENERAL T-FRONTEND >/dev/null
release_bundle="$TMP_ROOT/.agents/queue/releases/R-001.md"
cat > "$release_bundle" <<'BUNDLE'
# Release Bundle: R-001

Status: prepared
Manager: manager
Release captain: release-captain
Review: .agents/queue/releases/R-001_review.md
Decision: none

## Goal

- Ship both implementation tasks.

## Included tasks

- T-GENERAL
- T-FRONTEND

## Evidence summary

- Both tasks are done with Supervisor OK.

## Known issues

- None.

## Requested decision

- Decide SHIP, FIX, or BLOCKED.
BUNDLE
team "$TMP_ROOT/.agents/scripts/team_release_request.sh" \
  --manager manager R-001 T-GENERAL T-FRONTEND >/dev/null

release_review="$TMP_ROOT/.agents/queue/releases/R-001_review.md"
cat > "$release_review" <<'RELEASE'
# Release Review: R-001

Decision: none
Bundle: .agents/queue/releases/R-001.md
Manager: manager
Release captain: release-captain
Verified commit: pending
Post-change: pending
Post-change evidence: .agents/queue/releases/R-001_post-change.log
Smoke: pending
Smoke evidence: .agents/queue/releases/R-001_smoke.log

## Decision Summary

- SHIP.

## Bundle Checks

- [x] Intent, tasks, evidence, and current state agree.

## Evidence Reviewed

- Reports, review, critique, visual evidence, commits, post-change, and smoke.

## Caveats

- None.

## Required fixes

- None.
RELEASE
printf '%s\n' "uncommitted release change" > "$TMP_ROOT/unreleased.txt"
if team "$TMP_ROOT/.agents/scripts/team_release_report.sh" R-001 release-captain SHIP \
  > /dev/null 2> "$TMP_BASE/release-dirty.err"; then
  fail "SHIP accepted uncommitted project changes"
fi
grep -q '^error: release verification requires committed project changes$' \
  "$TMP_BASE/release-dirty.err"
grep -q 'unreleased.txt' "$TMP_BASE/release-dirty.err"
[[ "$(state_field release R-001 status)" == "requested" ]] \
  || fail "dirty release verification changed the release status"
rm "$TMP_ROOT/unreleased.txt"
touch "$TMP_ROOT/.agents/queue/state/fail-release-smoke"
if team "$TMP_ROOT/.agents/scripts/team_release_report.sh" R-001 release-captain SHIP \
  > /dev/null 2> "$TMP_BASE/release-smoke.err"; then
  fail "SHIP accepted a failing release smoke check"
fi
grep -q '^error: release verification failed: make smoke$' "$TMP_BASE/release-smoke.err"
[[ "$(state_field release R-001 status)" == "requested" ]] \
  || fail "failed release verification changed the release status"
rm "$TMP_ROOT/.agents/queue/state/fail-release-smoke"
team "$TMP_ROOT/.agents/scripts/team_release_report.sh" R-001 release-captain SHIP >/dev/null
[[ "$(state_field release R-001 status)" == "ship" ]] || fail "release did not reach ship"
verified_release_commit="$(git -C "$TMP_ROOT" rev-parse HEAD)"
grep -q "^Verified commit: $verified_release_commit$" "$release_review"
grep -q '^Post-change: passed$' "$release_review"
grep -q '^Smoke: passed$' "$release_review"
grep -q '^temp post-change ok$' "$TMP_ROOT/.agents/queue/releases/R-001_post-change.log"
grep -q '^temp smoke ok$' "$TMP_ROOT/.agents/queue/releases/R-001_smoke.log"

if as_agent manager "$TMP_ROOT/.agents/scripts/team_state_commit.sh" R-001 \
  > /dev/null 2> "$TMP_BASE/state-no-ack.err"; then
  fail "completion state commit accepted a release without completion_ack"
fi
grep -q '^error: completion acknowledgment is not pending: R-001$' "$TMP_BASE/state-no-ack.err"

team "$TMP_ROOT/.agents/scripts/team_send.sh" \
  --from manager --type completion_ready --bundle R-001 \
  lead "R-001 is ready for the human completion report." >/dev/null
ack_output="$(
  team "$TMP_ROOT/.agents/scripts/team_send.sh" \
    --from lead --type completion_ack --bundle R-001 \
    manager "R-001 was reported complete."
)"
ack_id="$(printf '%s\n' "$ack_output" | sed -n 's/^message_id=//p')"
[[ -n "$ack_id" ]] || fail "completion_ack returned no message id"

printf '\n- R-001 is complete and the team is waiting for the next intake.\n' \
  >> "$TMP_ROOT/.agents/state/STATE.md"
printf '%s\n' "unfinished change" > "$TMP_ROOT/unfinished.txt"
if as_agent manager "$TMP_ROOT/.agents/scripts/team_state_commit.sh" R-001 \
  > /dev/null 2> "$TMP_BASE/state-dirty.err"; then
  fail "completion state commit accepted unrelated repository changes"
fi
grep -q '^error: completion state commit requires a clean repository outside .agents/state/STATE.md$' \
  "$TMP_BASE/state-dirty.err"
grep -q 'unfinished.txt' "$TMP_BASE/state-dirty.err"
[[ ! -f "$TMP_ROOT/.agents/queue/state/processed/manager/$ack_id" ]] \
  || fail "failed completion state commit consumed completion_ack"
rm "$TMP_ROOT/unfinished.txt"

state_commit_output="$(as_agent manager "$TMP_ROOT/.agents/scripts/team_state_commit.sh" R-001)"
state_commit="$(printf '%s\n' "$state_commit_output" | sed -n 's/^commit=//p')"
[[ -n "$state_commit" ]] || fail "completion state commit returned no commit hash"
[[ "$(git -C "$TMP_ROOT" show --format= --name-only "$state_commit")" == ".agents/state/STATE.md" ]] \
  || fail "completion state commit included paths outside STATE.md"
git -C "$TMP_ROOT" show -s --format=%B "$state_commit" | grep -q '^Agent-State: R-001$'
[[ -f "$TMP_ROOT/.agents/queue/state/processed/manager/$ack_id" ]] \
  || fail "completion state commit did not process completion_ack"
[[ -z "$(git -C "$TMP_ROOT" status --short --untracked-files=all)" ]] \
  || fail "completion state commit did not leave a clean repository"

echo "harness lifecycle ok"
