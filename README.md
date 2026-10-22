# UpdateTools

Winget・Scoop・uv tool をまとめて更新する小さなスクリプト。UpdateTools 自体も Scoop で管理します。

## インストール

現在、配布先を移行準備中です。以下の `gitlab.example.com` とプロジェクト ID `1234` は仮値です。移行先の確定後、`install.ps1` と `Publish-Package.ps1` を含めて実際の配布先へ置き換えてください。

配布先の設定後、通常権限の PowerShell で実行します。

```powershell
irm https://gitlab.example.com/api/v4/projects/1234/packages/generic/update-tools/latest/install.ps1 | iex
```

Scoop がなければ公式インストーラーで導入し、Winget がなければ `scoop install main/winget`、UpdateTools が Scoop に未登録なら公開マニフェストからインストールします。既にあるものは再インストール・更新しません。導入時にアプリの一括更新は実行しません。

導入時に `UV_SYSTEM_CERTS=true` をユーザー環境変数に保存し、実行中の PowerShell にも反映します。uv が Windows の証明書ストアを使うための設定です。既存環境にも上記ワンライナーの再実行で設定できます。

0.2.x 以前から移行する場合も上記を実行します。古い `%LOCALAPPDATA%\UpdateTools\bin` の PATH 登録は外してください。

## 使い方

```powershell
update-tools                       # Winget → Scoop → uv tools の順で更新
update-tools -WhatIf               # 実行内容の表示だけ
update-tools -IncludeGlobalScoop   # Scoop のグローバルアプリも更新
```

`scoop update *` で UpdateTools 自体も更新され、新しいコードは次回起動から使われます。uv はインストール済みの場合だけ `uv tool upgrade --all` を実行します。uv の自動導入・公式版の `uv self update`・独自の自己更新機構はありません。

Winget はバージョン不明のアプリも更新対象に含め、利用規約に自動同意します。途中で失敗しても後続を実行し、失敗があれば終了コード `1` を返します。「更新なし」は成功扱いです。文字化け対策として実行中だけ出力を UTF-8 にします。

## 開発・配布

`VERSION` を上げ、`tests\Smoke.Tests.ps1` で検証してからコミット・push し、`Publish-Package.ps1` を実行します。配布先の GitLab にログイン済みの `glab` が必要です。

ZIP と Scoop マニフェストを Generic Package に公開します。Scoop がマニフェストの URL を記憶して更新を確認するため、専用 bucket や独自の更新コードは不要です。

アンインストール: `scoop uninstall update-tools`
