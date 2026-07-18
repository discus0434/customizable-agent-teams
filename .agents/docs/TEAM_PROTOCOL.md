# Team Protocol

この文書は、role間の接続と作業の状態遷移を示す。

各roleの判断基準と成果物は、対応する`team-<role>` skillに定める。

## Roleの接続

```text
Human -> Lead -> Manager
          |        |-> General Worker + General Reviewer
          |        |-> Hard Task Worker + General Reviewer
          |        `-> Frontend Worker + Frontend Critic
          `-> Express Worker (小さなtaskの直接dispatch)

Lead / Manager / Architect / General Reviewer / Frontend Critic -> Strategist
Lead / Manager / General Reviewer / Frontend Critic -> Architect
Lead / Manager / Strategist / Architect -> Research Worker pool
```

General WorkerまたはHard Task Workerには、固定されたGeneral Reviewerが付く。

Frontend Workerには、固定されたFrontend Criticが付く。

この二種類をまとめてSupervisorと呼ぶ。

Implementation Workerは、Managerがtaskを`done`にするまで次のtaskを持たない。

Research WorkerにはSupervisorを付けず、プロジェクトコードも編集させない。

Research WorkerとExpress Workerは常駐せず、依頼が割り当てられたときにcodex execの非対話実行として起動される。

## 実装task

Managerは`GENERAL_TEMPLATE.md`または`FRONTEND_TEMPLATE.md`からtaskを作り、Workerを指定する。

```bash
make task-lint TASK=<task_id>
make dispatch TASK=<task_id>
```

`dispatch`は、設定ファイルにある固定Supervisorをtaskへ記録する。

実装taskは次の順序で進む。

```text
task_assigned / supervision_assigned
-> 実装と途中相談
-> task commit / report / ready_for_supervision
-> Supervisor OK / FIX / ASK_MANAGER
-> Manager done / manager_fix
```

Supervisorが`OK`を記録すると、`done_recommendation=true`がManagerへ送られる。

Managerはtask state、report、Supervisorの判断、必要な専門家の成果物を確認して`done`を決める。

実装中に`Allowed paths`へ無い随伴file(変更したcodeを検証するtest、それを説明するdocs)が必要になった場合、Workerは自taskの`Allowed paths`へ`declared during implementation`の注記付きで追記してよい。追記できるのは、他のin-flight taskの契約と交差せず、自taskの`Do not modify`にもgovernance path(`.agents/`、`AGENTS.md`、`CLAUDE.md`、`Makefile`)にも当たらないpathだけとする。追記はreportへも記録し、Supervisorがreviewで妥当性を確認する。交差する場合や迷う場合は固定Supervisorへ相談する。express taskは対象外とする。

Frontend taskでは、主要なUI実装より前に画面方針を確認する。

```text
view_direction_ready
-> PROCEED / REVISE / NOT_NEEDED / ASK_MANAGER
-> 表示結果を確認しながら実装
-> final critique
```

taskで使う主なcommandは次のとおり。

```bash
make task-commit TASK=<task_id> MESSAGE="<summary>"
make report TASK=<task_id> STATUS=needs_supervision
make direction-report TASK=<task_id> DECISION=<decision>
make supervision-report TASK=<task_id> DECISION=<OK|FIX|ASK_MANAGER>
make state-update TASK=<task_id> STATUS=done
```

## Express task

小さく境界が明確なtaskは、LeadがManagerを通さずexpress laneで流せる。

Leadは`EXPRESS_TEMPLATE.md`から`T-E-`で始まるtaskを作り、直接dispatchする。

```bash
make dispatch TASK=T-E-001
```

express taskは次の制約を持つ。

- 同時に1件だけ動かせる。
- Supervisorは付かず、reviewはLeadが行う。
- `Architecture required`は`false`とする。
- `Allowed paths`に`.agents/`以下、`AGENTS.md`、`CLAUDE.md`、`Makefile`を含められない。

express taskは次の順序で進む。

