# LLM Usage Float

Claude Code と Codex の現在の使用量（レート制限の消費率）と、そのリセットまでの残り時間を
macOS のデスクトップ上に **半透明の小さなガジェット** として常時表示するアプリです。

> **English:** A tiny macOS menu-bar app that shows your Claude Code and Codex rate-limit usage
> (5-hour / 7-day windows, time until reset) in a translucent desktop widget. It reads the OAuth
> tokens that the `claude` and `codex` CLIs already store on your Mac and calls the same usage
> endpoints the CLIs use. Build from source with `./build.sh install` (Xcode Command Line Tools
> required). The README is in Japanese; the menu items are in Japanese too.

```
┌──────────────────────────────────┐
│ ● Claude Code  Max               │
│  › 5時間  ▂▂▂░░░ 13%  あと4時間27分 │
│  › 7日間  ▂▂▂▂░░ 21%   あと1日9時間 │
│ ──────────────────────────────── │
│ ● Codex  Pro Lite                │
│  › 7日間  ▂▂▂▂░░ 23%  あと4日20時間 │
│ ↻ 更新 18:32                   ⚙ │
└──────────────────────────────────┘
```

- 既定ではデスクトップ上（他のウィンドウの下）に固定して全スペースで表示。メニューの「表示モード」で「デスクトップに固定 / 通常のウィンドウ / 常に最前面」を切り替え可能。ドラッグで自由に移動（位置は記憶されます）
- 各枠は既定で 1 行のコンパクト表示（ラベル・短いバー・使用率・残り時間）。行をクリックすると詳細（フルバー + リセット時刻）に展開でき、状態は記憶されます
- 不透明度（50〜100%）と更新間隔（1〜30分）を右クリック / メニューバーから変更
- メニューバーにも「C 42% · X 13%」のように 5 時間枠の使用率を表示
- Dock にはアイコンを出さないメニューバー常駐アプリ

## 注意事項（公開版をお使いの方へ）

- 使用量の取得に使う API（Claude: `api.anthropic.com/api/oauth/usage`、Codex: `chatgpt.com/backend-api/wham/usage`）は
  **どちらも非公式・未ドキュメント**です。予告なく仕様が変わり、表示できなくなる可能性があります。
- アプリは Claude Code / Codex CLI がローカルに保存している **OAuth トークンを読み取ります**（macOS キーチェーンと
  `~/.claude` / `~/.codex` 配下）。トークンは上記の公式ドメインへの使用量取得にのみ使い、それ以外には送信・保存しません。
  コードは `Sources/LLMUsageFloat/ClaudeProvider.swift` と `CodexProvider.swift` で確認できます。
- トークンのリフレッシュは行いません。期限切れ表示が出たら `claude` / `codex` を一度起動してください。
- 動作確認環境: macOS 26/27、Apple Silicon、Claude Code 2.1.x、Codex CLI 0.159。他の環境での動作は未確認です。
- ライセンス: MIT。自己責任でご利用ください。

## 動作要件

- macOS 13 Ventura 以降
- Xcode Command Line Tools（`xcode-select --install`）または Xcode
- Claude Code **CLI** にログイン済み（ターミナルで `claude auth login`、または `claude` → `/login`）。
  Claude デスクトップアプリ（Code タブ）のログインは CLI とは別管理なので、それだけでは使用量を取得できません。`claude auth status` で `loggedIn: true` になっていれば OK です
- Codex CLI に ChatGPT アカウントでログイン済み（`codex login`）

## ビルド・インストール・起動

```bash
./build.sh install
```

ビルドして `~/Applications/LLMUsageFloat.app` に入れます（古いものは置き換えられます）。ビルドだけ行いたい場合は `./build.sh`（`build/LLMUsageFloat.app` を生成）、デバッグビルドは `./build.sh debug` です。

起動は次のいずれかで行います。

- Finder で `~/Applications` を開いて `LLMUsageFloat` をダブルクリック
- Spotlight（⌘Space）で「LLMUsageFloat」を検索して起動
- ターミナルで `open ~/Applications/LLMUsageFloat.app`

起動すると Dock には出ず、**メニューバー右上にゲージアイコン**が出ます。ウィンドウは既定でデスクトップ（他のウィンドウの下）に表示されるので、他のアプリを開いていると隠れて見えません。macOS の「デスクトップを表示」（F11）か、メニューバーのアイコン → 表示モード → 常に最前面 で確認できます。

ログイン時に自動起動したい場合は、システム設定 → 一般 → ログイン項目と機能拡張 → 「+」で `~/Applications/LLMUsageFloat.app` を追加してください。

終了はメニューバーのアイコン → 終了です。

### キーチェーンの許可ダイアログについて

初回に **「LLMUsageFloat がキーチェーン "Claude Code-credentials" を使用しようとしています」**
というダイアログが出たら、**「常に許可」** を選んでください（Claude Code の OAuth トークンを読み取るためです。「許可」だと毎回聞かれます）。

アプリは取得した認証情報をメモリに保持するので、同じバイナリを使っている限り、ダイアログは起動ごとに最大 1 回です（トークンの期限切れなどで読み直すときを除く）。CLI が未ログインやトークン期限切れで取得に失敗した場合も 30 分は読み直さないので、ダイアログが 5 分おきに出続けることはありません（「今すぐ更新」を押したときだけ即座に読み直します。`claude auth login` の直後はこれを押してください）。
**再ビルドすると ad-hoc 署名が変わるため、再度聞かれます。**

開発で何度もビルドする場合は、自己署名証明書を作っておくと再ビルド後も許可が持続します。手順:

