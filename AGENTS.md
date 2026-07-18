# Agent Team 共通ルール

## 起動

```bash
make team-identity
```

表示されたagent ID、role、team rootを基準にする。

teamの作業を始める前に、次のファイルを読む。

1. `.agents/docs/TEAM_PROTOCOL.md`
2. `.agents/state/MEMORY.md`
3. `.agents/state/STATE.md`

Implementation Workerは、担当する`.agents/queue/tasks/<task_id>.md`も読む。

すべてのpaneは同じrepository rootを使う。

agent間で共有する成果物は`.agents/queue/`に置く。

自分だけが使う一時ファイルは`/tmp`に置き、別のagentへ渡す一時ファイルは`.agents/queue/state/tmp/`に置く。

## 作業の進め方

- roleの責任、成果物、状態遷移、共有状態の所有はteamの契約として扱う。
- 調査範囲、思考の順序、追加検証、相談のタイミングは、taskの不確実さと影響に応じて各roleが選ぶ。
- 依存関係を確認してから着手する。
- 互いに依存せず、同じ変更対象を競合して更新しない作業は並列に進める。
- ある結果を待たなければ始められない作業と、同じ可変状態を更新する作業だけを直列にする。
- 依存先を待っている間は、自分のroleで着手できる別の作業を進める。

## ツールと検証

- GitHubの操作には`gh`を使う。
- repositoryの環境変数が必要なcommandは`direnv exec . <command>`で実行する。
- 必須toolがない場合は、見つからないcommandを示してblockerとして報告する。
- 完了を表す判断は、`team-verify`に定めたroleごとの証拠に基づける。

## 通信

人間と対話するのはLeadだけとする。

agent間の通信には`make team-send`と`make team-reply`を使う。

```bash
make inbox AGENT=<agent_id>
make team-send TO=<agent_id> TYPE=<message_type> TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/message.md
make team-reply IN_REPLY_TO=<message_id> TYPE=<message_type> BODY_FILE=.agents/queue/state/tmp/reply.md
```

messageの型、配送のされ方、処理済みの意味論は、`TEAM_PROTOCOL.md`の「Messageと処理済み」に従う。この文書には複製しない。

- task、research、pane、inboxの現在状態は`make team-status`で確認する。
- paneの入力欄にpromptが残っている場合は`make team-submit AGENT=<agent_id>`を実行する。

## Roleと共有状態

role間の接続、状態遷移、成果物の置き場所は`TEAM_PROTOCOL.md`を参照する。

role固有の判断基準と作業内容は、対応する`team-<role>` skillを参照する。

`STATE.md`と`MEMORY.md`は、各fileに定めた編集者と更新規則に従って扱う。

skillを作成または編集するときは、実行環境に組み込まれたskill作成ガイドを使う。
