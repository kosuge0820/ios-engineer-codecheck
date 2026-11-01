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

    /// - Parameter query: 初期の入力値。初期実装はプレースホルダ文字列を実値として入れていたので、本番ではそれを渡す（初級-02 で見直す）。
    init(searcher: any RepositorySearching, query: String = "") {
        self.searcher = searcher
        self.query = query
    }

    /// 現在の `query` で検索する。空白だけなら何もしない。進行中の検索はキャンセルされ、その応答は捨てられる。
    func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        let current = beginGeneration()
        state = .loading

        let task = Task { [searcher] () -> Result<SearchResponse, GitHubSearchError> in
            do throws(GitHubSearchError) {
                return .success(try await searcher.search(query: trimmedQuery))
            } catch {
                return .failure(error)
            }
        }
        searchTask = task
        let outcome = await task.value

        guard current == generation else {
            Log.search.debug("世代 \(current) の応答を破棄（現在 \(self.generation)）")
            return
        }
        searchTask = nil
        switch outcome {
        case .success(let response):
            state = response.items.isEmpty ? .empty : .loaded(response.items)
        case .failure(let error):
            Log.search.error("検索に失敗: \(String(describing: error))")
            state = .failed(error)
        }
    }

    /// 進行中の検索をキャンセルし、結果を捨てて初期状態に戻す。
    func reset() {
        _ = beginGeneration()
        state = .idle
    }

    /// 進行中の検索を取り消して世代を進め、新しい世代番号を返す。
    private func beginGeneration() -> Int {
        searchTask?.cancel()
        searchTask = nil
        generation += 1
        return generation
    }
}
