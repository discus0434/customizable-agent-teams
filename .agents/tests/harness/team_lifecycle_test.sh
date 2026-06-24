#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_BASE="$(mktemp -d)"
TMP_ROOT="$TMP_BASE/repo"
TMP_CONFIG_FILE="$TMP_ROOT/.agents/config/agent-team.yaml"
trap 'rm -rf "$TMP_BASE"' EXIT

mkdir -p "$TMP_ROOT"
mkdir -p "$TMP_ROOT/.agents"
cp -R "$ROOT/.agents/scripts" "$TMP_ROOT/.agents/scripts"
cp -R "$ROOT/.agents/config" "$TMP_ROOT/.agents/config"
cp -R "$ROOT/.agents/docs" "$TMP_ROOT/.agents/docs"
cp "$ROOT/.gitignore" "$TMP_ROOT/.gitignore"
cp "$ROOT/AGENTS.md" "$TMP_ROOT/AGENTS.md"
cp -P "$ROOT/CLAUDE.md" "$TMP_ROOT/CLAUDE.md"

mkdir -p \
  "$TMP_ROOT/.agents/queue/tasks" \
  "$TMP_ROOT/.agents/queue/inbox" \
  "$TMP_ROOT/.agents/queue/reports" \
  "$TMP_ROOT/.agents/queue/reviews" \
  "$TMP_ROOT/.agents/queue/integrations" \
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

perl -0pi -e 's/(  review:\n    cli: )claude/${1}codex/; s/(  review:\n    cli: codex\n    model: )claude-opus-4-8/${1}gpt-5.5/' "$TMP_CONFIG_FILE"
mkdir -p "$TMP_BASE/bin"

git -C "$TMP_ROOT" init -q
git -C "$TMP_ROOT" config user.email "agent-team-smoke@example.local"
git -C "$TMP_ROOT" config user.name "Agent Team Smoke"
git -C "$TMP_ROOT" add .
git -C "$TMP_ROOT" commit -qm "Initial template"

TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_status.sh" >/dev/null
[[ -d "$TMP_ROOT/.agents/queue/state/tmp" ]] || { echo "runtime scratch directory was not created" >&2; exit 1; }

cat > "$TMP_BASE/bin/codex" <<'SH'
#!/usr/bin/env bash
if [[ "$1" != "exec" ]]; then
  printf 'unexpected codex command: %s\n' "$*" >&2
  exit 2
fi

if [[ -n "${TEAM_FAKE_CODEX_SLEEP_SECONDS:-}" ]]; then
  sleep "$TEAM_FAKE_CODEX_SLEEP_SECONDS"
fi

output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message|-o)
      [[ $# -ge 2 ]] || exit 2
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$output" ]] || { echo "missing --output-last-message" >&2; exit 2; }
{
  printf '%s\n\n' 'Decision: OK'
  printf '%s\n\n' '## Findings'
  printf '%s\n\n' '## Verification Gaps'
  printf '%s\n\n' '## Notes'
  printf '%s\n' 'stub review'
} > "$output"
printf '%s\n' "codex exec stub"
SH
chmod +x "$TMP_BASE/bin/codex"

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
    printf '%s\n' "Claude Code v2.1.173"
    printf '%s\n' "Try \"edit <filepath> to...\""
    printf '%s\n' "Quick safety check: Is this a project you created or one you trust?"
    printf '%s\n' "Enter to confirm"
    exit 0
    ;;
  send-keys)
    printf '%s\n' "$*" >> "$TEAM_FAKE_TMUX_LOG"
    exit 0
    ;;
  set-option|kill-session)
    exit 0
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$TMP_BASE/bin/tmux"

TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" session >/dev/null
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" agent worker-1 >/dev/null
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" review-field model >/dev/null
TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" review-field timeout_seconds >/dev/null

identity="$(
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_AGENT_ID=worker-1 \
  TEAM_AGENT_ROLE=worker \
  TEAM_AGENT_CLI=codex \
  TEAM_AGENT_MODEL=gpt-5.5 \
  TEAM_SESSION=agent-team \
  "$TMP_ROOT/.agents/scripts/team_identity.sh"
)"
case "$identity" in
  *"agent_id=worker-1"*) ;;
  *) echo "identity missing agent_id" >&2; exit 1 ;;
esac
case "$identity" in
  *"role=worker"*) ;;
  *) echo "identity missing role" >&2; exit 1 ;;
esac

export TEAM_FAKE_TMUX_LOG="$TMP_BASE/tmux.log"
team_start_log="$TMP_BASE/team_start.log"
if ! PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_BOOT_NUDGE_DELAY=0 "$TMP_ROOT/.agents/scripts/team_start.sh" --restart > "$team_start_log" 2>&1; then
  cat "$team_start_log" >&2
  exit 1
