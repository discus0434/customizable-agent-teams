#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_BASE="$(mktemp -d)"
TMP_ROOT="$TMP_BASE/repo"
TMP_CONFIG_FILE="$TMP_ROOT/.agents/config/agent-team.yaml"
trap 'rm -rf "$TMP_BASE"' EXIT

fail() {
  echo "blocked-worker dispatch test failed: $*" >&2
  exit 1
}

team() {
  TEAM_ROOT="$TMP_ROOT" \
    TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" \
    TEAM_DISABLE_NUDGE=1 \
    "$@"
}

new_root() {
  rm -rf "$TMP_ROOT"
  mkdir -p "$TMP_ROOT/.agents/queue/tasks" "$TMP_ROOT/.agents/queue/inbox"
  cp -R "$ROOT/.agents/scripts" "$TMP_ROOT/.agents/scripts"
  cp -R "$ROOT/.agents/config" "$TMP_ROOT/.agents/config"
  cp -R "$ROOT/.agents/docs" "$TMP_ROOT/.agents/docs"
  cp "$ROOT/.agents/agent-team.mk" "$TMP_ROOT/.agents/agent-team.mk"
  cp "$ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md"
  cp "$ROOT/.agents/queue/tasks/EXPRESS_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/EXPRESS_TEMPLATE.md"
  cp "$ROOT/.gitignore" "$TMP_ROOT/.gitignore"
  cp "$ROOT/AGENTS.md" "$TMP_ROOT/AGENTS.md"
  git -C "$TMP_ROOT" init -q
  git -C "$TMP_ROOT" config user.email test@example.invalid
  git -C "$TMP_ROOT" config user.name "Blocked Worker Test"
  git -C "$TMP_ROOT" add .
  git -C "$TMP_ROOT" commit -qm "isolated dispatch test base"
  team "$TMP_ROOT/.agents/scripts/team_common.sh" >/dev/null 2>&1 || true
}

make_task() {
  local task_id="$1"
  local worker="$2"
  local allowed_path="$3"
  cp "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/$task_id.md"
  perl -0pi -e "s/T-XXX/$task_id/g; s/Worker: general-worker-1/Worker: $worker/; s#\x60path/to/file\x60#\x60$allowed_path\x60#" \
    "$TMP_ROOT/.agents/queue/tasks/$task_id.md"
  team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" "$task_id" >/dev/null
}

write_state() {
  local task_id="$1"
  local worker="$2"
  local supervisor="$3"
  local status="$4"
  local base_commit
  base_commit="$(git -C "$TMP_ROOT" rev-parse HEAD)"
  TEAM_ROOT="$TMP_ROOT" TEAM_CONFIG_FILE="$TMP_CONFIG_FILE" TEAM_DISABLE_NUDGE=1 \
    bash -c 'source "$1/.agents/scripts/team_common.sh"; ensure_state_dirs; team_write_task_state "$2" manager "$3" "$4" "$5" "$6" "" "" "" "" false false "" not_applicable ""' \
    _ "$TMP_ROOT" "$task_id" "$worker" "$supervisor" "$status" "$base_commit"
}

dispatch() {
  local task_id="$1"
  local owner="${2:-manager}"
  team "$TMP_ROOT/.agents/scripts/team_dispatch.sh" --owner "$owner" "$task_id"
}

expect_dispatch_failure() {
  local task_id="$1"
  local expected="$2"
  local owner="${3:-manager}"
  local stderr_file="$TMP_BASE/failure-$task_id.err"
  if dispatch "$task_id" "$owner" > /dev/null 2> "$stderr_file"; then
    fail "$task_id dispatch unexpectedly succeeded"
  fi
  grep -Fq "$expected" "$stderr_file" \
    || fail "$task_id failure did not contain '$expected': $(cat "$stderr_file")"
}

# Basis: T-048 requires the normal lane to reject every status other than done
# or blocked for the candidate Worker and fixed Supervisor. Real: isolated
# team_dispatch, task lint, and state files. Fake: no panes or nudges. Risk:
# a blocked entry may hide a later active entry when scanning sorted states.
# Non-scope: Manager's external WIP/resource evidence is not inferred here.
# Internal changes: state storage and scan order may change while the observed
# active rejection and concrete diagnostic remain stable.
new_root
make_task T-ACTIVE general-worker-2 active-output.txt
make_task T-CANDIDATE general-worker-2 candidate-output.txt
write_state T-ACTIVE general-worker-2 general-reviewer-2 dispatched
expect_dispatch_failure T-CANDIDATE "implementation worker is busy: general-worker-2"

