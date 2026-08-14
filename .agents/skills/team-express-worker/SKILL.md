---
name: team-express-worker
description: Express Workerがcodex execの非対話実行で起動され、Leadから直接dispatchされた小さなexpress taskの実装、検証、task commit、report、express_ready報告を扱うときに使う。
---

# team-express-worker

## 責務

- 担当express taskの`Goal`、`Acceptance`、`Constraints`を満たす実装を行う。
- 変更を`Allowed paths`内に収め、`Do not modify`にあるpathを変更しない。両方に合致するpathは狭い指定が勝つ。
- `STATE.md`と`MEMORY.md`を編集しない。

## 実行形態

Express Workerは常駐せず、Leadのdispatchごとにcodex execの非対話実行として起動される。

1回の実行で、実装からLeadへの報告までを完結させる。

Supervisorは付かないため、相談と質問の宛先はLeadだけとする。

reviewはLeadがtask commitの差分とreportだけで行うため、どちらも単独で判断できる内容にする。

## 実装

1. `make inbox AGENT=<agent_id>`でtask_assignedを確認し、task、関連コード、適用されるskillsを読む。
2. 影響する経路を確認し、task全体を満たす一貫した変更を実装する。
3. task固有の検証、`make post-change`、`make smoke`を実行する。
4. taskが所有する変更をcommitし、reportを作る。`Allowed paths`がすべてteam rootの外にあるtaskはtask commitを作らず、成果の場所と検証をreportへ書く。

```bash
make task-commit TASK=<task_id> MESSAGE="<summary>"
make report TASK=<task_id> STATUS=ready_for_lead
```

reportのplaceholderをすべて実測の証拠で埋める。

reportを完成させた後、Leadへ報告して実行を終える。

```bash
make team-send TO=<lead_id> TYPE=express_ready TASK=<task_id> BODY="<要点>"
```

## Blockerと質問

実行中に回答を待つことはできない。

解消できないblocker、対象範囲を変える必要、express taskに収まらない設計判断が生じた場合は、状況をreportへ残し、Leadへ質問を送って実行を終える。

```bash
make team-send TO=<lead_id> TYPE=question TASK=<task_id> BODY="<質問と現状>"
```

Leadからのfix feedbackは、同じsessionを再開する新しい実行として届く。

指摘を反映し、再検証、commit、report更新、express_readyの再送を行う。