fi
case "$(<"$TEAM_FAKE_TMUX_LOG")" in
  *"TEAM_AGENT_ID=lead"*"TEAM_AGENT_ROLE=lead"*"TEAM_AGENT_MODEL="*) ;;
  *) echo "lead launch env was not passed" >&2; exit 1 ;;
esac
case "$(<"$TEAM_FAKE_TMUX_LOG")" in
  *"TEAM_AGENT_ID=worker-1"*"TEAM_AGENT_ROLE=worker"*"TEAM_AGENT_MODEL="*) ;;
  *) echo "worker launch env was not passed" >&2; exit 1 ;;
esac
case "$(<"$TEAM_FAKE_TMUX_LOG")" in
  *"new-session"*" -c $TMP_ROOT "*|*"new-window"*" -c $TMP_ROOT "*) ;;
  *) echo "agents were not launched from TEAM_ROOT" >&2; exit 1 ;;
esac
case "$(<"$TEAM_FAKE_TMUX_LOG")" in
  *"send-keys"*"C-m"*) ;;
  *) echo "startup prompt was not accepted with C-m" >&2; exit 1 ;;
esac
startup_enter_count="$(grep -o 'C-m' "$TEAM_FAKE_TMUX_LOG" | wc -l | tr -d ' ')"
[[ "$startup_enter_count" -ge 3 ]] || { echo "startup prompt was not submitted with repeated C-m" >&2; exit 1; }
case "$(<"$TEAM_FAKE_TMUX_LOG")" in
  *"send-keys"*"AGENTS.md"*) ;;
  *) echo "boot nudge was not submitted with C-m" >&2; exit 1 ;;
esac
if TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_config.sh" agent verifier >/dev/null 2>&1; then
  echo "verifier must not be a tmux agent" >&2
  exit 1
fi

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
  *"TEAM_AGENT_ID=worker-1"*) echo "bootstrap should start only the lead agent" >&2; exit 1 ;;
esac
case "$(<"$TEAM_FAKE_TMUX_LOG")" in
  *"send-keys"*"C-m"*) ;;
  *) echo "bootstrap prompt was not submitted" >&2; exit 1 ;;
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

: > "$TEAM_FAKE_TMUX_LOG"
PATH="$TMP_BASE/bin:$PATH" \
  TEAM_ROOT="$TMP_ROOT" \
  TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
  TEAM_FAKE_TMUX_HAS_SESSION=1 \
  "$TMP_ROOT/.agents/scripts/team_submit.sh" worker-1
case "$(<"$TEAM_FAKE_TMUX_LOG")" in
  *"send-keys"*"C-m"*) ;;
  *) echo "team_submit did not send C-m" >&2; exit 1 ;;
esac
submit_enter_count="$(grep -o 'C-m' "$TEAM_FAKE_TMUX_LOG" | wc -l | tr -d ' ')"
[[ "$submit_enter_count" -ge 3 ]] || { echo "team_submit did not send repeated C-m" >&2; exit 1; }

cp "$TMP_ROOT/.agents/queue/tasks/TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-001.md"
perl -0pi -e 's/T-XXX/T-001/g' "$TMP_ROOT/.agents/queue/tasks/T-001.md"

cp "$TMP_ROOT/.agents/queue/tasks/TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-BAD.md"
perl -0pi -e 's/T-XXX/T-BAD/g; s/Owner: worker-1/Owner: worker-2/' "$TMP_ROOT/.agents/queue/tasks/T-BAD.md"
if TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 "$TMP_ROOT/.agents/scripts/team_send.sh" worker-1 task_assigned T-BAD >/dev/null 2>&1; then
  echo "owner mismatch dispatch unexpectedly succeeded" >&2
  exit 1
fi

message_id="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 "$TMP_ROOT/.agents/scripts/team_send.sh" worker-1 task_assigned T-001)"
[[ -n "$message_id" ]]
task_base_commit="$(git -C "$TMP_ROOT" rev-parse HEAD)"

pending="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_inbox.sh" worker-1)"
case "$pending" in
  *"$message_id"*) ;;
  *) echo "message was not visible in inbox" >&2; exit 1 ;;
esac

TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_inbox.sh" worker-1 --mark "$message_id" >/dev/null
pending_after_mark="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_inbox.sh" worker-1)"
[[ -z "$pending_after_mark" ]]

cp "$TMP_ROOT/.agents/queue/tasks/TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-002.md"
perl -0pi -e 's/T-XXX/T-002/g' "$TMP_ROOT/.agents/queue/tasks/T-002.md"
if TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 "$TMP_ROOT/.agents/scripts/team_send.sh" worker-1 task_assigned T-002 >/dev/null 2>&1; then
  echo "shared root allowed a second active task dispatch" >&2
  exit 1
