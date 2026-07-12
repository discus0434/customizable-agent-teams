# T-XXX: <title>

Worker: frontend-worker-1
Supervisor:
Architecture required: false

## Context

- 背景：
- 確認済みの事実：
- 関連する文書と成果物：
- 既存のUIとdesign system：

## Allowed paths

- `path/to/frontend/file`

## Do not modify

- `.agents/state/STATE.md`
- `.agents/state/MEMORY.md`

pathの箇条書きには、通常のpath、path pattern、backtickで囲んだpathを使える。

pathの後ろには説明を加えられる。

`Allowed paths`には、このtaskがcommitできるpathだけを書く。

`Do not modify`には、個別に保護する必要があるpathだけを書き、`Allowed paths`と重複させない。

## Goal

<このtaskで成立させる利用者に見える状態>

## Acceptance

- <画面、操作、状態として観測できる成功条件>

## Constraints

- <design、platform、操作、accessibility、既存要件>

## View Direction

- 対象となる画面：
- 情報の優先順位：
- 操作とnavigation：
- responsiveまたはplatform対応：
- 既存方針だけで判断できる内容：

## Visual Verification

- Project guidance：`AGENTS.md`のvisual verificationを参照する。
- 確認する画面と状態：
- deviceとviewport：
- Screenshot evidence：`.agents/queue/visuals/T-XXX/`

## Verification

- Task-specific: `<command>`
- `make post-change`
- `make smoke`

## Report Evidence

- summary、変更file、task commit、task固有の検証、post-change、smokeを具体的に記録する。
- 画面方針のdecision、表示確認、screenshot path、Frontend Criticの指摘と対応を記録する。

## Supervision

- <早い段階でFrontend Criticへ確認する判断>

## Escalation

- <ManagerまたはLeadの判断が必要になる条件>
