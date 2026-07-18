---
name: team-general-worker
description: General Workerがtask_assigned、supervision_feedback、supervision_result、manager_fixを受け、通常の実装、固定General Reviewerとの相談、検証、task commit、reportを扱うときに使う。
---

# team-general-worker

## 責務

- 担当taskの`Goal`、`Acceptance`、`Constraints`を満たす実装を行う。
- 変更を`Allowed paths`内に収め、`Do not modify`にあるpathを変更しない。両方に合致するpathは狭い指定が勝つ。
- blocker、不確実な判断、低い自信、技術上の疑問、対象範囲を変える必要が生じた場合は、固定General Reviewerへ相談する。
- ArchitectまたはStrategistの判断が必要な場合は、General Reviewerから依頼してもらう。
- `STATE.md`と`MEMORY.md`を編集しない。

## 実装

1. task、関連コード、現在状態、適用されるskillsを確認する。
2. 成功条件、変更path、検証方法、固定General Reviewerを確認する。
3. testの要否、種類、書き方は`team-test-strategy`に従う。
4. 影響する経路を確認し、task全体を満たす一貫した変更を実装する。
5. task固有の検証を実行する。

General Reviewerの入力によって実装方針を変えられる段階では、`supervision_checkpoint`で相談できる。

```bash
make team-send TO=<supervisor_id> TYPE=supervision_checkpoint TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/checkpoint.md
```

`supervision_feedback`を受けた場合は、指摘と対応をreportへ残す。

## 実装report

`team-verify`に従い、task固有の検証、`make post-change`、`make smoke`を実行する。

taskが所有する変更をcommitし、reportを作る。`Allowed paths`がすべてteam rootの外にあるtaskはtask commitを作らず、成果の場所と検証をreportへ書く。

```bash
make task-commit TASK=<task_id> MESSAGE="<summary>"
make report TASK=<task_id> STATUS=needs_supervision
```

reportのplaceholderをすべて埋める。

実行したcommand、結果、変更file、task commit、Supervisorとの相談、専門家の成果物を具体的に記録する。

reportを完成させた後、固定General Reviewerへ送る。

```bash
make team-send TO=<supervisor_id> TYPE=ready_for_supervision TASK=<task_id> BODY="Report and evidence are ready."
```

`FIX`または`manager_fix`を受けた場合は、同じGeneral Reviewerと相談し、修正、再検証、commit、report更新、再reviewを行う。
