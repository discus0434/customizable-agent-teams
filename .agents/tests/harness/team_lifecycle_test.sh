#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_BASE="$(mktemp -d)"
TMP_ROOT="$TMP_BASE/repo"
TMP_CONFIG_FILE="$TMP_ROOT/.agents/config/agent-team.yaml"
trap 'rm -rf "$TMP_BASE"' EXIT

mkdir -p "$TMP_ROOT/.agents"
cp -R "$ROOT/.agents/scripts" "$TMP_ROOT/.agents/scripts"
cp -R "$ROOT/.agents/config" "$TMP_ROOT/.agents/config"
cp -R "$ROOT/.agents/docs" "$TMP_ROOT/.agents/docs"
cp -R "$ROOT/.agents/state" "$TMP_ROOT/.agents/state"
cp "$ROOT/.gitignore" "$TMP_ROOT/.gitignore"
cp "$ROOT/AGENTS.md" "$TMP_ROOT/AGENTS.md"
cp -P "$ROOT/CLAUDE.md" "$TMP_ROOT/CLAUDE.md"

mkdir -p \
  "$TMP_ROOT/.agents/queue/tasks" \
  "$TMP_ROOT/.agents/queue/inbox" \
  "$TMP_ROOT/.agents/queue/reports" \
  "$TMP_ROOT/.agents/queue/reviews" \
  "$TMP_ROOT/.agents/queue/strategy" \
  "$TMP_ROOT/.agents/queue/memory_proposals" \
  "$TMP_ROOT/.agents/queue/state"
cp "$ROOT/.agents/queue/tasks/TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/TEMPLATE.md"

cat > "$TMP_ROOT/Makefile" <<'MAKE'
.PHONY: post-change smoke

post-change:
	@git diff --check -- .

smoke:
	@echo "temp smoke ok"
MAKE

mkdir -p "$TMP_BASE/bin"

cat > "$TMP_BASE/bin/tmux" <<'SH'
#!/usr/bin/env bash
case "$1" in
  has-session)
    if [[ "${TEAM_FAKE_TMUX_HAS_SESSION:-0}" == "1" ]]; then
      exit 0
    fi
    exit 1
    ;;
  new-session|new-window)
    printf '%s\n' "$*" >> "$TEAM_FAKE_TMUX_LOG"
    exit 0
    ;;
  display-message)
    if [[ "$*" == *"#{pane_id}"* ]]; then
      printf '%%fake-pane\n'
    elif [[ "$*" == *"#{pane_in_mode}"* ]]; then
      printf '0\n'
    fi
    exit 0
    ;;
  capture-pane)
    printf '%s\n' "Claude Code v2.1.190"
    printf '%s\n' "Try \"edit <filepath> to...\""
    printf '%s\n' "Quick safety check: Is this a project you created or one you trust?"
    printf '%s\n' "Enter to confirm"
    exit 0
    ;;
  send-keys)
    printf '%s\n' "$*" >> "$TEAM_FAKE_TMUX_LOG"
    exit 0
    ;;
  set-option|kill-session|list-panes)
    exit 0
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$TMP_BASE/bin/tmux"

git -C "$TMP_ROOT" init -q
git -C "$TMP_ROOT" config user.email "agent-team-smoke@example.local"
git -C "$TMP_ROOT" config user.name "Agent Team Smoke"
git -C "$TMP_ROOT" add .
git -C "$TMP_ROOT" commit -qm "Initial template"

TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_status.sh" >/dev/null
[[ -d "$TMP_ROOT/.agents/queue/state/tmp" ]] || { echo "runtime scratch directory was not created" >&2; exit 1; }
[[ -d "$TMP_ROOT/.agents/queue/strategy" ]] || { echo "strategy directory was not created" >&2; exit 1; }
[[ -f "$TMP_ROOT/.agents/state/STATE.md" ]] || { echo "STATE.md was not copied" >&2; exit 1; }
[[ -f "$TMP_ROOT/.agents/state/MEMORY.md" ]] || { echo "MEMORY.md was not copied" >&2; exit 1; }

TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" session >/dev/null
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" agent lead >/dev/null
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" agent manager >/dev/null
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" agent strategist >/dev/null
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" agent reviewer-1 >/dev/null
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" agent worker-1 >/dev/null
if TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" review-field model >/dev/null 2>&1; then
  echo "review-field must not exist" >&2
  exit 1
fi

