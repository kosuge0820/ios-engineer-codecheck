# iOSEngineerCodeCheck 開発ガイド

GitHub リポジトリを検索し、ブックマークできる iOS アプリ。人間とコーディングエージェントの双方がこのファイルを読んで作業する前提で書いている。仕様は `README.md` の「アプリ仕様」が正。

## 環境と前提

- Xcode 27.2 / Swift 6 言語モード（strict concurrency 有効）/ iOS 27.0 以上 / iPhone・iPad
- 署名は不要。シミュレータ向けにだけビルドする（`CODE_SIGNING_ALLOWED=NO`）
- 追加インストールは不要。静的解析は Xcode 同梱の `swift-format`（`xcrun swift-format`）、スクリプトは macOS 同梱の `bash` と `python3` だけを使う
- 既定のシミュレータは `iPhone 17`（OS は `latest`）。無い場合は `xcrun simctl list devices available` で確認し、後述の変数で差し替える
- GitHub Search API（`/search/repositories`）は未認証で 10 リクエスト/分。テストは実 API に触れない（スタブとフィクスチャで完結する）ので、トークンや秘密情報は不要
- サードパーティ依存は原則なし。追加する場合は解決するリスクと代替案を PR に書く

## セットアップと実行方法

入り口は `Makefile`。ローカルと CI（`.github/workflows/ci.yml`）は同じターゲットを呼ぶ。クリーンな環境では次の順で確認する。

```bash
git clone <このリポジトリ> && cd ios-engineer-codecheck
make lint && make build && make test
```

| ターゲット | 内容 | 出力 |
| --- | --- | --- |
| `make`（`make help`） | ターゲット一覧と現在の変数値 | 標準出力 |
| `make lint` | `swift-format lint --strict`（設定は `.swift-format`） | 指摘があれば `ファイル:行:列: error: [ルール名]` で非 0 |
| `make build` | シミュレータ向けビルド。Swift の警告はエラー扱い | `build/build.log` |
| `make test` | 単体テスト（テストプラン `iOSEngineerCodeCheck`）。終了後に要約を出す | `build/test.xcresult`, `build/test.log` |
| `make test-repeat` | `SearchModelTests` を 20 回繰り返し、非同期競合の flaky を探す | `build/test-repeat.xcresult`, `build/test-repeat.log` |
| `make ui-test` | UI テスト（テストプラン `iOSEngineerCodeCheckUI`）。`make test` では走らない | `build/ui-test.xcresult`, `build/ui-test.log` |
| `make report` | 直近の `build/test.xcresult` の要約を再表示 | 標準出力 |
| `make format` | `swift-format` で整形（ローカル用。CI では実行しない） | ソースを書き換える |
| `make log` | 起動中シミュレータのアプリログを流す（下記「ログ」） | 標準出力 |
| `make clean` | `build/` を削除 | — |

変数は引数または環境変数で上書きできる。絶対パスや個人環境の値は `Makefile` に書かない。

```bash
make test SIMULATOR_NAME="iPhone 17 Pro" SIMULATOR_OS=27.0   # 宛先を変える
make test DESTINATION="platform=iOS Simulator,id=<UDID>"      # UDID で指定する
make test-repeat REPEAT_COUNT=50                              # 繰り返し回数を変える
make test BUILD_DIR=/path/to/out                              # 出力先を変える
```

Xcode で開く場合は共有スキーム `iOSEngineerCodeCheck` を使う。テストプランは `iOSEngineerCodeCheck.xctestplan`（既定、単体テストのみ）と `iOSEngineerCodeCheckUI.xctestplan`（UI テスト）の 2 つで、⌘U は既定プランを実行する。

## 成否の判断と診断

- 成否は終了コードで判断する。`make build` / `make test` / `make lint` はいずれも失敗時に非 0 で終わる
- `make test` と `make test-repeat` は結果に関わらず `scripts/summarize-xcresult.sh` を実行し、「合計 / 成功 / 失敗 / スキップ」と、失敗したテストの名前・`ファイル:行`・メッセージを標準出力に出す。結果が Passed 以外（ランナーのクラッシュ等で失敗件数が 0 でも）や、テストが 1 件も実行されなかった場合（`-only-testing` の対象が消えた等）も非 0 で終わる。`GITHUB_STEP_SUMMARY` が設定されていれば同じ内容を Markdown でも書き出す（CI の Summary タブ）
- 詳しく調べるときは `build/test.xcresult` を Xcode で開くか、次を実行する

  ```bash
  xcrun xcresulttool get test-results tests --path build/test.xcresult
  ```

