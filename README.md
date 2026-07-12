# customizable-agent-teams

ローカルの tmux 上で、Claude Code と Codex を役割分担させるプロジェクトテンプレートです。人間との対話、進行管理、技術判断、調査、一般実装、難度の高い実装、frontend 実装、task-local supervision、release 判断を別々の agent が担当します。

人間は Lead にだけ話します。Manager は依存関係と dispatch を担い、General Worker または Hard Task Worker と General Reviewer、Frontend Worker と Frontend Critic の固定ペアが実装を進めます。4体の Research Worker はコードベース調査、フィジビリティ確認、Web検索を並列処理します。

![customizable-agent-teams workflow](.agents/assets/agent-team-flow.png)

## 特徴

- **Lead は人間との共同思考に集中** — Lead は実装も dispatch もせず、質問、承認取得、意図の翻訳に専念します。
- **Manager がチーム運用を所有** — task 作成、Worker 選択、dispatch、escalation、done 判定、release bundle 作成、`STATE.md` 更新を担当します。
- **Strategist を常駐** — 深い bug 調査、比較、実行計画を成果物として残します。
- **Architect が技術方針を所有** — 抽象化、境界、テスト方針、統合時の一貫性を見ます。
- **Release Captain が全体確認** — task 単位の OK とは別に、bundle が人間へ完了報告できる状態かを判定します。
- **General lane** — 3組の General Worker / General Reviewer が主要な実装を担当します。Manager は関連領域の継続性を見て Worker を選び、Supervisor は固定ペアから決まります。
- **Hard Task lane** — 2組の Hard Task Worker / General Reviewer が、難しいデバッグ、複数境界にまたがる変更、アルゴリズムや設計判断を伴う実装を担当します。
- **Research pool** — 4体の Research Worker がコードベース、feasibility、Web を調査し、根拠と結果を caller へ直接返します。
- **Frontend lane** — Frontend Worker が実画面を見ながら実装し、Claude Opus の Frontend Critic が view direction と完成画面を別視点で厳しく確認します。
- **shared root** — 全 agent が同じ repo root で動きます。venv / node_modules / `.env` / direnv を重複させません。
- **CLI / model の混在** — `.agents/config/agent-team.yaml` の agent records で CLI・model・effort・人数・固定ペアを変更できます。

## 仕組み

| 役割 | 配置 | 責務 |
| --- | --- | --- |
| **Lead** | tmux `lead` pane | 人間の唯一の窓口。曖昧な依頼を擦り合わせ、必要な判断を人間に確認し、Manager に依頼する。project code は編集しない。 |
| **Manager** | tmux `manager` pane | task 分解、Worker 選択、dispatch、escalation 対応、done 判定、release bundle 作成、`.agents/state/STATE.md` の主編集者。 |
| **Strategist** | tmux `strategist` pane | 深い調査、複数案比較、実行計画。 |
| **Architect** | tmux `architect` pane | 技術方針、設計一貫性、境界、テスト期待値を判断する。 |
| **Release Captain** | tmux `release-captain` pane | 複数 task のまとまりを確認し、`SHIP` / `FIX` / `BLOCKED` を返す。 |
| **General Worker** | tmux `general-worker-N` pane | 主力実装、検証、task commit、report。 |
| **Hard Task Worker** | tmux `hard-task-worker-N` pane | 難しい実装やデバッグを深く調査し、根本原因から解決する。 |
| **General Reviewer** | tmux `general-reviewer-N` pane | 固定 General Worker または Hard Task Worker の相談、途中 feedback、final review。 |
| **Research Worker** | tmux `research-worker-N` pane | codebase、feasibility、Web の事実調査。project code は編集しない。 |
| **Frontend Worker** | tmux `frontend-worker-N` pane | view direction を固め、実画面を反復確認しながら frontend を実装する。 |
| **Frontend Critic** | tmux `frontend-critic-N` pane | view direction、visual、interaction、accessibility、frontend code と tests を supervision する。 |

```text
Human
  -> Lead
  -> Manager
  -> General Worker + General Reviewer
     or Hard Task Worker + General Reviewer
     or Frontend Worker + Frontend Critic
  -> Research Worker pool when evidence is needed
  -> Strategist / Architect when deeper thinking is needed
  -> Supervisor OK/FIX/ASK_MANAGER
  -> Manager marks done
  -> Release Captain SHIP/FIX/BLOCKED
  -> Lead reports completion
```

Escalation は狭い範囲で決められる role から順に上がります。

