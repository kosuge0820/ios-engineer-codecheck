# iOSEngineerCodeCheck 開発ガイド

GitHub リポジトリを検索し、ブックマークできる iOS アプリ。人間とコーディングエージェントの双方がこのファイルを読んで作業する前提で書いている。仕様は `README.md` の「アプリ仕様」が正。

## 環境と制約

- Xcode 27 / Swift 6 言語モード（strict concurrency 有効）/ iOS 27.0 以上 / iPhone・iPad
- 署名は不要。シミュレータ向けビルドは `CODE_SIGNING_ALLOWED=NO` で行う
- GitHub Search API（`/search/repositories`）は未認証で 10 リクエスト/分。実 API に依存するテストは書かない
- サードパーティ依存は原則なし。追加する場合は解決するリスクと代替案を PR に書く

## 実行方法

ローカルと CI は同じ入り口を使う。

```bash
make build   # シミュレータ向けビルド
make test    # 単体テスト（xcresult を build/ に出力）
make lint    # 静的解析（導入している場合）
```

シミュレータ名と OS は `Makefile` 先頭の変数で変更できる。失敗時は `xcresult` を Xcode で開くか、`xcrun xcresulttool` で失敗テストを確認する。

## 構成

| 責務 | 置き場所 | 備考 |
| --- | --- | --- |
| API モデル | `Model/` | `Repository` / `SearchResponse`。GitHub の数値 `id` を同一性に使う。UI 状態は持たせない |
| 通信 | `Network/` | `RepositorySearching` protocol と `URLSession` 実装 `GitHubSearchClient`。HTTP ステータスを検証し、エラーは `GitHubSearchError` で表す |
| 永続化 | `Persistence/` | `BookmarkStoring` protocol と `UserDefaultsBookmarkStorage`。保存形式は API モデルと分離した専用型（`BookmarkRecordV1`） |
| 画面状態 | `Feature/Search/SearchModel.swift`, `Feature/Bookmark/BookmarkStore.swift` | `@Observable @MainActor` な型が検索状態・ブックマーク状態を所有し、`.environment()` で注入する |
| View | `Feature/`（`RootView`, `Search/`, `Bookmark/`, `Detail/`, `Shared/`） | 状態を描画するだけ。通信・永続化を直接呼ばない |
| ログ | `Support/Log.swift` | `os.Logger` を `network` / `persistence` / `search` のカテゴリで用意 |
| 単体テスト | `iOSEngineerCodeCheckTests/`（Swift Testing） | `Fixtures/` に JSON、`Support/` にスタブ（`StubRepositorySearcher`, `StubURLProtocol`, `InMemoryBookmarkStorage`, `TemporaryDefaults`） |

Xcode プロジェクトはフォルダ同期グループ（file-system-synchronized group）なので、ディレクトリにファイルを置けばターゲットに入る。`project.pbxproj` にファイルを手で列挙しない。

（ディレクトリ名は目安。変更したらこの表を更新する）

## 設計上の約束

- 検索状態は列挙型で明示する（初期 / 読み込み中 / 結果あり / 0 件 / 失敗 / 追加読み込み中）。UI はこれを区別して表示する
- 進行中の検索 `Task` は保持してキャンセルし、応答到着時に世代を照合する。古い応答で新しい結果を上書きしない
- 強制アンラップ、`try?`、空の `catch`、`@unchecked Sendable`、`nonisolated(unsafe)` を増やさない。失敗は `os.Logger` に記録し、必要なら UI に伝える
- ブックマークは Search / Bookmark どちらの画面からも同じストアを通して更新し、即座に保存する
- 永続化キーは `bookmarks.v1`。旧キー `data` の形式は一度だけ読み込んで移行する。保存形式を変えるときはキーを上げ、移行処理とテストを追加する。利用者のデータを黙って消さない

## テストの約束

- テストは実ネットワークと端末の `UserDefaults` に触れない。通信はスタブ、永続化は `UserDefaults(suiteName:)` で隔離し `tearDown` で破棄する
- スタブ通信クライアントは応答の遅延・順序・エラーを制御できる
- バグ修正には「修正前に失敗し、修正後に通る」テストを付ける
- フィクスチャ JSON は `Tests/Fixtures/` に置く（成功 / 0 件 / 403 / 422 / `items` 欠落 / `language: null`）

## 作業の流れ

- 作業ブランチは `main` から切る。1 PR には 1 Issue の変更だけを含める
- PR 本文には対象 Issue、変更理由、検証（ビルド・テスト・手動確認した仕様番号）、対象外とした範囲を書く
- コミットは小さく、メッセージは「何を・なぜ」
- 変更前に `make test` が通ることを確認し、変更後も通してから PR を出す

## コーディングエージェントへの補足

- 推測で「直った」と言わず、再現 → テスト → 修正 → 検証の順で進める
- 設計の分岐点では選択肢と推奨を提示し、承認を待ってから実装する
- PR 作成、マージ、Issue コメントは人間が行う。草稿の提示まででよい