- `xcodebuild` の生ログは `build/<ターゲット名>.log` に残る。xcresult が無い（テスト起動前にビルドで落ちた等）ときはここを見る
- CI では `build/*.xcresult` と `build/*.log` を成否に関わらずアーティファクト `test-results` として 14 日間保存する
- シミュレータが起動しない・宛先が見つからないときは `xcrun simctl list devices available` で名前と OS を確認し、`SIMULATOR_NAME` / `SIMULATOR_OS` を上書きする

### ログ

- アプリは `os.Logger`（`Support/Log.swift`）に記録する。サブシステムはバンドル ID（`jp.yumemi.iOSEngineerCodeCheck`）、カテゴリは `network` / `persistence` / `search`
- 起動中のシミュレータのログは `make log` で流せる（`log stream --predicate 'subsystem == "jp.yumemi.iOSEngineerCodeCheck"'`）。Console.app でも同じサブシステムで絞り込める
- 失敗理由やキー名などの診断に必要な値は `privacy: .public` を付けて伏せられないようにする。検索語・URL など利用者由来の値は既定（private）のまま残す

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
| UI テスト | `iOSEngineerCodeCheckUITests/` | 既定では実行しない（後述） |
| 入り口・CI | `Makefile`, `scripts/summarize-xcresult.sh`, `.github/workflows/ci.yml`, `*.xctestplan`, `.swift-format` | ローカルと CI で同じコマンド |

Xcode プロジェクトはフォルダ同期グループ（file-system-synchronized group）なので、ディレクトリにファイルを置けばターゲットに入る。`project.pbxproj` にファイルを手で列挙しない。

（ディレクトリ名は目安。変更したらこの表を更新する）

## 設計上の約束

- 検索状態は列挙型で明示する（初期 / 読み込み中 / 結果あり / 0 件 / 失敗）。状態を増やすときは列挙型にケースを足し、UI はそれぞれを区別して表示する
- 進行中の検索 `Task` は保持してキャンセルし、応答到着時に世代を照合する。古い応答で新しい結果を上書きしない
- 強制アンラップ、`try!` / `try?`、空の `catch`、`@unchecked Sendable`、`nonisolated(unsafe)` を増やさない。強制アンラップと `try!` は `make lint` が機械的に検出する。失敗は `os.Logger` に記録し、必要なら UI に伝える
- Swift の警告は 0 件を維持する（`make build` と CI は警告をエラーにする）
- ブックマークは Search / Bookmark どちらの画面からも同じストアを通して更新し、即座に保存する
- 永続化キーは `bookmarks.v1`。旧キー `data` の形式は一度だけ読み込んで移行する。保存形式を変えるときはキーを上げ、移行処理とテストを追加する。利用者のデータを黙って消さない。解釈できないデータは退避キー（`<キー>.unreadable`）へ複製してから例外にする

## テストの約束

- テストは実ネットワークと端末の `UserDefaults` に触れない。通信はスタブ、永続化は `UserDefaults(suiteName:)` で隔離し、テスト終了時に `removePersistentDomain` で破棄する（`TemporaryDefaults` の `deinit`）
- スタブ通信クライアント（`StubRepositorySearcher`）は応答の遅延・順序・エラーを制御でき、待機には上限がある（ハングではなく失敗になる）
- バグ修正には「修正前に失敗し、修正後に通る」テストを付ける
- テストプランは実行順をランダム化し、並列実行する。順序に依存するテストは書かない
- フィクスチャ JSON は `iOSEngineerCodeCheckTests/Fixtures/` に置き、`Fixture.data(_:)` で読む

### このプロジェクト固有のリスクと対応する検証

