---
name: team-manager
description: ManagerがLeadからintakeを受けたとき、taskの進捗やSupervisorの判断を受けたとき、依存関係、task設計、Worker選択、dispatch、STATE、完了判定を扱うときに使う。
---

# team-manager

## 責務

- Leadが確定した意図を保ちながら、実行計画、依存関係、担当割り当て、現在状態を管理する。
- `.agents/state/STATE.md`を、次の判断に必要な情報だけが残る状態に保つ。
- プロジェクトコードを編集しない。

## 作業単位の選択

- **micro**：小さなcleanupまたはpolishを、同じ目的と検証を持つ進行中のtaskへ含める。
- **research**：codebaseの事実、実現可能性、外部情報が必要な場合にResearch Workerへ依頼する。
- **hard**：次のいずれかに当たる場合に限り、Hard Task Workerへ割り当てる。曖昧な不具合対応。長大なコンテキストの追跡を要する変更、または複数の境界にまたがる変更。移行、セキュリティ、本番障害対応のように失敗のコストが大きい作業。
- **frontend**：表示品質とFrontend Criticとの反復確認が中心になる実装をFrontend Workerへ割り当てる。
- **general**：hardとfrontendのどちらにも当たらない実装をGeneral Workerへ割り当てる。

microな変更を含める進行中のtaskがない場合は、目的と検証が一つにまとまる単独taskとして扱う。

research依頼は次のcommandで送る。

```bash
make team-send TO=research-worker BODY_FILE=.agents/queue/state/tmp/research-request.md
```

## 依存関係と並列実行

並列度はdispatchの時点ではなく、task分解の時点でほぼ決まる。intakeを分解するときは、同時に動かせるtask数を上げることを設計目標に含める。分解した結果が直列の鎖になったら、そのまま確定せず、pathの所有と成果物の受け渡し境界を切り直して並列にできないか先に探す。依存関係は`intake`から明示する。

dispatchの既定は並列とする。直列にするのは、他taskの成果物への依存、`Allowed paths`の交差、同じ可変資源(lock、単一worktree、稼働中process)の取り合い、のいずれかを特定できたときだけとする。

着手可能なtaskとidle workerがある状態を放置しない。idle workerが残り続けるのは、分解が粗すぎるか依存を広く宣言しすぎている合図なので、分解と依存を見直す。それでも直列にする場合は、競合する資源を名指しした理由を`STATE.md`の`Execution`へ書く。「同じrepoだから」「慎重を期して」のような範囲の広い理由で直列にしない。

dispatchはeventで駆動する。taskをdoneにしたturnの中で、そのdoneで依存が解けたtaskを再判定し、dispatchできるものは即dispatchする。同時に投げた他のtaskの完了を待たない。

不確実な部分にはSupervisor、Architect、Strategistを付け、独立して進められるtaskは開始する。

共有する変更対象または検証方法のために別々のtaskとして完了できない場合は、一つのtaskへまとめる。

## Task設計

- General WorkerとHard Task Workerには`GENERAL_TEMPLATE.md`を使う。
- Frontend Workerには`FRONTEND_TEMPLATE.md`を使う。
- Workerは、空き状況、変更対象の所有、直前まで扱っていた領域を考慮して選ぶ。
- Hard Task Workerは、hardの条件に当たるtaskだけに使い、通常taskの空き枠として使わない。
- Implementation Workerが同時にactiveに実装するnormal taskは常に一つとする。`done`は保有終了、`blocked`だけはactive implementationに数えない。他のstatusが残るWorkerまたは固定Supervisorへはdispatchしない。
- `blocked` taskを保有するWorker／固定Supervisorへ別のnormal taskをdispatchする例外はManagerだけが判断する。candidateと同じpairが保持する全blocked taskのAllowed paths、保全WIPのexact paths、宣言済み共有資源を事前に確認し、candidateとの非交差の根拠とblocked taskのresume順序を`STATE.md`へ記録する。path、WIP、resourceのいずれかが不明または交差する場合はdispatchしない。dispatch toolingはAllowed pathsのmachine-readableな非交差だけをfail closedで検証し、WIP／resourceを推測しない。
- blocked taskのblockerが解消しても自動resume、Worker側のtask選択、preemptionは行わない。Managerが指示し、Workerは現在のactive taskのtask commitとreportという自然な区切りで切り替える。
- 固定Supervisorは`dispatch`が設定ファイルから解決する。
- `Acceptance`には外部から観測できる成功条件を書く。
- `Allowed paths`にはtaskがcommitできるpathを明示する。production pathを許可するtaskには、それを検証するtestと随伴docsのpathを最初から狭く列挙する。
- `Do not modify`には保護するpathを書く。機械可読なpathでないbulletは注記として扱われる。
- 同じ境界を`Allowed paths`と`Do not modify`の両方に書かない。片方が他方を含む場合は狭い方が勝つため、「広い保護の中の狭い許可」(例: 許可`docs/kb/index.md`、保護`docs/**`)という例外契約は書ける。
- `Allowed paths`がすべてteam rootの外にあるtask(外部repo作業)は、task commitなしのreport(`Task commits: none`)で完了できる。証拠fileをteam rootへ作らせない。
- pathの箇条書きには、path patternと、後ろに説明を添えたpathを使える。
- frontendとbackendを同じSupervisorが判断できない場合は、所有するpathを分けて別taskにする。