```text
General Worker -> General Reviewer -> Manager -> Lead -> Human
Hard Task Worker -> General Reviewer -> Manager -> Lead -> Human
Frontend Worker -> Frontend Critic -> Manager -> Lead -> Human
General Reviewer / Frontend Critic / Manager / Lead -> Architect
General Reviewer / Frontend Critic / Manager / Architect / Lead -> Strategist
Release Captain -> Architect
Lead / Manager / Strategist / Architect / Release Captain -> Research Worker pool
```

## 必要なツール

チームの起動には `git` `make` `bash` `tmux` `direnv` と、使う coding agent の CLI（`claude` / `codex` など）が必要です。GitHub 操作は `gh` を使います。

日常の repo 調査には `ripgrep` `fd` `bat` `git-delta` があると便利です。選んだ stack の toolchain（例: Python なら `uv`、TypeScript なら `pnpm` / `node`）も bootstrap で使います。

<details>
<summary>macOS でまとめてインストール</summary>

```bash
brew install gh ripgrep fd bat git-delta direnv tmux pnpm node python uv
brew install --cask codex
npm install -g @anthropic-ai/claude-code
```

</details>

<details>
<summary>Linux（apt 系）でまとめてインストール</summary>

```bash
npm install -g @openai/codex @anthropic-ai/claude-code
wget -qO- https://get.pnpm.io/install.sh | sh -
wget -qO- https://astral.sh/uv/install.sh | sh

type -p wget >/dev/null || (sudo apt update && sudo apt install -y wget)
sudo mkdir -p -m 755 /etc/apt/keyrings
out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
sudo mkdir -p -m 755 /etc/apt/sources.list.d
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt-get install -y gh ripgrep fd-find bat direnv tmux python3 nodejs npm
command -v fd >/dev/null || sudo ln -s /usr/bin/fdfind /usr/local/bin/fd
command -v bat >/dev/null || sudo ln -s /usr/bin/batcat /usr/local/bin/bat
```

</details>

## Quick Start

1. このテンプレートから新しい repo を作り、clone する。

2. 現在の shell で `direnv` を有効にする。

   <details>
   <summary>direnv フックを shell に追加する（未設定の場合）</summary>

   ```bash
   if [ -n "${ZSH_VERSION:-}" ]; then
     rc="$HOME/.zshrc"; hook='eval "$(direnv hook zsh)"'
   elif [ -n "${BASH_VERSION:-}" ]; then
     rc="$HOME/.bashrc"; hook='eval "$(direnv hook bash)"'
   else
     echo "Add the direnv hook for your shell, then rerun Quick Start." >&2; exit 1
   fi
   eval "$hook"
   grep -Fqx "$hook" "$rc" 2>/dev/null || printf '\n%s\n' "$hook" >> "$rc"
   ```

   </details>

3. bootstrap を開始する。

   ```bash
   make bootstrap
   make team-attach
   ```

   `lead` pane が「何を作るか」を最初の 1 問として聞いてきます。Lead は一度に質問を並べず、回答ごとに作るもの・stack・entrypoint・`make post-change`・`make smoke` を狭めます。

4. Lead が bootstrap 方針を固め、Manager に初期化依頼を送ったら、tmux から detach（`Ctrl-b` のあと `d`）し、repo root で次を実行する。

   ```bash
   make bootstrap-team
   make team-attach
   ```

   既存の Lead pane はそのまま、残りの role が起動します。以降は Lead pane で進行を見守り、Lead から質問されたときだけ答えます。

## チームの設定

`.agents/config/agent-team.yaml` の `agents:` list で役割、CLI、model、effort、window、agent 数を変更できます。General Worker、Hard Task Worker、Frontend Worker は `supervisor:` で固定ペアを指定します。

起動 command は `cli / model / effort` から生成されます。Claude Code には `--dangerously-skip-permissions`、Codex には `--dangerously-bypass-approvals-and-sandbox` が常に付きます。Codex の Research Worker には Web検索も有効になります。

## 日常運用

