# UpdateTools

Winget・Scoop・uv tool の一括更新コマンド。

## インストール

PowerShell で次のワンライナーを実行します。管理者権限・Git・glab は不要です。

```powershell
irm https://gitlab.example.com/api/v4/projects/1234/packages/generic/update-tools/latest/install.ps1 | iex
```

`%LOCALAPPDATA%\UpdateTools\bin` にインストールし、ユーザー PATH と実行中の PowerShell の PATH に追加します。既に開いている別のターミナルでは開き直してください。再実行すると UpdateTools 自体を最新の配布版に更新します。インストール時にアプリの一括更新は実行しません。

特定バージョンを入れる場合は URL の `latest` を `0.1.0` などに置き換えます。Generic Package にあるインストーラーは本体を内包しているため、導入時のダウンロードは1回です。

リポジトリは Internal、Package Registry は匿名ダウンロード可の設定です。URL にアクセスできるネットワークから利用できます。

## 使い方

インストール後は、どのフォルダからでも実行できます。

```powershell
update-tools
update-tools -WhatIf
```

0.2.0 以降のインストーラー導入版は、起動時に UpdateTools 自体の最新版を確認します。新しい版があればチェックサムを検証して適用し、その場で新しいコードに切り替えてからアプリの一括更新を続けます。最新版の場合は再インストールしません。

自己更新の通信や適用に失敗した場合は警告を表示し、手元の版で続行します。通信のタイムアウトは版の確認が10秒、インストーラーの取得が30秒です。`-WhatIf` では自己更新の通信・書き換えも行いません。自己更新だけ省略する場合は `update-tools -SkipSelfUpdate` を使います。

0.1.x からは、初回だけインストール用ワンライナーを再実行してください。Git リポジトリを直接実行する開発環境は自己更新の対象外です。

リポジトリを取得して直接実行する場合:

```powershell
.\update-tools.cmd
```

実行するコマンドだけ確認する場合:

```powershell
.\update-tools.cmd -WhatIf
```

順に以下を実行します。

1. UpdateTools 自体の最新版を確認・適用
2. `winget upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements`
3. `scoop update`
4. `scoop update *`
5. 公式インストーラー版の uv なら `uv self update`
6. `uv tool upgrade --all`

Scoop・uv が見つからない場合は、それぞれ「インストールしますか？ [y/N]」と確認します。`y` または `Y` の場合だけインストールし、Enter・`n`・その他の入力ならそのツールをスキップします。

- Scoop: 公式インストーラー `https://get.scoop.sh` を使用します。
- uv: Scoop が利用できれば `scoop install main/uv`、利用できなければ公式インストーラー `https://astral.sh/uv/install.ps1` を使用します。
- インストール後は現在のプロセスにも PATH の追加を反映し、そのまま更新を続けます。
- `-WhatIf` では確認入力・ダウンロード・インストール・更新を行いません。

失敗した処理があっても後続を実行し、最後に結果を表示します。終了コードは失敗がなければ `0`、更新・インストールの失敗や Winget 未検出があれば `1` です。インストールを断った場合や Winget の「更新なし」は失敗として扱いません。

Winget のソース・パッケージ利用規約には自動同意します。現在のバージョンが不明なアプリも更新対象に含めます。インストーラーによっては画面操作や管理者権限の承認が必要です。固定・保留設定や uv tool のバージョン制約は各ツールの通常の動作に従います。

Scoop は通常ユーザーのアプリが対象です。グローバルにインストールしたアプリも更新する場合は、管理者のターミナルで以下を実行します。

```powershell
.\update-tools.cmd -IncludeGlobalScoop
```

uv 本体の導入元は PATH 上で選ばれる実行ファイルを基準に判定します。Scoop 版は Scoop に更新を任せ、公式版はインストール記録（`uv-receipt.json`）の保存先と実行ファイルの一致を確認して `uv self update` を実行します。両方が存在する場合も、実際に使用する uv を判定します。

Winget・pip 等による導入や、公式インストール記録がない場合は、uv 本体の自己更新をスキップして表示します。`uv tool upgrade --all` は引き続き実行します。グローバルの Scoop 版 uv 本体を更新するには `-IncludeGlobalScoop` が必要です。

ネットワーク通信や実際の更新を行わずに分岐を検証するテスト:

```powershell
pwsh -NoProfile -File .\tests\Update-Tools.Tests.ps1
pwsh -NoProfile -File .\tests\Installer.Tests.ps1
pwsh -NoProfile -File .\tests\Encoding.Tests.ps1
pwsh -NoProfile -File .\tests\SelfUpdate.Tests.ps1
```

文字コードのテストは実際の `winget upgrade --help` を使用します。アプリの更新やインストールは行いません。

## 日本語の文字化け

0.1.1 で、CP932 のターミナル環境で Winget の日本語が `繝...` のように崩れる問題を修正しました。Winget の実行中だけ UTF-8 として出力を読み取り、終了後（失敗時も含む）は元の文字コード設定に戻します。既存のインストールは上記ワンライナーを再実行すると更新できます。

## 配布版の更新

`VERSION` を上げ、上記テストを実行し、変更をコミット・push してから以下を実行します。`glab` は `gitlab.example.com` にログイン済みである必要があります。

```powershell
pwsh -NoProfile -File .\Publish-Package.ps1
```

`dist/install.ps1`、チェックサム、自己更新用の `release.json` を生成し、Generic Package `update-tools/<VERSION>`、続いて `update-tools/latest` にアップロードします。既存バージョンの再公開は拒否します。`release.json` はインストーラーの公開後にアップロードし、自己更新ではそこに記載されたバージョンの固定 URL とチェックサムを使います。`latest` の同名ファイルは GitLab の最新アップロードが取得されます。認証情報は配布ファイルに含めません。

ローカル検証用にインストール先を変えて PATH 登録を省略する場合:

```powershell
.\dist\install.ps1 -InstallDir "$env:TEMP\UpdateTools-test\bin" -NoPath
```

アンインストールは `%LOCALAPPDATA%\UpdateTools` を削除し、ユーザー環境変数 PATH から `%LOCALAPPDATA%\UpdateTools\bin` を取り除きます。

参考: [Winget upgrade](https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade)、[Scoop](https://github.com/ScoopInstaller/Scoop/wiki/FAQ)、[uv のインストール・自己更新](https://docs.astral.sh/uv/getting-started/installation/)、[uv tools](https://docs.astral.sh/uv/concepts/tools/)。
