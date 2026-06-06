# Codex Profile Manager

[English](README.md) | [简体中文](README.zh-CN.md) | 日本語

複数の Codex アカウント Profile を管理するための、macOS ネイティブのメニュー
バーアプリです。分離された `CODEX_HOME`、クォータ表示、切り替え前の事前確認、
更新日のリマインダーを扱えます。

> このプロジェクトは独立したローカル補助ツールです。Codex や OpenAI の
> アカウント制限を回避するものではなく、公式の `codex login` フローを置き換える
> ものでもありません。

## 概要

Codex Profile Manager は、正当に複数の Codex 対応アカウントを使うユーザーが、
Codex Desktop のローカル実行環境をより安全に切り替えるためのツールです。

`codex logout` と `codex login` を繰り返す代わりに、このアプリはアカウントごと
にローカル Profile を作成します。各 Profile は独自の `CODEX_HOME` を持つため、
OAuth 認証情報とアカウント固有の状態を分離できます。切り替え時には、対象
Profile の検証、実行中タスクの確認、選択された状態共有モードの準備、Codex
Desktop の停止、選択された実行環境での再起動を行います。

## 機能

- macOS ネイティブの SwiftUI メニューバーアプリ。
- 複数の Codex Profile を管理し、それぞれ独立した `CODEX_HOME` を使用。
- 各 Profile に対して公式の `codex login` フローを起動。
- クォータ更新後、Codex が返す実際のアカウント情報を Profile に紐付け。
- primary / secondary rate-limit ウィンドウのクォータスナップショットを表示。
- 3 種類の切り替えモード：
  - **Isolated**：アカウント、スレッド、プロジェクト、ツール、設定を Profile
    自身の `CODEX_HOME` に保持。
  - **Shared State**：複数アカウントが 1 つのローカル Codex 状態ディレクトリを
    共有し、切り替え時に選択アカウントの認証情報をコピー。
  - **Partial Shared**：認証情報とスレッドは分離し、設定、ツール、skills、
    prompts、themes、rules、MCP 設定、hooks を同期。
- 実際にアカウントを切り替える前に、認証、アカウント識別、状態準備、ローカル
  コンテキスト保持の見込みを検証する事前確認。
- 現在の Codex アカウントに実行中タスクがある可能性を検出した場合、切り替えを
  ブロック。
- 更新日と通知タイミングを設定できるローカルリマインダー。
- トラブルシューティング用の操作ログと監査ログをローカル保存。
- ローカル署名済み `.app` bundle を作成するパッケージングスクリプト。

## 解決する課題

Codex Desktop と公式 CLI は、基本的に 1 つのアクティブなローカル実行ディレクトリ
を前提にしています。これはシンプルですが、複数アカウントを明確に分離したい場合
には不便です。

このアプリは次の 3 点を重視しています：

1. アカウントごとに認証情報を分離する。
2. 切り替えを明示的にし、ローカルコンテキストを失うリスクを下げる。
3. クォータと更新日の情報を日常の作業フローの近くに表示する。

## 要件

- macOS 14 以降。
- Swift 6.1 toolchain。
- `Codex.app` としてインストールされた Codex Desktop。
- 公式 `codex` CLI が `PATH`、`/opt/homebrew/bin`、または `/usr/local/bin`
  から見つかること。

## プロジェクト運用

- 現在のバージョン：[`0.3.5`](VERSION)
- バージョン管理ポリシー：[docs/VERSIONING.md](docs/VERSIONING.md)
- ブランチとコントリビューションの流れ：[docs/BRANCHING.md](docs/BRANCHING.md)
- 自動更新とリリース設定：[docs/AUTO_UPDATE.md](docs/AUTO_UPDATE.md)
- 変更履歴：[CHANGELOG.md](CHANGELOG.md)

## ビルド

セルフテストを実行：

```sh
Scripts/run_self_tests.sh
```

Swift Package Manager でビルド：

```sh
swift build
```

ローカル `.app` bundle を作成：

```sh
Scripts/package_app.sh
```

生成されるアプリ：

```text
Build/CodexProfileManager.app
```

## 使い方

### 1. Profile を作成

アプリを開き、`+` をクリックします。

任意の表示名、色、毎月の更新日を入力できます。アプリは新しい Profile
ディレクトリを作成し、その Profile の `CODEX_HOME` を使って公式 `codex login`
コマンドを Terminal で起動します。

ブラウザでの認可が完了すると、ログインコマンドは自動的に終了します。アプリに戻り
クォータを更新すると、Profile が Codex から返された実際のアカウントメールに
紐付けられます。

### 2. 追加アカウントを登録

アカウントごとに同じ手順を繰り返します。各 Profile には個別のローカル
ディレクトリが割り当てられます：

```text
~/Library/Application Support/CodexProfileManager/Profiles/<profile-id>/
```

Profile home に公式 Codex ログインフローで作成された `auth.json` がある場合、
アプリはその Profile をログイン済みとして扱います。

### 3. クォータを更新

更新操作により、各 Profile のクォータ情報を取得します。更新時には Codex が返す
実際のアカウント識別情報も Profile に紐付けられるため、同じアカウントを誤って
複数の Profile に割り当てるリスクを減らせます。

### 4. アカウントを切り替え

対象 Profile の切り替え操作をクリックし、モードを選びます。

切り替え完了前に、アプリは次を実行します：