| 操作 | コマンド | 主に使う役割 |
| --- | --- | --- |
| チーム起動 / 再起動 | `make team-start` → `make team-attach` | 人間 |
| 状態・進捗確認 | `make team-status` / `make state` | Manager / Lead |
| agent surface 確認 | `make agent-surfaces` | Manager / Supervisor |
| inbox 確認 | `make inbox AGENT=general-worker-1` | 全員 |
| 未送信プロンプトの送信 | `make team-submit AGENT=general-worker-1` | 全員 |
| agent 連絡 | `make team-send FROM=lead TO=manager TYPE=intake TASK=- BODY="..."` | 全員 |
| 長文の agent 連絡 | `make team-send FROM=lead TO=manager TYPE=intake TASK=- BODY_FILE=.agents/queue/state/tmp/message.md` | 全員 |
| 記録のみの note | `make team-send TO=general-worker-1 TYPE=note TASK=T-001 BODY="..."` | 全員 |
| inbox へ返信 | `make team-reply IN_REPLY_TO=<message_id> TYPE=answer BODY_FILE=.agents/queue/state/tmp/reply.md` | 全員 |
| research 依頼 | `make team-send TO=research-worker BODY_FILE=.agents/queue/state/tmp/research.md` | Lead / Manager / Strategist / Architect / Release Captain |
| task dispatch | `make dispatch TASK=T-001` | Manager |
| task contract 確認 | `make task-lint TASK=T-001` | Manager / Supervisor |
| 検証ゲート | `make post-change` / `make smoke` | Implementation Worker |
| task の変更を commit | `make task-commit TASK=T-001 MESSAGE="<summary>"` | Implementation Worker |
| supervision checkpoint | `make team-send TO=<supervisor_id> TYPE=supervision_checkpoint TASK=T-001 BODY_FILE=.agents/queue/state/tmp/checkpoint.md` | Implementation Worker |
| supervision feedback | `make team-send TO=<worker_id> TYPE=supervision_feedback TASK=T-001 BODY="..."` | Supervisor |
| manager 差し戻し | `make team-send TO=<pair_agent_id> TYPE=manager_fix TASK=T-001 BODY_FILE=.agents/queue/state/tmp/manager-fix.md` | Manager |
| strategist 相談 | `make team-send TO=strategist TASK=T-001 BODY="..."` | Lead / Manager / Supervisor / Architect |
| architect 相談 | `make team-send TO=architect TASK=T-001 BODY="..."` | Lead / Manager / Supervisor / Release Captain |
| implementation report | `make report TASK=T-001 STATUS=needs_supervision` | Implementation Worker |
| direction decision | `make direction-report TASK=T-001 DECISION=PROCEED` | Frontend Critic |
| supervision decision | `make supervision-report TASK=T-001 DECISION=OK` | General Reviewer / Frontend Critic |
| done 更新 | `make state-update TASK=T-001 STATUS=done` | Manager |
| release bundle 準備 | `make release-prepare BUNDLE=R-001 TASKS="T-001 T-002"` | Manager |
| release review 依頼 | `make release-request BUNDLE=R-001 TASKS="T-001 T-002"` | Manager |
| release decision | `make release-report BUNDLE=R-001 RELEASE_CAPTAIN=release-captain DECISION=SHIP` | Release Captain |
| 完了報告準備 | `make team-send FROM=manager TO=lead TYPE=completion_ready BUNDLE=R-001 BODY="..."` | Manager |
| 完了報告済み通知 | `make team-send FROM=lead TO=manager TYPE=completion_ack BUNDLE=R-001 BODY="..."` | Lead |
| 停止 | `make team-stop` | 人間 |

team pane の中では `TEAM_AGENT_ID` が sender になります。repo shell から直接送る場合は `FROM=<agent_id>` を指定します。
repo shell から直接 dispatch する場合は `MANAGER=<manager_id>` も指定します。

## Repository Layout

| パス | 内容 |
| --- | --- |
| `AGENTS.md` | 全 agent 共通の作業ルール（`CLAUDE.md` は symlink） |
| `.agents/config/agent-team.yaml` | agent・role・model・effort・固定 supervisor 設定 |
| `.agents/agent-team.mk` | agent team 操作用の Make targets |
| `.agents/harness.mk` | このテンプレート自体の保守用 test target |
| `.agents/docs/TEAM_PROTOCOL.md` | agent team の手順 |
| `.agents/state/STATE.md` | 現在の whole picture |
| `.agents/state/MEMORY.md` | 中長期の rules / tips / pitfalls / user preferences |
| `.agents/skills/` | Claude Code / Codex 共通の skill（`.claude/skills`・`.codex/skills` は symlink） |
| `.agents/scripts/` | 各コマンドの実体 |
| `.agents/queue/` | tasks / reports / reviews / critiques / visuals / research / strategy / architecture / releases / proposals / state |
| `.agents/tests/team/` | このテンプレート自体の test |
| `Makefile` | project の `post-change` / `smoke` と `.agents/agent-team.mk` の import |

## ドキュメント

- [`AGENTS.md`](AGENTS.md) — 役割ごとの作業ルール
- [`.agents/docs/TEAM_PROTOCOL.md`](.agents/docs/TEAM_PROTOCOL.md) — role と lifecycle の全体像
- [`.agents/state/MEMORY.md`](.agents/state/MEMORY.md) — 共有 memory のルール
