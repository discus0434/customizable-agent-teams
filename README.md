# customizable-agent-teams

ローカルの tmux 上で、複数の coding agent（Claude Code / Codex など）を **lead / worker / verifier** のチームとして動かすためのプロジェクトテンプレートです。人間は lead に話しかけるだけで、task → 実装 → 検証 → review → integrate という開発ループがそのまま回ります。

単一の agent に長い作業を丸投げすると、文脈が混ざり、検証が抜けやすくなります。このテンプレートは作業を task と report に分け、worker が root 上で実装し、機械的な検証ゲートと review を通ったものだけを integrated として記録します。CLI と model は役割ごとに差し替えられるので、たとえば lead に Claude Opus 4.8、worker に Codex GPT-5.5、verifier に Claude Opus 4.8、といった組み合わせを 1 つの設定ファイルで指定できます。

![customizable-agent-teams workflow](.agents/assets/agent-team-flow.png)

## 特徴

- **役割分担** — 依頼を受ける lead、実装する worker、変更を審査する verifier に責務を分離。
- **root 共有** — 全 agent が同じ repo root で動くため、venv / node_modules / `.env` / direnv を二重に持ちません。実装 task は dispatch 時に 1 本ずつ active になります。
- **強制された検証ゲート** — `make post-change`（format / lint / type / test）と `make smoke`（利用者向け動作の確認）を通らないと report にも integrate にも進めません。
- **noninteractive review** — `make review` が task・report・committed diff を verifier に渡し、`OK` / `FIX` / `ASK_LEAD` を機械的に返します。verifier は常駐せず、review のたびに 1 回だけ起動されます。
- **file mailbox + tmux nudge** — agent 間の通信本文は queue 上の file が正本。tmux には短い `inbox <agent_id>` という合図だけを流します。
- **CLI / model の混在** — `.agents/config/agent-team.yaml` で役割ごとに CLI・model・起動コマンドを設定。チーム構成や worker 数を 1 ファイルで変更できます。
- **対話的 bootstrap** — 最初の会話で「何を作るか」「言語と toolchain」「`make post-change`」「`make smoke`」を決め、テンプレート由来の文言を実プロジェクトの内容に置き換えます。

## 仕組み

### 役割

| 役割 | 配置 | 責務 |
| --- | --- | --- |
| **lead** | tmux `lead` pane（人間の窓口） | 依頼を受け、小さな変更は直接行い、大きな変更を task に分けて dispatch。worker の質問に答え、review を通った report だけを `make integrate` で統合。`MEMORY.md` の唯一の編集者。 |
| **worker** | tmux `worker-N` pane | dispatch された task を root 上で実装。検証・smoke・review 対応・report 記入まで担当。`Allowed paths` / `Do not modify` を守る。 |
| **verifier** | `make review` 実行時に noninteractive 起動 | task・report・committed diff・検証 evidence を読み、`OK` / `FIX` / `ASK_LEAD` を返す。file は編集しない。 |

### task のライフサイクル

```text
lead が task 作成 ─▶ dispatch（root が clean であることを確認）
        ─▶ 実装 ─▶ make post-change / make smoke ─▶ commit
        ─▶ report ─▶ make review ─┬─ OK   ─▶ report を done に
                                   ├─ FIX  ─▶ 修正して再 review
                                   └─ ASK_LEAD ─▶ lead に相談
        ─▶ lead が make integrate（post-change + smoke + integration 記録）
```

### state は file で持つ

agent 間で共有する状態はすべて `TEAM_ROOT`（repo root）以下の file が正本です。agent 間の通知は inbox に残り、tmux には短い nudge だけが送られます。

- `tasks/` — task 本文 / `inbox/` — agent メッセージ / `reports/` — worker report
- `reviews/` — verifier 結果 / `integrations/` — lead 統合ログ / `state/` — ライフサイクル状態

## こんなときに使う

- **長い作業を別 context に分けたい** — lead は方針決定に集中し、worker が task/report/review の流れで実装します。
- **model や CLI を混ぜたい / 比較したい** — 役割や worker 単位で別の model を割り当てられます。
- **review を必須の関門にしたい** — 検証ゲートと noninteractive review を通らないものは統合されません。
- **agent に渡す作業を契約として明示したい** — task file に `Allowed paths`・`Acceptance`・`Verification` を書いて境界を固定できます。

## 必要なツール

