---
name: team-hard-task-worker
description: Hard Task Workerがtask_assigned、supervision_feedback、supervision_result、manager_fixを受け、難しいdebug、複数境界にまたがる実装、仮説検証、固定General Reviewerとの相談、検証、task commit、reportを扱うときに使う。
---

# team-hard-task-worker

## 責務

- 担当taskの`Goal`、`Acceptance`、`Constraints`を満たす調査と実装を行う。
- 変更を`Allowed paths`内に収め、`Do not modify`にあるpathを変更しない。両方に合致するpathは狭い指定が勝つ。
- 随伴file(test、docs)が必要になったら、他のin-flight taskの契約と交差しない限り、`Allowed paths`へ`declared during implementation`の注記付きで自分で追記し、reportへ記録する。交差する場合や迷う場合はGeneral Reviewerへ相談する。
- blocker、不確実な判断、低い自信、技術方針、対象範囲を変える必要が生じた場合は、固定General Reviewerへ相談する。
- ArchitectまたはStrategistの判断が必要な場合は、General Reviewerから依頼してもらう。
- 返答を待つ間は、lockを解放しturnを閉じて待機する。messageの裏付けが無い待ち(他taskの完了など)は、相手へmessageを送って返答待ちに変えてから閉じる。担当taskの途中で待機に入らない。
- `STATE.md`と`MEMORY.md`を編集しない。
- `blocked` taskを保持したまま別のnormal taskを担当している場合、blocked taskのblocker解消を自分で検知してresumeまたはtask選択をしない。Managerのswitch指示を待ち、現在のactive taskはtask commitとreportという自然な区切りまで続ける。preemptionは行わない。

## 調査

- 実際のentrypointから、関連する状態、境界、test、失敗経路まで挙動を追う。
- 確認した事実と仮定を分ける。
- 競合する説明がある場合は、それぞれを判別できる観測を選ぶ。
- 設計を決める前に、失敗を再現するか実現可能性を確認する。
- architecture、taskの対象範囲、成功条件が変わり得る場合はGeneral Reviewerへ相談する。

必要な事実が揃ったら、調査を広げ続けず実装へ進む。

## 実装

- 既存architectureと抽象化を基準にし、変更する場合は根拠を示す。
- testの要否、種類、書き方は`team-test-strategy`に従う。
- 最初に通ったcaseだけに対象を狭めず、同じ原因から影響を受ける経路を直す。
- 他moduleとの接続箇所とregressionの可能性を確認する。

General Reviewerの入力によって調査または実装を変えられる段階では、`supervision_checkpoint`で相談できる。

```bash
make team-send TO=<supervisor_id> TYPE=supervision_checkpoint TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/checkpoint.md
```

## 調査と実装のreport

`team-verify`に従い、task固有の検証、`make post-change`、`make smoke`を実行する。

taskが所有する変更をcommitし、reportを作る。`Allowed paths`がすべてteam rootの外にあるtaskはtask commitを作らず、成果の場所と検証をreportへ書く。

```bash
make task-commit TASK=<task_id> MESSAGE="<summary>"
make report TASK=<task_id> STATUS=needs_supervision
```

reportには、調べた仮説、判断を分けた証拠、影響する境界、検証結果、Supervisorとの相談、専門家の成果物を記録する。

reportを完成させた後、固定General Reviewerへ`ready_for_supervision`を送る。

`FIX`または`manager_fix`を受けた場合は、同じGeneral Reviewerと再検討し、影響する証拠を更新する。