1. キーチェーンアクセス.app を開く
2. メニュー「キーチェーンアクセス」→「証明書アシスタント」→「証明書を作成…」を選ぶ
3. 名前を `LLMUsageFloat`、固有名のタイプを「自己署名ルート」、証明書のタイプを「コード署名」にして「作成」
4. 作成した証明書をキーチェーンアクセスでダブルクリック → 「信頼」を開き、「コード署名」を「常に信頼」にする（ここで管理者パスワードを 1 回聞かれます）。信頼していないと `security find-identity` に出てこず、ビルドは ad-hoc 署名のままになります

以後は `./build.sh` が自動でこの証明書で署名します（ビルド末尾に `署名: LLMUsageFloat (自己署名証明書)` と表示されます）。証明書で署名したアプリを最初に起動したときは改めて確認されるので、「常に許可」を選んでください。それ以降は再ビルドしても聞かれません。

## 仕組み

| サービス | 認証情報の取得元 | 使用量の取得元 |
| --- | --- | --- |
| Claude Code | macOS キーチェーン `Claude Code-credentials-<hash>`（Claude Code 2.1 以降。hash は設定ディレクトリの SHA-256 先頭 8 桁）→ `Claude Code-credentials` → `~/.claude/.credentials.json` の順に探索 | `GET https://api.anthropic.com/api/oauth/usage`（Claude Code の `/usage` が使うエンドポイント） |
| Codex | `~/.codex/auth.json`（`CODEX_HOME` 対応） | `GET https://chatgpt.com/backend-api/wham/usage`（Codex の `/status` が使うエンドポイント）。失敗時は `~/.codex/sessions/**/*.jsonl` に記録された直近の `rate_limits` にフォールバック |

- 5 時間 / 7 日間などの枠は、レスポンスの `limit_window_seconds` から判定します（モデル別の追加制限 `additional_rate_limits` も表示）。Claude 側で未知のキー（内部コードネーム）の枠が返ってきても表示しません。
- どちらも公式ドキュメント化されていないエンドポイントのため、仕様変更で表示できなくなる可能性があります。その場合はウィンドウ内にエラー理由を表示し、前回取得した値は保持します。
- Claude の usage エンドポイントはレート制限が厳しめなので、既定の更新間隔は 5 分です。
- トークンのリフレッシュは行いません（CLI 側の認証状態を壊さないため）。期限切れ表示が出たら、`claude` または `codex` を一度起動すると CLI がトークンを更新します。

## 常駐時の負荷

アイドル時の CPU は 0.0%、メモリは約 27 MB です（M1 Max / macOS 27 で実測）。常駐中の処理は次のとおりです。

1. 更新間隔（既定 5 分）ごとに HTTPS GET を 2 本（Claude / Codex）
2. 画面の「あと◯分」を更新するための、30 秒ごとの軽い再描画
3. 半透明背景のウィンドウ合成（GPU を使いますが、ごく軽微です）

- Codex の API が失敗したときだけ、`~/.codex/sessions` の新しい 5 ファイルの末尾を読みます。
- ネットワーク通信は更新時以外ありません。
- 更新間隔を 10〜30 分にすれば、さらに下がります。

## 構成

```
Package.swift                    SwiftPM マニフェスト（macOS 13+）
build.sh                         ビルドして build/LLMUsageFloat.app を生成
Resources/Info.plist             LSUIElement=true（Dock 非表示）
Sources/LLMUsageFloat/
  App.swift                      エントリポイント
  AppDelegate.swift              パネル・メニューバー・タイマー
  FloatingPanel.swift            半透明の NSPanel（表示モードでウィンドウレベルを切替）
  UsageView.swift                SwiftUI の表示部分
  UsageStore.swift               取得状態の管理
  ClaudeProvider.swift           Claude Code の認証情報読み取りと usage 取得
  CodexProvider.swift            Codex の認証情報読み取り・usage 取得・ログフォールバック
  Settings.swift                 不透明度・更新間隔などの永続化
  Models.swift                   データ型と JSON / 表示用ヘルパー
  Diagnostics.swift              --dump 診断モード
```

## トラブルシューティング

- **「Claude Code CLI が未ログインです」**: ターミナルで `claude auth login` を実行してください。`claude auth status` で確認できます。デスクトップアプリにログインしていても CLI は別です。
- **取得できない原因を調べたい**: `./build/LLMUsageFloat.app/Contents/MacOS/LLMUsageFloat --dump` を実行すると、認証情報の探索結果と使用量 API の生レスポンスをターミナルに表示します（トークンは表示しません）。
- **「Codex の認証情報が見つかりません」**: `codex login` を実行してください。API キーのみでのログインでは使用量は取得できません。
- **「レート制限中」**: Claude の usage エンドポイント側の制限です。更新間隔を長めにしてください。
- **ウィンドウが見当たらない / 画面外に行った**: メニューバーのゲージアイコン → 「ウィンドウを表示」、または「位置」→ 右上 などで画面の四隅に戻せます。
- **ウィンドウを動かしたい**: ボタン以外の場所（タイトルやバーの上）をドラッグします。「デスクトップに固定」中は他のウィンドウに覆われていると掴めないので、「デスクトップを表示」(F11) で露出させてからドラッグするか、「位置」メニューを使ってください。
- **「デスクトップに固定」だと他のアプリに隠れて見えない**: 他のウィンドウの下に表示される仕様です。macOS の「デスクトップを表示」（F11 / トラックパッドで親指と 3 本指を広げる）で表示するか、メニューバーのゲージアイコン → 「表示モード」で切り替えてください。