identity="$(
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_AGENT_ID=manager \
  TEAM_AGENT_ROLE=manager \
  TEAM_AGENT_CLI=claude \
  TEAM_AGENT_MODEL=claude-opus-4-8 \
  TEAM_SESSION=agent-team \
  "$TMP_ROOT/.agents/scripts/team_identity.sh"
)"
case "$identity" in
  *"agent_id=manager"*"role=manager"*) ;;
  *) echo "identity missing manager role" >&2; exit 1 ;;
esac

export TEAM_FAKE_TMUX_LOG="$TMP_BASE/tmux.log"
team_start_log="$TMP_BASE/team_start.log"
if ! PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_BOOT_NUDGE_DELAY=0 "$TMP_ROOT/.agents/scripts/team_start.sh" --restart > "$team_start_log" 2>&1; then
  cat "$team_start_log" >&2
  exit 1
fi
tmux_log="$(<"$TEAM_FAKE_TMUX_LOG")"
case "$tmux_log" in *"TEAM_AGENT_ID=lead"*"TEAM_AGENT_ROLE=lead"*) ;; *) echo "lead launch env was not passed" >&2; exit 1 ;; esac
case "$tmux_log" in *"TEAM_AGENT_ID=manager"*"TEAM_AGENT_ROLE=manager"*) ;; *) echo "manager launch env was not passed" >&2; exit 1 ;; esac
case "$tmux_log" in *"TEAM_AGENT_ID=strategist"*"TEAM_AGENT_ROLE=strategist"*) ;; *) echo "strategist launch env was not passed" >&2; exit 1 ;; esac
case "$tmux_log" in *"TEAM_AGENT_ID=reviewer-1"*"TEAM_AGENT_ROLE=reviewer"*) ;; *) echo "reviewer launch env was not passed" >&2; exit 1 ;; esac
case "$tmux_log" in *"TEAM_AGENT_ID=worker-1"*"TEAM_AGENT_ROLE=worker"*) ;; *) echo "worker launch env was not passed" >&2; exit 1 ;; esac
case "$tmux_log" in *"実装や dispatch はせず"*) ;; *) echo "lead boot nudge was not sent" >&2; exit 1 ;; esac
case "$tmux_log" in *"STATE の主編集者"*) ;; *) echo "manager boot nudge was not sent" >&2; exit 1 ;; esac
case "$tmux_log" in *"strategy_request"*) ;; *) echo "strategist boot nudge was not sent" >&2; exit 1 ;; esac
case "$tmux_log" in *"review_watch_assigned"*) ;; *) echo "reviewer boot nudge was not sent" >&2; exit 1 ;; esac
case "$tmux_log" in *"task_assigned"*) ;; *) echo "worker boot nudge was not sent" >&2; exit 1 ;; esac
startup_enter_count="$(grep -o 'C-m' "$TEAM_FAKE_TMUX_LOG" | wc -l | tr -d ' ')"
[[ "$startup_enter_count" -ge 3 ]] || { echo "startup prompt was not submitted with repeated C-m" >&2; exit 1; }

: > "$TEAM_FAKE_TMUX_LOG"
team_bootstrap_log="$TMP_BASE/team_bootstrap.log"
if ! PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  "$TMP_ROOT/.agents/scripts/team_bootstrap.sh" > "$team_bootstrap_log" 2>&1; then
  cat "$team_bootstrap_log" >&2
  exit 1
fi
case "$(<"$TEAM_FAKE_TMUX_LOG")" in
  *"send-keys"*"team-bootstrap"*"何を作るか"*"1問"*) ;;
  *) echo "bootstrap prompt was not sent to lead" >&2; exit 1 ;;
esac
case "$(<"$TEAM_FAKE_TMUX_LOG")" in
  *"TEAM_AGENT_ID=manager"*) echo "bootstrap should start only the lead agent" >&2; exit 1 ;;
esac

: > "$TEAM_FAKE_TMUX_LOG"
if ! PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_BOOT_NUDGE=0 \
  "$TMP_ROOT/.agents/scripts/team_start.sh" --restart > "$team_start_log" 2>&1; then
  cat "$team_start_log" >&2
  exit 1
fi

: > "$TEAM_FAKE_TMUX_LOG"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  "$TMP_ROOT/.agents/scripts/team_nudge.sh" worker-1
case "$(<"$TEAM_FAKE_TMUX_LOG")" in
  *"send-keys"*"inbox worker-1"*"C-m"*) ;;
  *) echo "nudge did not submit inbox with C-m" >&2; exit 1 ;;
esac
nudge_enter_count="$(grep -o 'C-m' "$TEAM_FAKE_TMUX_LOG" | wc -l | tr -d ' ')"
[[ "$nudge_enter_count" -ge 3 ]] || { echo "nudge was not submitted with repeated C-m" >&2; exit 1; }