fi

printf '%s\n' "worker change" > "$TMP_ROOT/integration-smoke.txt"
if TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_report.sh" T-001 worker-1 needs-review >/dev/null 2>&1; then
  echo "dirty root report unexpectedly succeeded" >&2
  exit 1
fi
if PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 "$TMP_ROOT/.agents/scripts/team_review.sh" T-001 worker-1 >/dev/null 2>&1; then
  echo "dirty root review unexpectedly succeeded" >&2
  exit 1
fi

git -C "$TMP_ROOT" add integration-smoke.txt
git -C "$TMP_ROOT" commit -qm "Implement T-001"
task_head_commit="$(git -C "$TMP_ROOT" rev-parse HEAD)"
report_file="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_report.sh" T-001 worker-1 needs-review)"
grep -q '^Head commit: ' "$report_file"
if PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 "$TMP_ROOT/.agents/scripts/team_review.sh" T-001 worker-1 >/dev/null 2>&1; then
  echo "placeholder report review unexpectedly succeeded" >&2
  exit 1
fi

cat > "$report_file" <<REPORT
# Report: T-001 by worker-1

Status: needs-review
Base commit: $task_base_commit
Head commit: $task_head_commit
Review: none
Integration: none

## Summary

- Smoke task change is committed.

## Files changed

- integration-smoke.txt

## Verification

- Command: test -f integration-smoke.txt
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

## Review

- Command: make review TASK=T-001 AGENT=worker-1
- Result:
- Evidence:

## Integration

- Command: make integrate TASK=T-001 AGENT=worker-1
- Result:
- Evidence:

## Blockers

- None.

## Questions for lead

- None.

## Memory proposals

- None.
REPORT

perl -0pi -e 's/(    timeout_seconds: )\d+/${1}1/' "$TMP_CONFIG_FILE"
if PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 TEAM_FAKE_CODEX_SLEEP_SECONDS=5 "$TMP_ROOT/.agents/scripts/team_review.sh" T-001 worker-1 >/dev/null 2>&1; then
  echo "timeout review unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'review command timed out after 1 seconds' "$TMP_ROOT/.agents/queue/reviews/T-001_worker-1_review.exec.log"
perl -0pi -e 's/(    timeout_seconds: )\d+/${1}180/' "$TMP_CONFIG_FILE"

review_file="$(PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 "$TMP_ROOT/.agents/scripts/team_review.sh" T-001 worker-1)"
[[ -f "$review_file" ]]
case "$review_file" in
  "$TMP_ROOT/.agents/queue/reviews/T-001_worker-1_review.md") ;;
  *) echo "unexpected review path: $review_file" >&2; exit 1 ;;
esac
grep -q '^BEGIN TASK FILE$' "$TMP_ROOT/.agents/queue/reviews/T-001_worker-1_review_prompt.txt"
grep -q '^BEGIN WORKER REPORT$' "$TMP_ROOT/.agents/queue/reviews/T-001_worker-1_review_prompt.txt"
grep -q '^BEGIN COMMITTED DIFF$' "$TMP_ROOT/.agents/queue/reviews/T-001_worker-1_review_prompt.txt"
grep -q 'integration-smoke.txt' "$TMP_ROOT/.agents/queue/reviews/T-001_worker-1_review_prompt.txt"

review_message="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_inbox.sh" worker-1)"
case "$review_message" in
  *"\"type\":\"review\""*) ;;
  *) echo "review message was not returned to worker" >&2; exit 1 ;;
esac

report_file="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_report.sh" T-001 worker-1 done)"
status_output="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_status.sh")"
case "$status_output" in
  *"T-001 owner=worker-1 phase=ready-to-integrate"*) ;;
  *) echo "status did not show ready-to-integrate" >&2; exit 1 ;;
esac

integration_file="$(PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_integrate.sh" T-001 worker-1)"
[[ -f "$integration_file" ]]
grep -q '^Status: integrated$' "$integration_file"
[[ -f "$TMP_ROOT/integration-smoke.txt" ]]
integration_commit="$(sed -n 's/^Integration commit: //p' "$integration_file")"
[[ "$integration_commit" == "$task_head_commit" ]]

rerun_integration_file="$(PATH="$TMP_BASE/bin:$PATH" TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_integrate.sh" T-001 worker-1)"
[[ "$rerun_integration_file" == "$integration_file" ]]
grep -q '^Status: integrated$' "$integration_file"
grep -q "^Integration commit: $integration_commit$" "$integration_file"

integrated_status="$(TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" "$TMP_ROOT/.agents/scripts/team_status.sh")"
case "$integrated_status" in
  *"T-001 owner=worker-1 phase=integrated"*) ;;
  *) echo "status did not show integrated" >&2; exit 1 ;;
esac

echo "smoke ok"