```text
task_assigned (Leadがdispatch、express workerがexec起動)
-> 実装 / task commit / report / express_ready
-> Leadが差分と証拠を確認し、post-changeとsmokeを再実行
-> 修正が必要なら make express-fix TASK=<task_id> BODY="<指摘>"
-> make state-update TASK=<task_id> STATUS=done
-> LeadがManagerへnoteでSTATE.md記帳を依頼
```

`express-fix`は同じcodex exec sessionを再開し、指摘を渡して再実装させる。

express taskはManagerを通らないため、Leadのdone判定が最終ゲートになる。

expressに収まらないと分かった時点で、Leadは通常taskとしてManagerへ引き継ぐ。

## Research

Lead、Manager、Strategist、Architectは、共有poolへ調査を依頼できる。

```bash
make team-send TO=research-worker BODY_FILE=.agents/queue/state/tmp/research-request.md
```

依頼は、空いているResearch Workerへ作成順に割り当てられ、そのWorkerがcodex execの非対話実行として起動される。

各Research Workerが同時に担当する依頼は一つとする。

Research Workerは結果を依頼元へ直接返す。

追加調査は新しい依頼として扱い、別のResearch Workerへ割り当てられる場合がある。

Research Workerは実行中に依頼元へ質問できない。

不明点は前提を明示した結果として返し、依頼元は回答を添えた新しい依頼で調査を続ける。

依頼元は、調査依頼を送ったときに返されたrequest IDへ、理由を添えて`TYPE=cancel`で返信し、調査を中止できる。

進行中の依頼を中止すると、実行中のexec processも停止される。

```bash
make team-reply IN_REPLY_TO=<request_id> TYPE=cancel BODY="<reason>"
```

## 専門家への相談

Implementation Workerは、まず固定Supervisorへ相談する。

Supervisorは、そのtask内の質問に答える。

taskの対象範囲、成功条件、他taskへの影響、解消できないblockerについてManagerの判断が必要な場合は、SupervisorがManagerへ`question`で上げる。escalationのような専用型はない。

```bash
make team-send TO=manager TYPE=question TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/manager-question.md
```

```bash
make team-send TO=strategist TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/strategy-request.md
make team-send TO=architect TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/architecture-request.md
```

StrategistとArchitectへの依頼では、送信元とtaskから依頼種別と成果物pathが決まる。

Supervisorが送った依頼と結果はManagerにも共有される。

Managerは、人間の判断が必要な内容をLeadへ上げる。

Leadは人間と確認し、Managerへ判断を返す。

## 並列実行

dispatchの既定は並列とする。直列にするのは、次のいずれかを特定できたときだけとする。

- 他taskの成果物を入力にする依存。
- `Allowed paths`の交差、または同じ可変資源(lock、単一worktree、稼働中process)の取り合い。

着手可能なtaskとidle workerがあるのに直列にする場合は、競合する資源を名指しした理由を`STATE.md`の`Execution`へ書く。「同じrepoだから」「慎重を期して」のような範囲の広い理由で直列にしない。

dispatchはbatchではなくeventで駆動する。taskの完了は、それ単体で「新たにdispatch可能になったtaskはないか」を再判定して即dispatchするトリガーであり、同時に投げた他のtaskの完了を待たない。次のphaseの設計やresearchの発注も、現在のphaseの完了を待たずに並行してよい。

HOLDは、対象taskと資源を名指しした範囲でだけ発行し、全体を止めない。

## Messageと処理済み

送信されたmessageは受信側のpendingになり、nudgeが受信paneを起こす。nudgeが失われても、常駐の照合(`team_watch`)がpendingを抱えたidle paneを定期的に起こす。汎用の型は`note`、`intake`、`approval`、`decision`、`question`、`answer`、`request`で、専用型は送信scriptが検証する。

`note`だけは記録専用で、受信側を起こさずpendingにもならない。相手の行動や受領を待つ内容を`note`で送らない。読ませたい記録は`REQUIRES_ATTENTION=1`を付けて送る。

処理済みは、messageが作る義務の完了の記録であり、閲覧の記録ではない。判断を要求するmessageは読んだだけでは処理済みにならず、応答のcommand(`supervision_feedback`、supervision-reportなど)か、対応不要と判断した場合の明示のMARKだけが処理済みにする。

