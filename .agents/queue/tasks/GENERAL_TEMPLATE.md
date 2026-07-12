# T-XXX: <title>

Worker: general-worker-1
Supervisor:
Architecture required: false

## Context

- 背景：
- 確認済みの事実：
- 関連する文書と成果物：

## Allowed paths

- `path/to/file`

## Do not modify

- `.agents/state/STATE.md`
- `.agents/state/MEMORY.md`

pathの箇条書きには、通常のpath、path pattern、backtickで囲んだpathを使える。

pathの後ろには説明を加えられる。

`Allowed paths`には、このtaskがcommitできるpathだけを書く。

`Do not modify`には、個別に保護する必要があるpathだけを書き、`Allowed paths`と重複させない。

## Goal

<このtaskで成立させる状態>

## Acceptance

- <外部から観測できる成功条件>

## Constraints

- <守るべき境界と既存要件>

## Verification

- Task-specific: `<command>`
- `make post-change`
- `make smoke`

## Report Evidence

- summary、変更file、task commit、task固有の検証、post-change、smokeを具体的に記録する。
- Supervisorとの相談、feedback、strategyまたはarchitectureの成果物を記録する。

## Supervision

- <早い段階でSupervisorへ確認する判断>

## Escalation

- <ManagerまたはLeadの判断が必要になる条件>