| リスク | 困ること | 検証 | 入り口 |
| --- | --- | --- | --- |
| 非同期競合（連続検索・リセット・キャンセル） | 古い応答が新しい結果を上書きする、空欄なのに結果が残る | `SearchModelTests` がスタブの `hold` / `resume` で応答順を制御して検証。実行順ランダム化。`make test-repeat` で同じテストを繰り返し flaky を検出 | `make test`, `make test-repeat` |
| API 依存（レート制限、応答形式の変更） | テストが実 API に当たって不安定になる、形式変更に気付けない | `StubURLProtocol` と `Fixtures/search-*.json`, `error-*.json` で通信を遮断。`GitHubSearchClientTests` が成功 / 0 件 / 403 / 422 / 5xx / 壊れた本文 / 未接続 / クエリ符号化を検証 | `make test` |
| 永続化互換性（`bookmarks.v1`、旧キー `data`） | アプリ更新で利用者のブックマークが消える・復活する | `UserDefaultsBookmarkStorageTests` が往復、旧形式の移行、壊れたデータの退避を検証。`Fixtures/bookmarks-v1.json` は出荷済みの v1 形式を固定したもので、`BookmarkRecordV1` を変えると `decodesFrozenV1Fixture` が落ちる | `make test` |
| Swift 6 strict concurrency の退行 | 警告が積もり、実行時の競合が隠れる | `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` | `make build` |
| 禁止パターン・スタイルの揺れ | レビューが本質以外に時間を使う | `swift-format lint --strict`（`NeverForceUnwrap`, `NeverUseForceTry`, `NeverUseImplicitlyUnwrappedOptionals` 等） | `make lint` |
| UI の退行（ダークモード、文字サイズ、タップ領域） | 自動検出できない | 対象外。PR の検証欄に手動確認した内容を書く | — |

### フィクスチャの更新

- API 応答のフィクスチャ（`search-*.json`, `error-*.json`）は固定点として扱う。`RepositoryDecodingTests` や `GitHubSearchClientTests` は件数・リポジトリ名・スター数などの値そのものを検証しているので、コミット済みの JSON を上書きするとテストが落ちる
- 採取し直すときは別ファイルに出して差分を確認し、フィクスチャとテストの期待値を同じコミットで更新する。個人を特定できる値を含めない（GitHub 公開リポジトリのメタデータのみ）

  ```bash
  curl -s -H "Accept: application/vnd.github+json" \
    "https://api.github.com/search/repositories?q=swift&per_page=2" > build/search-success.new.json
  diff <(python3 -m json.tool iOSEngineerCodeCheckTests/Fixtures/search-success.json) <(python3 -m json.tool build/search-success.new.json)
  ```

- `bookmarks-v1.json` は保存形式の固定点なので更新しない。形式を変えるときは `bookmarks.v2` 用のフィクスチャとテストを追加し、v1 → v2 の移行テストで旧フィクスチャを読み続ける

### UI テストを書くとき

- UI テストターゲットは `iOSEngineerCodeCheckUI.xctestplan` にだけ入っていて、`make test` と CI では実行しない（起動コストと flaky を避けるため）
- 追加した UI テストは `make ui-test` で実行する。CI で回したい場合は `.github/workflows/ci.yml` に `make ui-test` のステップを足す

## CI

- `.github/workflows/ci.yml` が `main` への pull request と push で動く。手順は `make lint` → `make build` → `make test` → `make test-repeat`。秘密情報は使わない
- ランナーは `runs-on: xcode-27`（GitHub ホスト、公開プレビューのイメージ）。`macos-latest` は macOS 26 / Xcode 26 系で iOS 27 SDK が無いためビルドできない。`DEVELOPER_DIR=/Applications/Xcode_27.2.app` でローカルと同じ Xcode 27.2 に固定している（イメージ側は Release Candidate ビルドの場合がある）
- CI のテストはワークフロー内で新規作成したシミュレータ（`xcrun simctl create`、UDID を `DESTINATION` に渡す）で実行する。イメージ既定の `iPhone 17` は Apple Watch とペアリングされており、並列テストのクローンに失敗するため
- 失敗したときは、ジョブの Summary タブ（テスト件数と失敗一覧）→ 該当ステップのログ → アーティファクト `test-results` の `*.xcresult` を Xcode で開く、の順に見る
- 同じブランチへの連続 push は古い実行を取り消す（`concurrency`）

## 作業の流れ

- 作業ブランチは `main` から切る。1 PR には 1 つの Issue の変更だけを含める
- 変更前に `make test` が通ることを確認し、変更後は `make lint && make build && make test` を通してから PR を出す
- PR 本文には対象 Issue、変更理由、検証（実行したコマンドと結果、手動確認した仕様番号）、対象外とした範囲を書く
- コミットは小さく、メッセージは「何を・なぜ」
- 推測で「直った」と言わない。再現 → 失敗するテスト → 修正 → 検証の順で進め、設計の分岐点では選択肢と推奨を示して合意してから実装する
