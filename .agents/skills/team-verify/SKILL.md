---
name: team-verify
description: Workerのreport、SupervisorのOK、Managerのdone、Leadの完了報告など、完了を表す判断の前に、roleごとに必要な現在の検証結果と対応するcommitまたは状態を確認するために使う。
---

# team-verify

## Roleごとの証拠

- Implementation Workerは、task固有の検証、`make post-change`、`make smoke`を実行し、commandと結果をreportへ記録する。
- Supervisorは、task、task commit、report、関連コードを調べ、変更の不確実さと影響に応じて追加確認を選ぶ。
- Managerは、task state、成果物の必須項目、Supervisorの判断を確認する。
- Leadは、完了報告の前にHEADで`make post-change`と`make smoke`を実行し、差分と注意点を確認して人間へ報告する。

検証後に対象commitまたは状態が変わった場合は、その検証を担当するroleが結果を更新する。

## 確認事項

- command名だけでなく、exit statusと結果を確認する。
- lintだけを根拠にbuild成功を判断しない。
- unit testだけを根拠にend-to-endの成功を判断しない。
- 過去の結果を、現在の状態に対する結果として扱わない。
- 実行していない検証と、未確認の範囲を成果物へ明記する。
