#!/usr/bin/env bash

# backlogはteamの供給源を一段上に足す層。人間との対話で受けた依頼と作業中に
# 見つけた次の意図を、Leadがカードとして積む。擦り合わせのタイミングは
# 引く瞬間に縛らず、人間が求めたらいつでもよい。確定したspecはカード本文の
# `## Spec`節に残り、それが「clarify済み」の印になる(第3の状態は作らない)。
# intakeが完了したらLeadがspec確定済みを先頭にカードを引き、intakeへ契約化する。
# カードはfileが真実。ManagerとWorkerはbacklogを読まない(intakeの品質ゲートを
# 迂回させない)。状態はopenとconsumedの2つだけ。
# usage:
#   team_backlog.sh list
#   team_backlog.sh add --title <title> [--priority high|normal|low] [--body <text>|--body-file <path>]
#   team_backlog.sh pull <card_id> --intake <message_id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/team_common.sh"

BACKLOG_DIR="$TEAM_QUEUE_DIR/backlog"

usage() {
  cat >&2 <<'USAGE'
usage:
  team_backlog.sh list
  team_backlog.sh add --title <title> [--priority high|normal|low] [--body <text>|--body-file <path>]
  team_backlog.sh pull <card_id> --intake <message_id>
USAGE
}

card_file_of() {
  printf '%s/%s.md\n' "$BACKLOG_DIR" "$1"
}

require_card() {
  local card_id="$1"
  local card_file
  card_file="$(card_file_of "$card_id")"
  [[ -f "$card_file" ]] || die_rule \
    "backlog card not found: $card_id" \
    "cards live in $BACKLOG_DIR as <card_id>.md" \
    "run make backlog to list card ids"
  printf '%s\n' "$card_file"
}

priority_rank() {
  case "$1" in
    high) printf '0\n' ;;
    normal) printf '1\n' ;;
    low) printf '2\n' ;;
    *) printf '1\n' ;;
  esac
}

cmd_list() {
  local card_file card_id title priority status created intake spec_rank spec_label
  local -a open_rows consumed_rows

  open_rows=()
  consumed_rows=()
  for card_file in "$BACKLOG_DIR"/*.md; do
    [[ -f "$card_file" ]] || continue
    card_id="$(basename "$card_file" .md)"
    title="$(team_task_markdown_field "$card_file" "Title" || true)"
    priority="$(team_task_markdown_field "$card_file" "Priority" || true)"
    status="$(team_task_markdown_field "$card_file" "Status" || true)"
    created="$(team_task_markdown_field "$card_file" "Created at" || true)"
    intake="$(team_task_markdown_field "$card_file" "Intake ref" || true)"
    # spec確定済みは擦り合わせ無しでintake化できるので先頭に置く
    spec_rank="1"
    spec_label=""
    if grep -q '^## Spec' "$card_file"; then
      spec_rank="0"
      spec_label="/spec"
    fi
    case "$status" in
      open)
        open_rows+=("$spec_rank|$(priority_rank "$priority")|$created|  $card_id [${priority:-normal}$spec_label] $title") ;;
      consumed)
        consumed_rows+=("$created|  $card_id -> ${intake:-none} $title") ;;
    esac
  done

  echo "open:"
  if [[ "${#open_rows[@]}" -gt 0 ]]; then
    printf '%s\n' "${open_rows[@]}" | sort | cut -d'|' -f4-
  else
    echo "  none"
  fi
  echo "consumed (latest 5):"
  if [[ "${#consumed_rows[@]}" -gt 0 ]]; then
    printf '%s\n' "${consumed_rows[@]}" | sort -r | head -n 5 | cut -d'|' -f2-
  else
    echo "  none"
  fi
}

cmd_add() {
  local title=""
  local priority="normal"
  local body=""
  local body_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) [[ $# -ge 2 ]] || die "--title requires a value"; title="$2"; shift 2 ;;
      --priority) [[ $# -ge 2 ]] || die "--priority requires a value"; priority="$2"; shift 2 ;;
      --body) [[ $# -ge 2 ]] || die "--body requires a value"; body="$2"; shift 2 ;;
      --body-file) [[ $# -ge 2 ]] || die "--body-file requires a path"; body_file="$2"; shift 2 ;;
      *) die "unknown add option: $1" ;;
    esac
  done

  [[ -n "$title" && "$title" != *$'\n'* ]] || die_rule \
    "backlog card title must be one non-empty line" \
    "the title is the card's identity in every listing" \
    "pass TITLE='<one line>'"
  case "$priority" in
    high|normal|low) ;;
    *) die "card priority must be high, normal, or low: $priority" ;;
  esac
  if [[ -n "$body_file" ]]; then
    [[ -f "$body_file" ]] || die "body file not found: $body_file"
    body="$(cat "$body_file")"
  fi

  local card_id card_file
  card_id="card_$(date -u +%Y%m%dT%H%M%SZ)_$$_${RANDOM}"
  card_file="$(card_file_of "$card_id")"
  {
    printf '# Backlog: %s\n\n' "$title"
    printf 'Title: %s\n' "$title"
    printf 'Priority: %s\n' "$priority"
    printf 'Status: open\n'
    printf 'Created at: %s\n' "$(team_now_utc)"
    printf 'Intake ref: none\n'
    printf '\n## Card\n\n'
    printf '%s\n' "${body:-"(本文なし。titleが意図のすべて)"}"
  } > "$card_file"
  printf 'card_id=%s\n' "$card_id"
  printf '%s\n' "$card_file"
}

require_status() {
  local card_file="$1"
  local expected="$2"
  local action="$3"
  local status
  status="$(team_task_markdown_field "$card_file" "Status" || true)"
  [[ "$status" == "$expected" ]] || die_rule \
    "backlog card is not $expected: $(basename "$card_file" .md)" \
    "card status is ${status:-missing}" \
    "$action"
}

cmd_pull() {
  local card_id="${1:-}"
  shift || true
  local intake=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --intake) [[ $# -ge 2 ]] || die "--intake requires a value"; intake="$2"; shift 2 ;;
      *) die "unknown pull option: $1" ;;
    esac
  done
  [[ -n "$card_id" ]] || { usage; exit 2; }
  [[ -n "$intake" ]] || die_rule \
    "backlog pull requires the intake message id" \
    "consumed cards stay traceable through Intake ref" \
    "send the intake first, then run make backlog-pull CARD=$card_id INTAKE=<message_id>"

  local card_file
  card_file="$(require_card "$card_id")"
  require_status "$card_file" "open" "consumed cards cannot be consumed again"
  team_update_markdown_field "$card_file" "Status" "consumed"
  team_update_markdown_field "$card_file" "Intake ref" "$intake"
  printf 'card=%s\nstatus=consumed\nintake_ref=%s\n' "$card_id" "$intake"
}

command="${1:-}"
shift || true
case "$command" in
  list) cmd_list "$@" ;;
  add) cmd_add "$@" ;;
  pull) cmd_pull "$@" ;;
  -h|--help) usage ;;
  *) usage; exit 2 ;;
esac