`gh` `ripgrep` `fd` `bat` `jq` `git-delta` `direnv` `tmux` と、使う coding agent の CLI（`claude` / `codex` など）、選んだ stack の toolchain（例: Python なら `uv`、TypeScript なら `pnpm` / `node`）。

<details>
<summary>macOS でまとめてインストール</summary>

```bash
brew install gh ripgrep fd bat jq yq git-delta direnv tmux pnpm node python uv
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
sudo apt-get install -y gh ripgrep fd-find bat jq direnv tmux python3 nodejs npm
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
   ```

   attach すると `lead` pane が「何を作るか」を最初の 1 問として聞いてきます。回答に応じて、作るもの・言語と package manager・formatter / linter / test runner・build command・`make post-change`・`make smoke`・README / AGENTS / package metadata / entrypoint がプロジェクト用に初期化されます。

4. bootstrap が固まったら tmux から detach（`Ctrl-b` のあと `d`）し、repo root で次を実行する。

   ```bash
   make bootstrap-finish
   ```

   完了すると、worker を含む `agent-team` tmux session に attach されます。以降は lead pane に依頼を入力するだけです。

## チームの設定

役割・model・CLI・worker 数は `.agents/config/agent-team.yaml` で変更します。

- `team.lead` — lead の CLI / model / tmux window / 起動コマンド
- `team.workers` — worker ごとの CLI / model / window / 起動コマンド（増減も可能）
- `team.review` — verifier の CLI / model / effort / timeout / 出力先

## 日常運用

agent はそれぞれ役割に沿って下記コマンドを使います。詳しい前提条件・チェック内容・state 遷移は [`.agents/docs/TEAM_PROTOCOL.md`](.agents/docs/TEAM_PROTOCOL.md) を参照してください。

| 操作 | コマンド | 主に使う役割 |
| --- | --- | --- |
| チーム起動 / 再起動 | `make team-start` → `tmux attach -t agent-team` | 人間 |
| 状態確認 | `make team-status` | lead |
| task 作成・送付 | `cp .agents/queue/tasks/TEMPLATE.md .agents/queue/tasks/T-001.md` → 編集 → `make team-send TO=worker-1 TYPE=task_assigned TASK=T-001` | lead |
| inbox 確認 / 既読 | `make inbox AGENT=worker-1` / `make inbox AGENT=worker-1 MARK=<id>` | 全員 |
| 未送信プロンプトの送信 | `make team-submit AGENT=worker-1` | 全員 |
| 検証ゲート | `make post-change` / `make smoke` | worker / lead |
| report 記入 | `make report TASK=T-001 AGENT=worker-1 STATUS=needs-review` | worker |
| review 実行 | `make review TASK=T-001 AGENT=worker-1` | worker |
| 統合 | `make integrate TASK=T-001 AGENT=worker-1` | lead |
| 停止 | `make team-stop` | 人間 |

`make team-send TYPE=task_assigned` は root が clean で、他の実装 task が active でない場合だけ task state を作ります。`make integrate` は `ready-to-integrate` の task だけを対象に検証を実行し、結果を `.agents/queue/integrations/` に残します。

## Repository layout

| パス | 内容 |
| --- | --- |
| `AGENTS.md` | 全 agent 共通の作業ルール（`CLAUDE.md` は symlink） |
| `.agents/config/agent-team.yaml` | 役割・model・起動コマンド設定 |
| `.agents/docs/TEAM_PROTOCOL.md` | task / report / review / integration の詳細手順 |
| `.agents/docs/MEMORY.md` | 共有 memory と更新ルール（lead のみ編集） |
| `.agents/skills/` | Claude Code / Codex 共通の skill（`.claude/skills`・`.codex/skills` は symlink） |
| `.agents/scripts/` | harness を構成する各コマンドの実体 |
| `.agents/queue/` | tasks / inbox / reports / reviews / integrations / state |
| `.agents/tests/harness/` | harness 自体の test |
| `Makefile` | すべての操作 entrypoint |

## Harness 自体を変更したとき

`.agents/` 以下の harness を編集した場合は、構文と lifecycle を確認します。

```bash
make post-change
make harness-test
```

## ドキュメント

- [`AGENTS.md`](AGENTS.md) — 役割ごとの作業ルール
- [`.agents/docs/TEAM_PROTOCOL.md`](.agents/docs/TEAM_PROTOCOL.md) — task / review / integration の詳細
- [`.agents/docs/MEMORY.md`](.agents/docs/MEMORY.md) — 共有 memory のルール
