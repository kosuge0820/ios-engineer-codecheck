import Foundation
import Observation

/// 検索画面の状態。UI はこれを区別して描画する。
enum SearchState: Equatable, Sendable {
    /// まだ検索していない
    case idle
    /// 検索中
    case loading
    /// 1 件以上の結果がある
    case loaded([Repository])
    /// 検索したが 0 件
    case empty
    /// 検索に失敗した
    case failed(GitHubSearchError)
}

/// 検索の入力と結果を所有する。通信は `RepositorySearching` に委ねる。
@Observable
@MainActor
final class SearchModel {
    var query = ""
    private(set) var state: SearchState = .idle

    private let searcher: any RepositorySearching

    /// - Parameter query: 初期の入力値。初期実装はプレースホルダ文字列を実値として入れていたので、本番ではそれを渡す（初級-02 で見直す）。
    init(searcher: any RepositorySearching, query: String = "") {
        self.searcher = searcher
        self.query = query
    }

    /// 現在の `query` で検索する。空白だけなら何もしない。
    func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        state = .loading
        do {
            let response = try await searcher.search(query: trimmedQuery)
            state = response.items.isEmpty ? .empty : .loaded(response.items)
        } catch {
            Log.search.error("検索に失敗: \(String(describing: error))")
            state = .failed(error)
        }
    }

    /// 結果を捨てて初期状態に戻す。
    func reset() {
        state = .idle
    }
}
