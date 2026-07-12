---
name: team-verify
description: Guides fresh verification evidence collection before completion claims. Use before saying work is done, fixed, passing, ready for supervision, ready to report, OK, SHIP, or complete.
---

# team-verify

完了判断は、その判断を担当する role に必要な、現在の evidence に基づける。

## Evidence Ownership

- Implementation Worker は task-specific checks、`make post-change`、`make smoke` を実行し、command と結果を report に残す。
- Supervisor は task contract、task commits、report、関連コードを調査し、uncertainty と impact に応じて追加の command や inspection を選ぶ。
- Manager は task state、artifact の完全性、Supervisor の判断、bundle の整合性を確認する。
- Release Captain は current commit に対する fresh な `make post-change` と `make smoke`、および whole-system evidence で release を判断する。
- Lead は release decision、verified commit、verification evidence、caveat を確認して人間へ報告する。

Evidence の対象 commit や状態が変わった場合は、その evidence を担当する role が更新する。

## Not Enough

- lint だけで build 成功を主張する。
- unit test だけで end-to-end contract を満たしたことにする。
- command 名だけを記録し、exit status や結果を確認しない。
- 古い結果を現在の evidence として扱う。

## Use Before

- implementation report
- Supervisor `OK` 判断
- manager の `done` 判断
- release-captain の `SHIP` 判断
- lead のユーザー向け完了報告
