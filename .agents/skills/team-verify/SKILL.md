---
name: team-verify
description: Guides fresh verification evidence collection before completion claims. Use before saying work is done, fixed, passing, ready for review, ready to report, OK, SHIP, or complete.
---

# team-verify

完了主張は、直近の検証 evidence の後にだけ行う。

## Gate

1. 主張を証明する command / inspection を特定する。
2. 直近で実行する。
3. exit code と output を読む。
4. acceptance と照合する。
5. 成功、失敗、未実行、未検証範囲を report に書く。

## Not Enough

- lint だけで build 成功を主張する。
- unit test だけで end-to-end contract を満たしたことにする。
- worker の報告だけで done と判断する。
- 古い結果を現在の evidence として扱う。

## Use Before

- worker report
- reviewer `OK` 判断
- manager の `done` 判断
- release-captain の `SHIP` 判断
- lead のユーザー向け完了報告