- 対象 Profile home を検証；
- 対象 Profile がログイン済みであることを確認；
- 対象アカウントの識別情報が紐付け済み Profile と一致することを確認；
- 最近の Codex スレッドに active / running タスクがないか確認；
- 選択された切り替えモードに応じて状態を準備；
- Codex Desktop を停止；
- 選択された `CODEX_HOME` で Codex Desktop を再起動。

Codex を停止または再起動せずに何が起きるか確認したい場合は、事前確認を使って
ください。

## 切り替えモード

### Isolated

最も安全なモードです。Codex Desktop は対象 Profile 自身の `CODEX_HOME` で起動
します。

アカウント分離を、スレッドやプロジェクトのローカルコンテキスト共有より優先したい
場合に適しています。

### Shared State

Codex Desktop はこのアプリが管理する共有 `CODEX_HOME` で起動します。切り替え時
には、選択されたアカウントの auth ファイルが共有状態にコピーされます。

より多くのローカルプロジェクトやスレッド状態を保持できる可能性がありますが、
リモートスレッドを別アカウントで継続利用できるかは Codex 側の挙動に依存し、
保証されません。

### Partial Shared

Codex Desktop は対象 Profile 自身の `CODEX_HOME` で起動しますが、選択された設定
やカスタマイズ項目は共有領域から同期されます。

現在同期される項目：

- `config.toml`
- `AGENTS.md`
- `AGENTS.override.md`
- `models_cache.json`
- `skills/`
- `plugins/`
- `prompts/`
- `themes/`
- `rules/`
- `mcp/`
- `hooks/`

アカウントと会話は分離しつつ、ツールと設定を揃えたい場合に適しています。

## データ保存場所

デフォルトでは、アプリデータは次の場所に保存されます：

```text
~/Library/Application Support/CodexProfileManager/
```

主なパス：

```text
Profiles/              アカウントごとの CODEX_HOME
SharedCodexHome/       shared-state モードで使う実行ディレクトリ
PartialSharedState/    partial-shared モードで使う設定とツール状態
profiles.json          Profile メタデータ
quota-cache.json       キャッシュされたクォータスナップショット
audit.jsonl            高レベルの監査イベント
operations.jsonl       詳細な操作ログ
```

テストやローカル開発では、環境変数でルートを上書きできます：

```sh
CODEX_PROFILE_MANAGER_ROOT=/tmp/codex-profile-manager-dev
```

## 安全モデル

- OAuth ログインは公式 `codex login` コマンドで行います。
- 認証情報はローカルの Profile 固有 `CODEX_HOME` に保存されます。
- 実行中の Codex タスクが検出された場合、または安全な切り替えを確認できない場合、
  直接切り替えをブロックします。
- Codex が返すアカウント識別情報で Profile を検証し、アカウントの取り違えを
  減らします。
- ローカルアプリディレクトリは可能な限り制限された権限で作成されます。
- アカウントの自動ローテーションや、クォータ/利用制限の回避は行いません。

## 現在の制限

- 各アカウントは少なくとも一度、公式ログインフローを完了する必要があります。
- リモート Codex スレッドはアカウント間で移行されません。
- shared-state モードはローカル状態を保持できますが、別アカウントでリモート
  スレッドを継続利用できることは保証しません。
- 実行中タスクがないことを確認できない場合、推測せずに切り替えをブロックします。
- ローカルに Codex Desktop と Codex CLI がインストールされている必要があります。

## プロジェクト構成

```text
Sources/CodexProfileManager/
  AppModel.swift                 アプリ状態と主要ワークフローの制御
  CodexLauncher.swift            ログイン、停止、起動の連携
  CodexStateCoordinator.swift    isolated/shared/partial state の準備
  CodexAppServerClient.swift     Codex アカウント、クォータ、スレッドの問い合わせ
  ProfileStore.swift             Profile とクォータの永続化
  RenewalReminderService.swift   ローカル更新日通知
  MainView.swift                 SwiftUI UI
  Models.swift                   共通データモデル
  Paths.swift                    実行パスと環境変数ヘルパー
  OperationLogger.swift          ローカル操作ログ

Scripts/
  run_self_tests.sh              軽量セルフテスト
  package_app.sh                 ローカル app bundle 作成スクリプト
  generate_icon.swift            アプリアイコン生成ヘルパー

Tests/SelfTests/
  main.swift                     モデルと状態管理のセルフテスト
```

## 開発

コミット前に推奨されるチェック：

```sh
Scripts/run_self_tests.sh
swift build
```

セルフテストスクリプトは、コアモデルと状態管理ファイルを一時的なバイナリに
コンパイルして動作確認を行います。ユーザーの実際の Codex Profile データには
書き込みません。

## サポートと連絡先

このプロジェクトが役に立った場合は、作者にコーヒーをごちそうする形でサポート
できます。

| Alipay | WeChat Pay |
| --- | --- |
| <img src="docs/assets/sponsor-alipay.jpg" alt="Alipay QR code" width="260"> | <img src="docs/assets/sponsor-wechat.jpg" alt="WeChat Pay QR code" width="260"> |

質問、不具合報告、または個別の連絡は、次のメールアドレスまでお願いします：
[781830133@qq.com](mailto:781830133@qq.com)。

## ライセンス

このプロジェクトは MIT License のもとで公開されています。詳細は
[LICENSE](LICENSE) を参照してください。
