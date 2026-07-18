---
name: team-frontend-worker
description: Frontend Workerがtask_assigned、view_direction_result、supervision_feedback、supervision_result、manager_fixを受け、画面方針、表示結果を確認しながら進める実装、visual evidence、検証、task commit、reportを扱うときに使う。
---

# team-frontend-worker

## 責務

- 担当taskのfrontendと、それを直接支えるclient-side codeを実装する。
- 画面方針、表示品質、操作、accessibility、不確実な判断、対象範囲について、固定Frontend Criticへ相談する。
- backend、database、domain、infrastructureの実質的な変更が必要な場合は、Frontend CriticからManagerへ別taskを求めてもらう。
- 随伴file(test、docs)が必要になったら、他のin-flight taskの契約と交差しない限り、`Allowed paths`へ`declared during implementation`の注記付きで自分で追記し、reportへ記録する。交差する場合や迷う場合はFrontend Criticへ相談する。
- `STATE.md`と`MEMORY.md`を編集しない。

## 画面方針

主要なUI実装より前に、情報の優先順位、構成、操作、必要な状態、platformごとの対応を短くまとめる。

wireframe、参考資料、既存screenshotは、判断に必要な場合だけ添える。

```bash
make team-send TO=<critic_id> TYPE=view_direction_ready TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/view-direction.md
```

- `PROCEED`を受けた場合は、確認した方針で実装する。
- `NOT_NEEDED`を受けた場合は、既存方針に従って実装する。
- `REVISE`を受けた場合は、方針を直して再提出する。
- `ASK_MANAGER`はManagerへ送られるため、WorkerはManagerまたはFrontend Criticから解決結果が届くまで待つ。

## 実装と表示確認

- projectの`AGENTS.md`にあるvisual verificationと、taskに記載された確認対象に従う。
- client-side testの要否、種類、書き方は`team-test-strategy`に従う。
- 実装中も表示結果を確認し、code reviewだけで見た目を判断しない。
- 共有するscreenshotと確認結果は`.agents/queue/visuals/<task_id>/`に置く。
- taskに応じて、代表的なdevice、viewport、window、状態、操作、accessibility、loading、empty、errorを確認する。
- Frontend Criticの入力によって実装を変えられる段階では、`supervision_checkpoint`で相談できる。

```bash
make team-send TO=<critic_id> TYPE=supervision_checkpoint TASK=<task_id> BODY_FILE=.agents/queue/state/tmp/checkpoint.md
```

`supervision_feedback`を受けた場合は、指摘と対応をreportへ残す。

## 実装report

`team-verify`に従い、task固有の検証、`make post-change`、`make smoke`を実行する。

taskが所有する変更をcommitし、reportを作る。

```bash
make task-commit TASK=<task_id> MESSAGE="<summary>"
make report TASK=<task_id> STATUS=needs_supervision
```

reportには、画面方針の判断、screenshot path、確認した状態、Frontend Criticの指摘と対応、検証結果を記録する。

reportを完成させた後、固定Frontend Criticへ`ready_for_supervision`を送る。

`FIX`または`manager_fix`を受けた場合は、同じFrontend Criticと再検討し、影響する表示証拠を更新する。
