# customizable-agent-teams

Claude CodeとCodexを、複数のroleに分けてtmux上で動かすproject templateです。

人間との対話、進行管理、技術判断、調査、実装、reviewを別々のagentが担当します。

人間はLeadとだけ対話します。

Managerは依存関係を整理し、実装taskをWorkerと固定Supervisorの組へ割り当てます。

Research Workerは、codebase、実現可能性、Webを並列に調査します。

![customizable-agent-teams workflow](.agents/assets/agent-team-flow.png)

## 特徴

- **Lead**：人間への質問、承認の確認、目的と成功条件の整理に集中します。
- **Manager**：task作成、Worker選択、割り当て、完了判定、`STATE.md`を担当します。
- **Strategist**：原因調査、選択肢の比較、実行方針の検討を担当します。
- **Architect**：技術方針、設計境界、test方針、task間の一貫性を担当します。
- **General Worker**：複数のWorkerが通常の実装を担当し、それぞれに固定General Reviewerが付きます。
- **Hard Task Worker**：複数のWorkerが難しいdebugと複数境界にまたがる実装を担当し、それぞれに固定General Reviewerが付きます。
- **Research Worker**：常駐せず、依頼が来たときだけ`codex exec`で起動され、調査結果を依頼元へ直接返します。
- **Express Worker**：常駐せず、Leadが直接dispatchした小さなtaskを`codex exec`で実装します。Managerを通らず、reviewはLeadが行います。
- **Frontend Worker**：実際の画面を確認しながら実装し、固定Frontend Criticが画面方針と完成結果をreviewします。
- **共有repository**：すべてのagentが同じrepository rootを使うため、venv、`node_modules`、`.env`、direnvを共有できます。
- **構成変更**：`.agents/config/agent-team.yaml`でCLI、model、effort、agent数、固定Supervisorを変更できます。

## Roleの責務

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

```text
Human
  -> Lead
  -> Manager
  -> General Worker + General Reviewer
     or Hard Task Worker + General Reviewer
     or Frontend Worker + Frontend Critic
  -> Supervisor OK / FIX / ASK_MANAGER
  -> Manager marks done
  -> Lead verifies and reports completion
```

小さく境界が明確なtaskは、LeadがManagerを通さずExpress Workerへ直接dispatchできます。

```text
Human -> Lead -> Express Worker (codex exec)
  -> 実装 / commit / report / express_ready
  -> Leadが差分と検証を確認して done
  -> Lead reports completion
```

調査または専門的な判断が必要な場合は、担当roleからResearch Worker、Strategist、Architectへ依頼します。

```text
General Worker -> General Reviewer -> Manager -> Lead -> Human
Hard Task Worker -> General Reviewer -> Manager -> Lead -> Human
Frontend Worker -> Frontend Critic -> Manager -> Lead -> Human

Lead / Manager / Architect / General Reviewer / Frontend Critic -> Strategist
Lead / Manager / General Reviewer / Frontend Critic -> Architect
Lead / Manager / Strategist / Architect -> Research Worker pool
```

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

## チーム設定

`.agents/config/agent-team.yaml`の`agents`で、role、CLI、model、effort、window、agent数を変更できます。

General Worker、Hard Task Worker、Frontend Workerの`supervisor`には固定Supervisorを指定します。

起動commandは各agentの`cli`、`model`、`effort`から生成されます。

Claude Codeには`--dangerously-skip-permissions`が付きます。

Codexには`--dangerously-bypass-approvals-and-sandbox`が付きます。

CodexのResearch WorkerではWeb検索も有効になります。

Research WorkerとExpress Workerは常駐windowを持たず、依頼が割り当てられたときに`codex exec`の非対話実行として起動されます。この2つのroleには`window`を書きません。

## 日常操作

