---
name: team-bootstrap
description: Leadがこのtemplateから新しいprojectを初期化するために、人間へ一度に一つずつ質問し、構築物、stack、entrypoint、post-change、smoke、visual verificationを決めてManagerへ依頼するときに使う。
---

# team-bootstrap

## 現在状態の確認

次のファイルと、すでに存在するproject fileを確認する。

- `AGENTS.md`
- `README.md`
- `Makefile`
- `.agents/docs/TEAM_PROTOCOL.md`
- `.agents/state/STATE.md`
- `.agents/state/MEMORY.md`
- `pyproject.toml`、`package.json`、`pnpm-workspace.yaml`などのpackage metadata。
- source directoryとtest directory。

## 人間との対話

最初に「何を作るか」を一つだけ質問する。

回答を受けたら、確定した内容を短く示し、次の判断を最も進める質問を一つ選ぶ。

repositoryと依頼から確定できる内容は質問しない。

人間が選びやすくなる場合は、選択肢と推奨案を添える。

一度に複数の質問を並べない。

初期化の要件が固まるまで、実装とtask割り当てを始めない。

次の内容を必要な順に決める。

- 構築するものと利用者。
- library、CLI、service、application、package、scriptなどの提供形態。
- 主な言語、runtime、そのecosystemで標準的なtoolchain。
- package名と公開entrypoint。
- 最初に成立させる利用者向けの挙動。
- `make post-change`で実行するformat、lint、typecheck、build、test。
- `make smoke`で確認する代表的な利用者向けの挙動。
- frontendがある場合の起動方法、操作方法、screenshot、確認する状態。

stackが決まった後、具体的な初期値が必要な場合は[stack-contracts.md](references/stack-contracts.md)を読む。

## Projectの検証command

- `make post-change`は、Implementation Workerが変更後に実行する一つのcommandとする。
- 選んだstackの標準的なpackage manager、formatter、linter、test runner、必要なbuildまたはpackage commandを設定する。
- `make post-change`には、format、lint、必要なtypecheck、build、test、`git diff --check -- .`を含める。
- 複数packageがある場合は、対象directoryを明示し、一つの`post-change`から各packageの検証を呼ぶ。
- `make smoke`は、代表的な利用者向けの挙動を短時間で実行するcommandとする。所定の`harness-test`は削除して置き換える。
- frontendがある場合は、同じ画面と状態を再現できるvisual verificationを`AGENTS.md`へ記載する。
- 必要なlockfileを作る。
- 必須toolがない場合は、見つからないcommandを示してblockerとして報告する。

## 初期化するファイル

templateの記述を、実際のprojectに合わせて更新する。

- `README.md`：project名、目的、install、実行方法、主要entrypoint、検証command。
- `AGENTS.md`：team共通ルールに加え、実際のstack、source directory、test、visual verificationの情報。
- `Makefile`：projectの`post-change`と`smoke`。
- package metadata：package名、version、description、entrypoint、build backend、lockfile。
- `.agents/config/agent-team.yaml`：変更が必要な場合のteam名、session名、agent、CLI、model、effort、固定Supervisor。

選ばなかったstack、未使用のscaffold、templateのproject名、実際には使わないcommandを残さない。

## Managerへの引き継ぎ

初期化の要件が固まったら、Managerへ`intake`を送る。

`intake`には次の内容を含める。

- project名、目的、最初の利用者向け挙動。
- 選んだstackと必要なtool。
- package名とentrypoint。
- `make post-change`の内容。
- `make smoke`で確認する挙動。
- `README.md`、`AGENTS.md`、`Makefile`、package metadataの更新内容。
- 初期化後に削除するscaffold。
- Managerが追加承認なしで進められる範囲。
- Leadへ判断を戻す条件。

人間にはtmuxからdetachし、repository rootで次のcommandを実行してもらう。

```bash
make bootstrap-team
```

このcommandはLeadのpaneを残したまま、その他のroleを起動する。

## 初期化の完了条件

- `make post-change`が成功する。
- `make smoke`が成功する。
- deliverableにbuildが必要な場合は`make post-change`に含まれている。
- `README.md`、`AGENTS.md`、`Makefile`、package metadata、agent team設定が実際のprojectを説明している。
- source、test、lockfile、必要な設定が存在する。
- 未使用のscaffold、stack command、placeholderのproject名が残っていない。
- `.agents/skills/team-bootstrap/`が削除されている。
- bootstrap専用のMake targetが削除されている。
- `.agents/scripts/team_bootstrap.sh`と`.agents/scripts/team_bootstrap_team.sh`が削除されている。
- 削除したbootstrap commandへの参照が残っていない。
