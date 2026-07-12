---
name: absolute-rules
description: 仕様、コード、workflowを変更するときに、明示されていない後方互換、alias、互換layer、silent fallback、default値によるfallbackを避け、現在の要件に合う単一の実装へ整理するために使う。
---

# absolute-rules

- 後方互換が明示的な要件でない場合は、古いinterfaceと挙動を残さない。
- 破壊的変更によって設計が単純になる場合は、古い経路、alias、互換layerを削除する。
- 変更後の設計に不要な文書、test、設定、名称も削除し、過去の経緯を説明する記述を残さない。
- silent fallbackと、場当たり的な代替経路を追加しない。
- 環境変数、設定、引数が必須なら、default値で補わず不足を明示する。
- 作業を継続できない場合は、失敗した理由、守るべき条件、成功させる方法を示して停止する。