# Basis: T-048 requires a candidate to be checked against every blocked task
# retained by both the Worker and fixed Supervisor. Real: the same dispatch
# consumer and config pairing are used; Fake: isolated state only. Risk:
# Supervisor reuse could silently bypass the active guard. Non-scope: express
# dispatch and Manager-owned resources. Internal changes: pair lookup may move
# without changing the fixed-supervisor rejection.
new_root
make_task T-SUP-ACTIVE general-worker-3 supervisor-output.txt
make_task T-CANDIDATE general-worker-2 candidate-output.txt
write_state T-SUP-ACTIVE general-worker-3 general-reviewer-2 dispatched
expect_dispatch_failure T-CANDIDATE "implementation supervisor is busy: general-reviewer-2"

# Basis: T-048 requires the full fixed-Supervisor state scan even when the
# candidate Worker has no retained assignment of its own. Real: dispatch,
# parser/matcher, state writer, and message writer. Fake: isolated git root
# and disabled nudge. Risk: a Supervisor-only blocked task could be omitted
# from the path gate or its obligation could be consumed. Non-scope: Manager's
# WIP/resource evidence. Internal changes: pair/state enumeration may move
# while overlap diagnostics and old obligation identity remain observable.
new_root
make_task T-SUP-BLOCKED general-worker-3 supervisor-blocked/
make_task T-CANDIDATE general-worker-2 supervisor-blocked/file.txt
write_state T-SUP-BLOCKED general-worker-3 general-reviewer-2 blocked
supervisor_state="$TMP_ROOT/.agents/queue/state/tasks/T-SUP-BLOCKED.json"
supervisor_hash="$(sha256sum "$supervisor_state" | awk '{print $1}')"
supervisor_pending_id="$(team "$TMP_ROOT/.agents/scripts/team_send.sh" --from manager --type request --task T-SUP-BLOCKED general-reviewer-2 "supervisor blocked obligation")"
supervisor_pending_id="$(printf '%s\n' "$supervisor_pending_id" | sed -n 's/^message_id=//p')"
[[ -n "$supervisor_pending_id" ]] || fail "supervisor-only pending message id was not returned"
[[ ! -e "$TMP_ROOT/.agents/queue/state/tasks/T-CANDIDATE.json" ]] || fail "candidate Worker had a retained state before dispatch"
expect_dispatch_failure T-CANDIDATE "task path contracts overlap: T-CANDIDATE and T-SUP-BLOCKED"
grep -Fq "candidate path 'supervisor-blocked/file.txt' intersects blocked path 'supervisor-blocked/'" \
  "$TMP_BASE/failure-T-CANDIDATE.err" || fail "Supervisor-only overlap diagnostic omitted path details"
[[ "$(sha256sum "$supervisor_state" | awk '{print $1}')" == "$supervisor_hash" ]] || fail "Supervisor-only blocked state changed on overlap rejection"
grep -Fq "$supervisor_pending_id" "$TMP_ROOT/.agents/queue/inbox/general-reviewer-2.jsonl" \
  || fail "Supervisor-only pending message disappeared on overlap rejection"
[[ ! -f "$TMP_ROOT/.agents/queue/state/processed/general-reviewer-2/$supervisor_pending_id" ]] \
  || fail "Supervisor-only pending message was processed on overlap rejection"

# Basis: T-048 permits disjoint dispatch against a blocked task retained only
# by the fixed Supervisor and requires old state/pending invariance. Real:
# same dispatch/state/message writers and exact diagnostics. Fake: isolated
# root with no candidate Worker state. Risk: Supervisor-only blocked state may
# incorrectly make a disjoint candidate busy or mutate its pending obligation.
# Non-scope: WIP/resource gate. Internal changes: dispatch persistence may move
# while candidate success and old identity/hash remain stable.
new_root
make_task T-SUP-BLOCKED general-worker-3 supervisor-only.txt
make_task T-CANDIDATE general-worker-2 candidate-output.txt
write_state T-SUP-BLOCKED general-worker-3 general-reviewer-2 blocked
supervisor_state="$TMP_ROOT/.agents/queue/state/tasks/T-SUP-BLOCKED.json"
supervisor_hash="$(sha256sum "$supervisor_state" | awk '{print $1}')"
supervisor_pending_id="$(team "$TMP_ROOT/.agents/scripts/team_send.sh" --from manager --type request --task T-SUP-BLOCKED general-reviewer-2 "supervisor blocked obligation")"
supervisor_pending_id="$(printf '%s\n' "$supervisor_pending_id" | sed -n 's/^message_id=//p')"
[[ -n "$supervisor_pending_id" ]] || fail "supervisor-only pending message id was not returned"
[[ ! -e "$TMP_ROOT/.agents/queue/state/tasks/T-CANDIDATE.json" ]] || fail "candidate Worker had a retained state before dispatch"
dispatch T-CANDIDATE >/dev/null
grep -Fq '"status":"dispatched"' "$TMP_ROOT/.agents/queue/state/tasks/T-CANDIDATE.json" \
  || fail "Supervisor-only disjoint candidate was not dispatched"
