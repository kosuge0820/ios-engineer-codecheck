import Foundation
import Observation

/// 検索画面の状態。UI はこれを区別して描画する。
enum SearchState: Equatable, Sendable {
    /// まだ検索していない
    case idle
    /// 最初のページを待っている。表示中の結果は無い
    case loading
    /// 1 件以上の結果がある
    case loaded(SearchResults)
    /// 表示中の結果を保ったまま次のページを待っている
    case loadingMore(SearchResults)
    /// 追加読み込みに失敗した。表示中の結果は保持し、再試行できる
    case loadMoreFailed(SearchResults, GitHubSearchError)
    /// 検索したが 0 件
    case empty
    /// 最初のページの取得に失敗した
    case failed(GitHubSearchError)

    /// 表示している結果（結果を持つ 3 状態で共通）。
    var results: SearchResults? {
        switch self {
        case .loaded(let results), .loadingMore(let results), .loadMoreFailed(let results, _):
            results
        case .idle, .loading, .empty, .failed:
            nil
        }
    }
}

/// 1 回の検索セッションで表示している結果。`items` は GitHub の `id` で重複排除済み。
struct SearchResults: Equatable, Sendable {
    /// GitHub Search API が返す件数の上限。これを超えるページは要求しない。
    static let resultCap = 1000

    /// トリム済みの検索語。追加読み込みはテキスト欄の現在値ではなくこれを使う。
    let query: String
    private(set) var items: [Repository]
    /// 次に要求するページ。`nil` なら続きは無い。
    private(set) var nextPage: Int?
    /// 重複排除前に受け取った件数。`totalCount` との比較に使う。
    private(set) var receivedCount: Int

    init(query: String, items: [Repository] = [], nextPage: Int? = nil, receivedCount: Int = 0) {
        self.query = query
        self.items = items
        self.nextPage = nextPage
        self.receivedCount = receivedCount
    }

    /// `page` 番目の応答を取り込む。既に表示している `id` は追加しない（先に表示した方を残す）。
    ///
    /// 続きの有無は、応答が空か、受け取った件数が `totalCount`（上限 1000）に達したかで決める。
    func appending(_ response: SearchResponse, page: Int) -> SearchResults {
        var seen = Set(items.map(\.id))
        var merged = items
        for repository in response.items where seen.insert(repository.id).inserted {
            merged.append(repository)
        }
        let received = receivedCount + response.items.count
        let reachedEnd = response.items.isEmpty || received >= min(response.totalCount, Self.resultCap)
        return SearchResults(
            query: query, items: merged, nextPage: reachedEnd ? nil : page + 1, receivedCount: received
        )
    }
}

/// 検索の入力と結果を所有する。通信は `RepositorySearching` に委ねる。
///
/// 進行中の検索 `Task` を保持し、新しい検索や `reset()` でキャンセルする。
/// 応答は世代番号で照合し、古い検索の応答で新しい状態を上書きしない。
@Observable
@MainActor
final class SearchModel {
    var query = ""
    private(set) var state: SearchState = .idle

    private let searcher: any RepositorySearching
    private var searchTask: Task<Result<SearchResponse, GitHubSearchError>, Never>?
    /// 検索を開始・破棄するたびに進める。応答到着時にこの値と一致しなければ捨てる。
    private var generation = 0

    init(searcher: any RepositorySearching) {
        self.searcher = searcher
    }

    /// 現在の `query` で検索する。空白だけなら何もしない。進行中の検索はキャンセルされ、その応答は捨てられる。
    func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        let current = beginGeneration()
        state = .loading

        let outcome = await perform(SearchRequest(query: trimmedQuery, page: 1))

        guard current == generation else {
            Log.search.debug("世代 \(current) の応答を破棄（現在 \(self.generation)）")
            return
        }
        searchTask = nil
        switch outcome {
        case .success(let response):
            let results = SearchResults(query: trimmedQuery).appending(response, page: 1)
            state = results.items.isEmpty ? .empty : .loaded(results)
        case .failure(let error):
            Log.search.error("検索に失敗: \(String(describing: error), privacy: .public)")
            state = .failed(error)
        }
    }

    /// 表示中の結果の続き（次のページ）を読み込む。
    ///
    /// 進行中の通信があるとき、続きが無いとき、結果を表示していないときは何もしない。
    /// 追加読み込みは同じ検索セッションなので世代は進めない。失敗しても表示中の結果は保ち、再度呼べば同じページを再要求する。
    func loadMore() async {
        switch state {
        case .loaded(let results), .loadMoreFailed(let results, _):
            guard searchTask == nil, let page = results.nextPage else { return }
            await loadPage(page, appendingTo: results)
        case .idle, .loading, .loadingMore, .empty, .failed:
            return
        }
    }

    private func loadPage(_ page: Int, appendingTo results: SearchResults) async {
        let current = generation
        state = .loadingMore(results)

        let outcome = await perform(SearchRequest(query: results.query, page: page))

        // 世代が進んでいれば別の検索セッション。状態が変わっていれば reset 等で捨てられている
        guard current == generation, case .loadingMore = state else {
            Log.search.debug("世代 \(current) のページ \(page) の応答を破棄（現在 \(self.generation)）")
            return
        }
        searchTask = nil
        switch outcome {
        case .success(let response):
            state = .loaded(results.appending(response, page: page))
        case .failure(let error):
            Log.search.error("ページ \(page) の追加読み込みに失敗: \(String(describing: error), privacy: .public)")
            state = .loadMoreFailed(results, error)
        }
    }

    /// 進行中の検索をキャンセルし、結果を捨てて初期状態に戻す。
    func reset() {
        _ = beginGeneration()
        state = .idle
    }

    /// 要求を 1 本の `Task` として `searchTask` に保持し、完了まで待つ。
    /// 呼び出し側は世代を照合してから結果を取り込み、`searchTask` を解放する。
    private func perform(_ request: SearchRequest) async -> Result<SearchResponse, GitHubSearchError> {
        let task = Task { [searcher] () -> Result<SearchResponse, GitHubSearchError> in
            do throws(GitHubSearchError) {
                return .success(try await searcher.search(request))
            } catch {
                return .failure(error)
            }
        }
        searchTask = task
        return await task.value
    }

    /// 進行中の検索を取り消して世代を進め、新しい世代番号を返す。
    private func beginGeneration() -> Int {
        searchTask?.cancel()
        searchTask = nil
        generation += 1
        return generation
    }
}