義務はmessageの他にtask stateにも記録される。`team_watch`は、活きたstatusのtaskがどのinboxにも映らず止まっている場合、statusから義務を負うagentを決めて起こす。

返答を保留したいmessageを、pendingのまま抱えて待機しない。たとえば「条件が揃ったら再開したい」という相談を受け、条件が揃った時点でまとめて答えるつもりでmessageをpendingに残す、という形がこれにあたる。pendingは未対応の義務の印なので、照合(`team_watch`)は毎周期この義務を見つけて受信者を起こすが、条件は揃っていないから起きても何もできず、空の起床が条件成立まで毎周期続く。

保留したい内容は、いま決められることを返信して処理済みにする。上の例なら「条件Xが成立するまで待て。成立はevent Y(対象taskのterminal reportなど)で分かるので、受け取り次第こちらから再開指示を送る」とその場で答え、約束した後続はevent Yが届いたときに行う。

## 待機

turnを閉じて待ってよいのは、自分宛のmessageで起こされる待ちだけとする。paneを開いたままsleepやpollingで監視を続けない。開いたturnはtokenを消費し続け、その間はinboxのmessageも読めない。

messageの裏付けが無いもの(他taskの完了、散文で宣言した指示待ち)を待ちたい場合は、待つ相手へmessageを送り、返答待ちに変えてから閉じる。担当taskの作業途中は待機ではない。続きは自分で再開する。

待ちに入る前に、次を済ませる。

- 判断に必要な証拠をfile(report、成果物、log)へ保全する。
- lockと共有資源を解放する。検証環境の保全を理由に、共有資源を握ったまま待たない。
- 何を待っていて、届いたら何をするかを、reportまたは相談messageに書き残す。

## 完了

`completion_ready`が発火するのはintake全体の完了時だけなので、それより前の進捗は節目で報告する。intakeがphaseやmilestoneを定義している場合、Managerは節目のtaskがすべて`done`になった時点でLeadへ報告し、Leadは人間へ進捗を伝える。

```bash
make team-send TO=lead TYPE=note REQUIRES_ATTENTION=1 BODY="<節目の完了報告>"
```

intakeの成功条件を満たすtaskがすべて`done`になったら、Managerは対象taskと成果物を列挙してLeadへ`completion_ready`を送る。

`completion_ready`の送信時には、`STATE.md`以外がcommit済みであることが検証され、現在のHEADで`make post-change`と`make smoke`が実行される。

どちらかが失敗すると、送信自体が失敗する。

Leadは受け入れ検証として、task state、report、利用者に見える挙動、未解決事項を確認する。

問題があればManagerへ差し戻し、なければ人間へ完了を報告して、Managerへ`completion_ack`を返す。

Managerは`STATE.md`を次の作業に必要な状態へ整理し、完了状態をcommitする。

```bash
make state-commit
```

このcommandは、`completion_ack`が届いていることと、`STATE.md`以外に未commitの変更がないことを検証する。

## 状態と成果物

`STATE.md`は、`Intent`、`Execution`、`Active Tasks`、`Blockers`、`Current Decisions`、`Next Actions`で現在状態を表す。

完了した作業の詳細は、task、report、review、critique、research、architecture、strategyの各成果物へ残す。

`MEMORY.md`には、中長期に再利用する情報だけを残す。

| Path | 内容 |
| --- | --- |
| `.agents/queue/tasks/` | 実装taskとtemplate |
| `.agents/queue/reports/` | Workerの実装報告と検証結果 |
| `.agents/queue/reviews/` | General Reviewerの判断 |
| `.agents/queue/direction-critiques/` | Frontend Criticの画面方針に対する判断 |
| `.agents/queue/critiques/` | Frontend Criticの最終判断 |
| `.agents/queue/visuals/` | 表示結果の共有証拠 |
| `.agents/queue/research/` | 調査依頼と結果 |
| `.agents/queue/strategy/` | Strategistの分析 |
| `.agents/queue/architecture/` | Architectの技術判断 |
| `.agents/queue/memory_proposals/` | MEMORYへの提案 |
| `.agents/queue/skill_proposals/` | project skillへの提案 |