[[ "$(sha256sum "$supervisor_state" | awk '{print $1}')" == "$supervisor_hash" ]] \
  || fail "Supervisor-only blocked state changed on disjoint dispatch"
grep -Fq "$supervisor_pending_id" "$TMP_ROOT/.agents/queue/inbox/general-reviewer-2.jsonl" \
  || fail "Supervisor-only pending message disappeared on disjoint dispatch"
[[ ! -f "$TMP_ROOT/.agents/queue/state/processed/general-reviewer-2/$supervisor_pending_id" ]] \
  || fail "Supervisor-only pending message was processed on disjoint dispatch"

# Basis: T-048 acceptance requires blocked+disjoint success while preserving
# old state and pending obligations. Real: dispatch, state writer, message
# writer, parser, and matcher. Fake: isolated git root and disabled nudge.
# Risk: the exception could mutate blocked state or consume its pending message.
# Non-scope: WIP/resource ownership remains Manager-only. Internal changes:
# dispatch persistence may change while old state/message identity is stable.
new_root
make_task T-BLOCKED general-worker-2 blocked-output.txt
make_task T-CANDIDATE general-worker-2 candidate-output.txt
write_state T-BLOCKED general-worker-2 general-reviewer-2 blocked
blocked_state="$TMP_ROOT/.agents/queue/state/tasks/T-BLOCKED.json"
blocked_hash="$(sha256sum "$blocked_state" | awk '{print $1}')"
pending_id="$(team "$TMP_ROOT/.agents/scripts/team_send.sh" --from manager --type request --task T-BLOCKED general-worker-2 "blocked obligation")"
pending_id="$(printf '%s\n' "$pending_id" | sed -n 's/^message_id=//p')"
[[ -n "$pending_id" ]] || fail "blocked pending message id was not returned"
dispatch_output="$(dispatch T-CANDIDATE)"
candidate_state="$TMP_ROOT/.agents/queue/state/tasks/T-CANDIDATE.json"
[[ "$dispatch_output" == "$candidate_state" ]] || fail "dispatch stdout was not the candidate state path"
grep -Fq '"status":"dispatched"' "$candidate_state" || fail "candidate was not dispatched"
grep -Fq '"supervisor":"general-reviewer-2"' "$candidate_state" || fail "fixed supervisor was not recorded"
[[ "$(sha256sum "$blocked_state" | awk '{print $1}')" == "$blocked_hash" ]] || fail "blocked state changed"
grep -Fq "$pending_id" "$TMP_ROOT/.agents/queue/inbox/general-worker-2.jsonl" || fail "blocked pending message disappeared"
[[ ! -f "$TMP_ROOT/.agents/queue/state/processed/general-worker-2/$pending_id" ]] || fail "blocked pending message was processed"
grep -Fq 'Supervisor: general-reviewer-2' "$TMP_ROOT/.agents/queue/tasks/T-CANDIDATE.md" || fail "candidate task did not record fixed supervisor"

# Basis: T-048 path ownership is an intersection gate, including directory
# containment. Real: existing matcher semantics against explicit contracts.
# Fake: only the temporary root and task files. Risk: overlapping candidate
# work could be dispatched beside blocked WIP. Non-scope: no WIP inference.
# Internal changes: the comparison implementation may be reorganized while a
# contained path remains rejected with both task IDs.
new_root
make_task T-BLOCKED general-worker-2 blocked/
make_task T-CANDIDATE general-worker-2 blocked/file.txt
write_state T-BLOCKED general-worker-2 general-reviewer-2 blocked
expect_dispatch_failure T-CANDIDATE "task path contracts overlap: T-CANDIDATE and T-BLOCKED"

