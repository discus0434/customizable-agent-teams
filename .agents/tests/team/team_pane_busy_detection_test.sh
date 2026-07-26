#!/usr/bin/env bash

# agentが他paneをtmux capture-paneで覗くと、相手CLIのlive chromeが自分の
# transcriptへ焼き付く。焼き付きを自分のbusyと誤認すると、そのpane宛のwakeが
# 永久に届かず、出力が無いので残骸も流れない自己deadlockになる。
# 判定が「自分のCLIの形」かつ「画面末尾」に限定されていることを外から確認する。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_BASE="$(mktemp -d)"
SESSION="team-busy-test-$$"
FIXTURE="$TMP_BASE/fixture.txt"
FAILURES=0

cleanup() {
  set +e
  tmux kill-session -t "$SESSION" 2>/dev/null
  rm -rf "$TMP_BASE"
}
trap cleanup EXIT

# shellcheck source=/dev/null
source "$ROOT/.agents/scripts/team_common.sh"

command -v tmux >/dev/null 2>&1 || {
  echo "required command not found: tmux" >&2
  exit 1
}

CODEX_LIVE='◦ Working (27s • esc to interrupt)'
CLAUDE_LIVE='  ⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt · ← for agents'

# paneの可視領域を fixture の内容そのものにする
render() {
  printf '%s\n' "$@" > "$FIXTURE"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  tmux new-session -d -s "$SESSION" -x 200 -y 50 "clear; cat '$FIXTURE'; sleep 600"
  local pane
  pane="$(tmux list-panes -t "$SESSION" -F '#{pane_id}' | head -n 1)"
  # catの出力が描画されるまで待つ
  local waited=0
  while (( waited < 50 )); do
    if tmux capture-pane -t "$pane" -p | grep -q '[^[:space:]]'; then
      break
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  printf '%s' "$pane"
}

check() {
  local label="$1" expected="$2" cli="$3" pane="$4"
  local actual="idle"
  if team_tmux_pane_is_busy "$pane" "$cli"; then
    actual="busy"
  fi
  if [[ "$actual" == "$expected" ]]; then
    echo "ok   $label ($cli -> $actual)"
  else
    echo "FAIL $label ($cli -> $actual, expected $expected)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# 自分のCLIのlive chromeはbusyとして観測できる
pane="$(render "$CODEX_LIVE" "" "" "› Run /review on my current changes" "" "  gpt-5.6-sol xhigh · ~/projects/molt")"
check "codex live chrome" busy codex "$pane"

pane="$(render "✽ Working… (1m 36s · ↓ 5.5k tokens)" "" "$CLAUDE_LIVE")"
check "claude live chrome" busy claude "$pane"

# 回帰: 他CLIのchromeが焼き付いても自分のbusyにはならない。
# 末尾窓にも入る位置へ置き、CLI別判定だけで守れていることを確かめる
pane="$(render "$CLAUDE_LIVE" "" "" "› Run /review on my current changes" "" "  gpt-5.6-sol xhigh · ~/projects/molt")"
check "claude chrome burned into codex pane" idle codex "$pane"

pane="$(render "$CODEX_LIVE" "" "❯ " "")"
check "codex chrome burned into claude pane" idle claude "$pane"

# 同じCLIの残骸でも、live chromeが居ない位置まで流れていればbusyではない
filler=()
for i in $(seq 1 20); do filler+=("transcript line $i"); done
pane="$(render "$CODEX_LIVE" "${filler[@]}" "› Run /review on my current changes" "" "  gpt-5.6-sol xhigh · ~/projects/molt")"
check "same-CLI chrome scrolled out of the tail window" idle codex "$pane"

# cli不明時は従来通り広く採り、安全側(配送しない)へ倒す
pane="$(render "$CLAUDE_LIVE")"
check "unknown cli falls back to the broad pattern" busy "" "$pane"

if (( FAILURES > 0 )); then
  echo "$FAILURES check(s) failed" >&2
  exit 1
fi
echo "all checks passed"