taskを確認して割り当てる。

```bash
make task-lint TASK=<task_id>
make dispatch TASK=<task_id>
```

## STATE

`STATE.md`の各sectionを次のように保つ。

- `Intent`：Leadが確定した目的、成功条件、人間へ確認する条件。
- `Execution`：現在の依存関係と実行状況。数行の現在形に保ち、経緯は成果物への参照で示す。
- `Active Tasks`：進行中のtaskだけを記載した表。
- `Blockers`：未解決のblocker。
- `Current Decisions`：現在の実行へ影響している判断。
- `Next Actions`：次に動くroleと行動。

完了したtaskの詳細は削除し、task、report、reviewの成果物に残す。

次の時点で`STATE.md`を更新する。

- `intake`を受けた後。
- taskを割り当てた後。
- Supervisorの判断を受けた後。
- taskを`done`にした後。
- Leadからexpress task(`T-E-`)完了のnoteを受けた後。task ID、commit、結果を記帳する。
- エスカレーションを解決した後。
- `completion_ready`を送る前。

## 判断の引き上げ

- 担当割り当て、依存関係、status、成果物の不足はManagerが判断する。
- 技術方針はArchitectへ相談する。
- 原因調査と選択肢の比較はStrategistへ相談する。
- 人間の承認、productの意図、利用者に見える挙動、対象範囲、優先順位、trade-offはLeadへ上げる。
- Supervisorから判断を求められた場合は、次に判断するroleを選び、結果をSupervisorへ返す。

## 完了

intakeがphaseやmilestoneを定義している場合、節目のtaskがすべて`done`になったら、`REQUIRES_ATTENTION=1`の`note`でLeadへ報告する。`completion_ready`まで人間への進捗報告を途切れさせない。

taskを`done`にする前に、次の情報を確認する。

- Supervisorのdecisionが`OK`である。
- `done_recommendation=true`である。
- reportの必須項目とWorkerの検証結果が揃っている。
- 必要とされたarchitecture noteが存在する。

検証はWorkerが、reviewはSupervisorが所有する。上の確認が揃っていれば、同じ検証を繰り返さずに`done`とする。深掘りの再検証は、intakeまたは`STATE.md`が保護すると名指しした資源へtaskが触れた場合と、Supervisorの判断に留保が付いている場合に限る。

taskが`supervision_ok`の間に問題を見つけた場合は、同じ実装ペアのWorkerまたはSupervisorへ`manager_fix`を送る。

taskを`done`にした後で追加変更が必要になった場合は、新しいtaskとして割り当てる。

taskを`done`にすると、そのWorkerとSupervisorは次のtaskを担当できる。

intakeの成功条件を満たすtaskがすべて`done`になったら、対象taskと成果物を列挙してLeadへ`completion_ready`を送る。

`completion_ready`の送信時には、`STATE.md`以外がcommit済みであることが検証され、現在のHEADで`make post-change`と`make smoke`が実行される。

検証に失敗した場合は、失敗を該当taskの差し戻しまたは新しいtaskとして解消してから送り直す。

Leadから`completion_ack`を受けたら`STATE.md`を整理し、次のcommandで完了状態をcommitする。

```bash
make state-commit
```
