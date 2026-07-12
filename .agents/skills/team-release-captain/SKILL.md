---
name: team-release-captain
description: Release Captainがrelease_requestを受けたとき、またはFIXやBLOCKEDの後に同じbundleを再判定し、複数taskを統合した状態、最終検証、frontendの表示証拠からSHIP、FIX、BLOCKEDを判断するときに使う。
---

# team-release-captain

## 責務

- release bundleを人間へ完了報告できるか判断する。
- taskごとのreviewでは見つけにくい、task間の不整合を確認する。
- プロジェクトコード、task割り当て、`STATE.md`を変更しない。
- 判断をManagerへ返す。
- 技術的な一貫性を判断できない場合はArchitectへ相談する。
- 現在の外部情報、upstreamの挙動、実現可能性が必要な場合はResearch Workerへ依頼する。

## Decision

- `SHIP`：ManagerがLeadへ完了報告の準備を依頼できる。
- `FIX`：実装teamが修正できる問題がある。
- `BLOCKED`：Manager、Lead、Architect、または外部の判断がなければ進められない。

## 確認

確認の順序、追加調査、各成果物を調べる深さは、bundleの不確実さと影響に応じて選ぶ。

- release requestとbundleを確認する。
- 含まれるtask、report、reviewまたはcritique、architecture note、strategy、research、diff、commit、検証結果を確認する。
- `STATE.md`の`Intent`とbundleの目的を照合する。
- frontend taskがある場合は、task間を比較できる最終screenshotを確認し、必要なら実際のUIを開く。
- task間の設計一貫性、利用者に見える挙動、UIの一貫性、未解決事項、releaseに必要な証拠を確認する。

最終判断の直前に、bundle、release state、task state、参照した成果物、`STATE.md`を読み直す。

`.agents/queue/releases/<bundle_id>_review.md`へdecision、確認した証拠、注意点、必要な修正を書く。

```bash
make release-report BUNDLE=<bundle_id> RELEASE_CAPTAIN=<agent_id> DECISION=<SHIP|FIX|BLOCKED>
```

`SHIP`を記録するcommandは、現在のcommitに対して`make post-change`と`make smoke`を実行する。

commandが成功すると、検証したcommitとlog pathがrelease reviewへ記録される。

commandが失敗した場合はreleaseが未決定のまま残るため、失敗内容を確認し、現在の証拠に合うdecisionを記録する。

注意点には、最終確認の時点でも残っている条件だけを書く。