| 操作 | Command | 主なrole |
| --- | --- | --- |
| チーム起動または再起動 | `make team-start`の後に`make team-attach` | 人間 |
| 現在状態の確認 | `make team-status`または`make state` | Manager、Lead |
| `AGENTS.md`とskills symlinkの確認 | `make agent-surfaces` | Manager、Supervisor |
| inbox確認 | `make inbox AGENT=general-worker-1` | 全role |
| 入力欄に残ったpromptの送信 | `make team-submit AGENT=general-worker-1` | 全role |
| agentへの連絡 | `make team-send FROM=lead TO=manager TYPE=intake TASK=- BODY="..."` | 全role |
| 長文の連絡 | `make team-send FROM=lead TO=manager TYPE=intake TASK=- BODY_FILE=.agents/queue/state/tmp/message.md` | 全role |
| 対応不要の記録 | `make team-send TO=general-worker-1 TYPE=note TASK=T-001 BODY="..."` | 全role |
| inboxへの返信 | `make team-reply IN_REPLY_TO=<message_id> TYPE=answer BODY_FILE=.agents/queue/state/tmp/reply.md` | 全role |
| research依頼 | `make team-send TO=research-worker BODY_FILE=.agents/queue/state/tmp/research.md` | Lead、Manager、Strategist、Architect |
| task割り当て | `make dispatch TASK=T-001` | Manager |
| express taskの割り当て | `make dispatch TASK=T-E-001` | Lead |
| express taskの修正指示 | `make express-fix TASK=T-E-001 BODY="..."` | Lead |
| task仕様の確認 | `make task-lint TASK=T-001` | Manager、Supervisor |
| Workerの検証 | `make post-change`と`make smoke` | Implementation Worker |
| task変更のcommit | `make task-commit TASK=T-001 MESSAGE="<summary>"` | Implementation Worker |
| 実装中の相談 | `make team-send TO=<supervisor_id> TYPE=supervision_checkpoint TASK=T-001 BODY_FILE=.agents/queue/state/tmp/checkpoint.md` | Implementation Worker |
| Workerへのfeedback | `make team-send TO=<worker_id> TYPE=supervision_feedback TASK=T-001 BODY="..."` | Supervisor |
| Managerからの差し戻し | `make team-send TO=<pair_agent_id> TYPE=manager_fix TASK=T-001 BODY_FILE=.agents/queue/state/tmp/manager-fix.md` | Manager |
| Strategistへの相談 | `make team-send TO=strategist TASK=T-001 BODY="..."` | Lead、Manager、Supervisor、Architect |
| Architectへのtask相談 | `make team-send TO=architect TASK=T-001 BODY="..."` | Lead、Manager、Supervisor |
| implementation report | `make report TASK=T-001 STATUS=needs_supervision` | Implementation Worker |
| 画面方針のdecision | `make direction-report TASK=T-001 DECISION=PROCEED` | Frontend Critic |
| Supervisorのdecision | `make supervision-report TASK=T-001 DECISION=OK` | General Reviewer、Frontend Critic |
| taskの完了 | `make state-update TASK=T-001 STATUS=done` | Manager |
| 完了報告の準備 | `make team-send FROM=manager TO=lead TYPE=completion_ready TASK=- BODY="..."` | Manager |
| 完了報告済みの通知 | `make team-send FROM=lead TO=manager TYPE=completion_ack TASK=- BODY="..."` | Lead |
| 完了状態のcommit | `make state-commit` | Manager |
| チーム停止 | `make team-stop` | 人間 |

team paneでは`TEAM_AGENT_ID`が送信元になります。

repository shellから送信する場合は`FROM=<agent_id>`を指定します。

repository shellからtaskを割り当てる場合は`OWNER=<agent_id>`も指定します（通常taskはmanager、express taskはlead）。

## Repository構成

| Path | 内容 |
| --- | --- |
| `AGENTS.md` | 全agentの共通ルールであり、`CLAUDE.md`はこのfileへのsymlink。 |
| `.agents/config/agent-team.yaml` | agent、role、model、effort、固定Supervisorの設定。 |
| `.agents/agent-team.mk` | agent teamを操作するMake target。 |
| `.agents/harness.mk` | このtemplate自体を保守するときに使うtest target。 |
| `.agents/docs/TEAM_PROTOCOL.md` | role間の接続と状態遷移。 |
| `.agents/state/STATE.md` | 現在の判断と次の行動に必要な状態。 |
| `.agents/state/MEMORY.md` | 中長期に再利用するrule、tip、pitfall、user preference。 |
| `.agents/skills/` | Claude CodeとCodexが共有するskillsであり、`.claude/skills`と`.codex/skills`はこのdirectoryへのsymlink。 |
| `.agents/scripts/` | 各Make targetの実装。 |
| `.agents/queue/` | task、report、review、researchなどの共有成果物。 |
| `.agents/tests/team/` | このtemplate自体のtest。 |
| `Makefile` | projectの`post-change`と`smoke`を定義し、`.agents/agent-team.mk`をincludeする。 |

## 関連文書

- [`AGENTS.md`](AGENTS.md)：全agentの共通ルール。
- [`.agents/docs/TEAM_PROTOCOL.md`](.agents/docs/TEAM_PROTOCOL.md)：role間の接続と状態遷移。
- [`.agents/state/MEMORY.md`](.agents/state/MEMORY.md)：共有memoryの更新規則。