cp "$TMP_ROOT/.agents/queue/tasks/TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-001.md"
perl -0pi -e 's/T-XXX/T-001/g' "$TMP_ROOT/.agents/queue/tasks/T-001.md"

cp "$TMP_ROOT/.agents/queue/tasks/TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-BAD.md"
perl -0pi -e 's/T-XXX/T-BAD/g; s/Reviewer: reviewer-1/Reviewer: worker-1/' "$TMP_ROOT/.agents/queue/tasks/T-BAD.md"
if TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 "$TMP_ROOT/.agents/scripts/team_dispatch.sh" T-BAD worker-1 reviewer-1 >/dev/null 2>&1; then
  echo "reviewer mismatch dispatch unexpectedly succeeded" >&2
  exit 1
fi

message_state="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 "$TMP_ROOT/.agents/scripts/team_dispatch.sh" T-001 worker-1 reviewer-1)"
[[ -f "$message_state" ]]
grep -q '"owner":"worker-1"' "$message_state"
grep -q '"reviewer":"reviewer-1"' "$message_state"
grep -q '"status":"dispatched"' "$message_state"
task_base_commit="$(git -C "$TMP_ROOT" rev-parse HEAD)"
grep -q "\"base_commit\":\"$task_base_commit\"" "$message_state"

worker_pending="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_inbox.sh" worker-1)"
case "$worker_pending" in
  *"\"type\":\"task_assigned\""*"reviewer-1"*) ;;
  *) echo "worker task assignment was not visible in inbox" >&2; exit 1 ;;
esac

reviewer_pending="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_inbox.sh" reviewer-1)"
case "$reviewer_pending" in
  *"\"type\":\"review_watch_assigned\""*"worker-1"*) ;;
  *) echo "reviewer watch assignment was not visible in inbox" >&2; exit 1 ;;
esac

printf '%s\n' "worker change" > "$TMP_ROOT/manager-review-smoke.txt"
dirty_report_file="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_report.sh" T-001 worker-1 needs_review)"
[[ -f "$dirty_report_file" ]]
grep -q '^Status: needs_review$' "$dirty_report_file"

git -C "$TMP_ROOT" add manager-review-smoke.txt
git -C "$TMP_ROOT" commit -qm "T-001: add manager review smoke"
task_head_commit="$(git -C "$TMP_ROOT" rev-parse HEAD)"
report_file="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_report.sh" T-001 worker-1 needs_review)"
grep -q "^Head commit: $task_head_commit$" "$report_file"

cat > "$report_file" <<REPORT
# Report: T-001 by worker-1

Status: needs_review
Reviewer: reviewer-1
Base commit: $task_base_commit
Head commit: $task_head_commit
Review: none
Review decision: none

## Summary

- Smoke task change is committed.

## Files changed

- manager-review-smoke.txt

## Commits

- $(git -C "$TMP_ROOT" log --oneline -1)

## Verification

- Command: test -f manager-review-smoke.txt
- Result: PASS
- Evidence: file exists in the shared root commit.

## Post-change

- Command: make post-change
- Result: PASS
- Evidence: temp post-change target checks diff whitespace.

## Smoke

- Command: make smoke
- Result: PASS
- Evidence: temp smoke target prints temp smoke ok.

## Reviewer coordination

- Assigned reviewer: reviewer-1
- Ready for review message: sent
- Reviewer feedback handled: pending

## Blockers

- None.

## Questions for reviewer

- None.

## Escalation for manager

- None.

## Memory proposals

- None.
REPORT

review_file="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 "$TMP_ROOT/.agents/scripts/team_review_report.sh" T-001 reviewer-1 OK)"
[[ "$review_file" == "$TMP_ROOT/.agents/queue/reviews/T-001_reviewer-1.md" ]]
grep -q '^Decision: OK$' "$review_file"
grep -q '"status":"review_ok"' "$message_state"
grep -q '"review_decision":"OK"' "$message_state"

manager_pending="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_inbox.sh" manager)"
case "$manager_pending" in
  *"\"type\":\"review_result\""*"Decision: OK"*) ;;
  *) echo "manager did not receive review result" >&2; exit 1 ;;
esac

done_state="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_state_update.sh" update T-001 done)"
[[ "$done_state" == "$message_state" ]]
grep -q '"status":"done"' "$message_state"

status_output="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_status.sh")"
case "$status_output" in
  *"T-001 owner=worker-1 reviewer=reviewer-1 status=done"*) ;;
  *) echo "status did not show done task" >&2; exit 1 ;;
esac

echo "smoke ok"
