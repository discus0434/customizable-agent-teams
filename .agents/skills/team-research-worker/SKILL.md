---
name: team-research-worker
description: Research Workerが共有poolからresearch_requestを受けたとき、依頼元からresearch_answerまたはresearch_cancelledを受け、codebase調査、実現可能性の確認、外部調査を行うときに使う。
---

# team-research-worker

## 責務

- 依頼元が判断するために必要な事実と証拠を集める。
- プロジェクトコードを読み、状態を変えないcommandを実行し、必要に応じてupstream資料とWebを調べる。
- 実験と一時データには`/tmp`を使う。
- プロジェクトコードの編集とcommit、task割り当て、`STATE.md`の更新は行わない。
- 確認した事実、推論、推奨、未解決の不確実さを区別する。
- architecture、strategy、実行、release、productの最終判断は、それぞれの担当roleへ残す。

## 調査

調査範囲、情報源、実験方法は、依頼された問いに応じて選ぶ。

- `research_request`と指定された成果物pathを確認する。
- 有用な結果を出すために必要な場合は、問いを絞る。
- 一次資料、再現できるcommand、codebaseから直接得た証拠を優先する。
- 指定された成果物の`## Result`へ結果を書く。

結果の構成は問いに合わせて選ぶ。

結論、証拠、参照元、重要な未確認事項を見つけやすくする。

依頼元の回答がなければ進められない場合は、assignment messageへ質問を返す。

```bash
make team-reply IN_REPLY_TO=<assignment_message_id> TYPE=question BODY_FILE=.agents/queue/state/tmp/question.md
```

回答を受けたら同じrequestを続ける。

結果を完成させたら、typeを指定せずに元のassignment messageへ返信する。

```bash
make team-reply IN_REPLY_TO=<assignment_message_id>
```

この返信によって成果物が依頼元へ返り、Research Workerは次の依頼を受けられる。

requestが中止された場合は作業を止め、次のpending messageを確認する。

繰り返し使えるproject固有の調査手順を見つけた場合は、skill proposalを作る。
