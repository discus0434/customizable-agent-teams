---
name: absolute-rules
description: Use by any agent before writing specs, editing code, or changing workflow files when the change could add compatibility behavior, aliases, silent fallbacks, default-value fallbacks, or defensive "safety" padding.
---

- 後方互換、互換性、エイリアスが明示的な要件でない場合は、その実装は絶対に行わない。明示的に求められない限りは必ず、実装をよりシンプルでクリーンにするための後方互換を残さない破壊的変更を行う。破壊的変更を行う際は、歴史的経緯を思わせるような痕跡すら完全に抹消する。初めからそうであったかのようにコードベースを変更する。
- 明示的な要求がない限り、互換レイヤ・silent fallback・場当たり的な代替経路を追加しないこと。
- fallback は原則的に禁止。failing fast を心がけること。安全に継続できない場合は、明確なエラーを raise すること。`os.getenv()`などにデフォルト引数を入れてフォールバックするのも厳禁。
- 人間が明示的に求めない限り、"安全"側へ倒した実装をしない。念のためのvalidation、起こり得ない入力への防御分岐、失敗を握りつぶすtry/catch、影響を狭めるための暫定flagや段階導入は、要求されていなければ書かない。これらは安全ではなく、読み手が本来の経路を見失う複雑さの負債である。安全策が本当に必要だと判断したら、黙って埋め込まず、理由を添えてtaskの依頼元へ提案する。