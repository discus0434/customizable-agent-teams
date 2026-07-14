# customizable-agent-teams

[English](../../README.md) | **日本語**

Claude Code と Codex を11の役割に分けて、tmux の上で1つのチームとして動かすプロジェクトテンプレートです。

人間が対話する相手は Lead ひとりだけで、タスクの分解、割り当て、レビュー、進捗の管理はチームの中で完結します。

![customizable-agent-teams の全体フロー](../assets/agent-team-flow.png)

1体のエージェントに要件の確認から実装、レビュー、完了判断までを積むと、膨れ上がったコンテキストの中から、いま思い出すべきことを拾い出せなくなっていきます。

そこでこのテンプレートは、責務ごとに別のエージェントを立てて、それぞれに専用のコンテキストを与えます。

責務を分けると、役割ごとに向いた CLI とモデルを選べるようになります。人間の窓口には対話に強いモデルを、数をこなす実装には安くて速いモデルを、という配分です。

チームの骨格は次の4つです。

- **固定レビュワー**：実装 Worker には固定のレビュワーが付き、レビューを通らない task は done になりません。自分で書いた変更を自分で承認する状況を、構造ごと消しています。
- **完了ゲート**：Manager が完了を報告しようとすると、その送信の時点で検証コマンド一式が統合後の HEAD で自動実行され、通らなければ送信自体が失敗します。
- **express レーン**：小さな依頼は Manager を通さず、Lead が Express Worker へ直接 dispatch します。レビューは Lead が行います。
- **モデル配分は設定1ファイル**：`.agents/config/agent-team.yaml` の `model` と `effort` を書き換えるだけで、役割の構成を保ったままモデルを入れ替えられます。これが名前の由来です。

## 必要なtool

チームの起動には`git`、`make`、`bash`、`tmux`、`direnv`と、使用するcoding agentのCLIが必要です。

GitHubの操作には`gh`を使います。

repositoryの調査には`ripgrep`が利用できます。

選んだstackのtoolchainもbootstrapで使います。

<details>
<summary>macOSでまとめてinstallする</summary>

```bash
brew install gh ripgrep direnv tmux pnpm node python uv
brew install --cask codex
npm install -g @anthropic-ai/claude-code
```

</details>

<details>
<summary>apt系Linuxでまとめてinstallする</summary>

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
sudo apt-get install -y gh ripgrep direnv tmux python3 nodejs npm
```

</details>

## Quick Start

1. このtemplateから新しいrepositoryを作り、cloneする。

2. 現在のshellで`direnv`を有効にする。

   <details>
   <summary>direnv hookをshellへ追加する</summary>

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

3. bootstrapを開始する。

   ```bash
   make bootstrap
   make team-attach
   ```

   Leadは最初に「何を作るか」を一つ質問します。

   回答ごとに、構築物、利用者、stack、entrypoint、`make post-change`、`make smoke`を順に決めます。

4. Leadが初期化要件をManagerへ送ったら、`Ctrl-b`の後に`d`を押してtmuxからdetachする。

   repository rootで残りのroleを起動し、再びattachする。

   ```bash
   make bootstrap-team
   make team-attach
   ```

   以降はLeadのpaneで進行を確認し、Leadから質問された場合に回答します。

## 日常操作

人間が使うcommandは次の3つだけです。

| 操作 | Command |
| --- | --- |
| チーム起動または再起動 | `make team-start`の後に`make team-attach` |
| 現在状態の確認 | `make team-status` |
| チーム停止 | `make team-stop` |

tmuxからのdetachは`Ctrl-b`の後に`d`です。

## Roleと設定

| Role | 責務 |
| --- | --- |
| **Lead** | 人間の唯一の窓口として、目的、成功条件、制約、承認を確認する。 |
| **Manager** | task、依存関係、担当割り当て、完了判定、`STATE.md`を管理する。 |
| **Strategist** | 原因調査、複数案の比較、実行方針をまとめる。 |
| **Architect** | 技術方針、設計境界、共通化、test方針を判断する。 |
| **General Worker** | 通常の実装、検証、task commit、reportを担当する。 |
| **Hard Task Worker** | 高度な調査と推論を要する実装またはdebugを担当する。 |
| **General Reviewer** | 固定Workerの相談、途中feedback、最終reviewを担当する。 |
| **Research Worker** | codebase、実現可能性、外部情報を調査する。 |
| **Express Worker** | Leadが直接dispatchした小さなtaskを実装する。 |
| **Frontend Worker** | 表示結果を確認しながらfrontendを実装する。 |
| **Frontend Critic** | 画面方針、表示品質、操作、accessibility、frontend実装をreviewする。 |

`.agents/config/agent-team.yaml`の`agents`で、role、CLI、model、effort、window、agent数、固定Supervisorを変更できます。

```yaml
  - id: general-worker-1
    role: general-worker
    cli: codex
    model: gpt-5.6-luna
    effort: high
    window: general-worker-1
    supervisor: general-reviewer-1
```

起動commandは各agentの`cli`、`model`、`effort`から生成されます。

Claude Codeには`--dangerously-skip-permissions`が付きます。

Codexには`--dangerously-bypass-approvals-and-sandbox`が付きます。

Research WorkerとExpress Workerは常駐windowを持たず、依頼が割り当てられたときに`codex exec`の非対話実行として起動されます。この2つのroleには`window`を書きません。

## Repository構成

| Path | 内容 |
| --- | --- |
| `AGENTS.md` | 全agentの共通ルールであり、`CLAUDE.md`はこのfileへのsymlink。 |
| `.agents/config/agent-team.yaml` | agent、role、model、effort、固定Supervisorの設定。 |
| `.agents/agent-team.mk` | agent teamを操作するMake target。 |
| `.agents/docs/TEAM_PROTOCOL.md` | role間の接続と状態遷移。 |
| `.agents/state/STATE.md` | 現在の判断と次の行動に必要な状態。 |
| `.agents/state/MEMORY.md` | 中長期に再利用するrule、tip、pitfall、user preference。 |
| `.agents/skills/` | Claude CodeとCodexが共有するskills。 |
| `.agents/queue/` | task、report、review、researchなどの共有成果物。 |
| `Makefile` | projectの`post-change`と`smoke`を定義し、`.agents/agent-team.mk`をincludeする。 |

## 関連文書

- [`AGENTS.md`](../../AGENTS.md)：全agentの共通ルール。
- [`TEAM_PROTOCOL.md`](TEAM_PROTOCOL.md)：role間の接続と状態遷移。
- [`MEMORY.md`](../state/MEMORY.md)：共有memoryの更新規則。