# Basis: T-048 explicitly requires a later active state to reject even when a
# sorted earlier state is blocked. Real: sorted state scan and diagnostics.
# Fake: isolated state writer. Risk: first-blocked early return can authorize
# a third task while active work exists. Non-scope: path checking after reject.
# Internal changes: state enumeration may change while all non-done statuses
# remain enforced.
new_root
make_task T-BLOCKED-FIRST general-worker-2 blocked-first.txt
make_task T-ACTIVE-LATER general-worker-2 active-later.txt
make_task T-CANDIDATE general-worker-2 candidate-output.txt
write_state T-BLOCKED-FIRST general-worker-2 general-reviewer-2 blocked
write_state T-ACTIVE-LATER general-worker-2 general-reviewer-2 dispatched
expect_dispatch_failure T-CANDIDATE "implementation worker is busy: general-worker-2"

# Basis: T-048 permits redispatch after the active task reaches done while a
# disjoint blocked obligation remains. Real: state writer plus dispatch state
# creation. Fake: isolated task lifecycle. Risk: done may remain incorrectly
# busy or blocked may be resumed implicitly. Non-scope: Manager switch timing.
# Internal changes: state transitions may move while done/blocked semantics stay
# observable through successful candidate dispatch and unchanged blocked state.
new_root
make_task T-BLOCKED general-worker-2 blocked-output.txt
make_task T-ACTIVE general-worker-2 active-output.txt
make_task T-CANDIDATE general-worker-2 candidate-output.txt
write_state T-BLOCKED general-worker-2 general-reviewer-2 blocked
write_state T-ACTIVE general-worker-2 general-reviewer-2 done
blocked_state="$TMP_ROOT/.agents/queue/state/tasks/T-BLOCKED.json"
blocked_hash="$(sha256sum "$blocked_state" | awk '{print $1}')"
dispatch T-CANDIDATE >/dev/null
grep -Fq '"status":"dispatched"' "$TMP_ROOT/.agents/queue/state/tasks/T-CANDIDATE.json" || fail "done active state blocked redispatch"
[[ "$(sha256sum "$blocked_state" | awk '{print $1}')" == "$blocked_hash" ]] || fail "blocked state changed after done redispatch"

# Basis: T-048 requires unreadable and unprovable Allowed paths to fail closed.
# Real: dispatch's contract parser/matcher boundary. Fake: missing task file or
# wildcard contract in an isolated root. Risk: parse failure could become an
# accidental disjoint success. Non-scope: valid explicit path intersection.
# Internal changes: parser internals may change while both unsafe inputs reject.
new_root
make_task T-CANDIDATE general-worker-2 candidate-output.txt
write_state T-MISSING general-worker-2 general-reviewer-2 blocked
expect_dispatch_failure T-CANDIDATE "task contract is unreadable: $TMP_ROOT/.agents/queue/tasks/T-MISSING.md"

new_root
make_task T-BLOCKED general-worker-2 'blocked/*.txt'
make_task T-CANDIDATE general-worker-2 candidate-output.txt
write_state T-BLOCKED general-worker-2 general-reviewer-2 blocked
expect_dispatch_failure T-CANDIDATE "task path contracts cannot be proven disjoint"

# Basis: T-048 excludes express tasks from the normal blocked exception. Real:
# express task lint, Lead-only lane checks, and worker busy helper. Fake:
# isolated blocked state. Risk: a blocked normal state could accidentally make
# an express task eligible. Non-scope: normal fixed Supervisor handling.
# Internal changes: express routing may move while blocked remains busy.
new_root
cp "$TMP_ROOT/.agents/queue/tasks/EXPRESS_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-E-CANDIDATE.md"
perl -0pi -e 's/T-E-001/T-E-CANDIDATE/g; s#\x60path/to/express/file\x60#\x60express-output.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-E-CANDIDATE.md"
team "$TMP_ROOT/.agents/scripts/team_task_lint.sh" T-E-CANDIDATE >/dev/null
cp "$TMP_ROOT/.agents/queue/tasks/GENERAL_TEMPLATE.md" "$TMP_ROOT/.agents/queue/tasks/T-BLOCKED.md"
perl -0pi -e 's/T-XXX/T-BLOCKED/g; s/Worker: general-worker-1/Worker: express-worker-1/; s#\x60path/to/file\x60#\x60blocked-express.txt\x60#' \
  "$TMP_ROOT/.agents/queue/tasks/T-BLOCKED.md"
write_state T-BLOCKED express-worker-1 "" blocked
expect_dispatch_failure T-E-CANDIDATE "implementation worker is busy: express-worker-1" lead

printf '%s\n' "blocked-worker dispatch regression passed"
