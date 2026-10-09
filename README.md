# LLM Usage Float

Claude Code と Codex の現在の使用量（レート制限の消費率）と、そのリセット日時を
macOS のデスクトップ上に **半透明のフローティングウィンドウ** で常時表示する小さなアプリです。

```
┌──────────────────────────────┐
│ ● Claude Code        Max     │
│  5時間            42% 使用   │
│  ████████░░░░░░░░░░░░        │
│  リセット 10/9 18:30  あと2時間13分 │
│  7日間            17% 使用   │
│  ███░░░░░░░░░░░░░░░░░        │
│  リセット 10/14 09:00 あと4日14時間 │
│ ─────────────────────────── │
│ ● Codex              Plus    │
│  5時間            13% 使用   │
│  7日間            61% 使用   │
│ ↻ 更新 12:34              ⚙ │
└──────────────────────────────┘
```

- 常に最前面・全スペースで表示、ドラッグで自由に移動（位置は記憶されます）
- 不透明度（50〜100%）と更新間隔（1〜30分）を右クリック / メニューバーから変更
- メニューバーにも「C 42% · X 13%」のように 5 時間枠の使用率を表示
- Dock にはアイコンを出さないメニューバー常駐アプリ

## 動作要件

- macOS 13 Ventura 以降
- Xcode Command Line Tools（`xcode-select --install`）または Xcode
- Claude Code にログイン済み（ターミナルで `claude` → `/login`）
- Codex CLI に ChatGPT アカウントでログイン済み（`codex login`）

## ビルドと起動

```bash
./build.sh
open build/LLMUsageFloat.app
```

初回起動時に **「LLMUsageFloat がキーチェーン "Claude Code-credentials" を使用しようとしています」**
というダイアログが出るので「常に許可」を選んでください（Claude Code の OAuth トークンを読み取るためです）。
ad-hoc 署名のため、再ビルドすると再度確認を求められることがあります。

ログイン項目に追加したい場合は「システム設定 → 一般 → ログイン項目」に `LLMUsageFloat.app` を追加してください。

## 仕組み

| サービス | 認証情報の取得元 | 使用量の取得元 |
| --- | --- | --- |
| Claude Code | macOS キーチェーン `Claude Code-credentials`（なければ `~/.claude/.credentials.json`） | `GET https://api.anthropic.com/api/oauth/usage`（Claude Code の `/usage` が使うエンドポイント） |
| Codex | `~/.codex/auth.json`（`CODEX_HOME` 対応） | `GET https://chatgpt.com/backend-api/wham/usage`（Codex の `/status` が使うエンドポイント）。失敗時は `~/.codex/sessions/**/*.jsonl` に記録された直近の `rate_limits` にフォールバック |

- 5 時間 / 7 日間などの枠は、レスポンスの `limit_window_seconds` から判定します（モデル別の追加制限 `additional_rate_limits` も表示）。
- どちらも公式ドキュメント化されていないエンドポイントのため、仕様変更で表示できなくなる可能性があります。その場合はウィンドウ内にエラー理由を表示し、前回取得した値は保持します。
- Claude の usage エンドポイントはレート制限が厳しめなので、既定の更新間隔は 5 分です。
- トークンのリフレッシュは行いません（CLI 側の認証状態を壊さないため）。期限切れ表示が出たら、`claude` または `codex` を一度起動すると CLI がトークンを更新します。

## 構成

```
Package.swift                    SwiftPM マニフェスト（macOS 13+）
build.sh                         ビルドして build/LLMUsageFloat.app を生成
Resources/Info.plist             LSUIElement=true（Dock 非表示）
Sources/LLMUsageFloat/
  App.swift                      エントリポイント
  AppDelegate.swift              パネル・メニューバー・タイマー
  FloatingPanel.swift            半透明・最前面の NSPanel
  UsageView.swift                SwiftUI の表示部分
  UsageStore.swift               取得状態の管理
  ClaudeProvider.swift           Claude Code の認証情報読み取りと usage 取得
  CodexProvider.swift            Codex の認証情報読み取り・usage 取得・ログフォールバック
  Settings.swift                 不透明度・更新間隔などの永続化
  Models.swift                   データ型と JSON / 表示用ヘルパー
```

## トラブルシューティング

- **「Claude Code の認証情報が見つかりません」**: `claude` を起動して `/login` してください。
- **「Codex の認証情報が見つかりません」**: `codex login` を実行してください。API キーのみでのログインでは使用量は取得できません。
- **「レート制限中」**: Claude の usage エンドポイント側の制限です。更新間隔を長めにしてください。
- **ウィンドウが見当たらない**: メニューバーのゲージアイコン → 「ウィンドウを表示」。
