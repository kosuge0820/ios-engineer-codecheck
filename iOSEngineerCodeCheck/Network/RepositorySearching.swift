import Foundation

/// 1 回の検索要求。`page` は 1 始まり。
struct SearchRequest: Hashable, Sendable {
    let query: String
    let page: Int
}

/// リポジトリ検索の通信境界。本番は `GitHubSearchClient`、テストはスタブで差し替える。
protocol RepositorySearching: Sendable {
    func search(_ request: SearchRequest) async throws(GitHubSearchError) -> SearchResponse
}

/// 検索で起こり得る失敗。UI は種類ごとに扱いを変えられる。
enum GitHubSearchError: Error, Equatable, Sendable {
    /// 403 / 429。未認証の Search API は 10 リクエスト/分。
    case rateLimited
    /// 422。GitHub が返したメッセージを保持する。
    case invalidQuery(message: String)
    /// 上記以外の 2xx でないステータス。
    case unexpectedStatus(Int)
    /// 応答本文を `SearchResponse` として解釈できない（理由を保持）。
    case invalidResponse(String)
    /// 接続できない・タイムアウトなど `URLSession` 由来の失敗。
    case network(URLError)
}

extension GitHubSearchError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .rateLimited:
            "リクエスト上限に達しました。しばらく待ってから再試行してください。"
        case .invalidQuery(let message):
            "検索条件が受け付けられませんでした: \(message)"
        case .unexpectedStatus(let status):
            "サーバーからエラーが返されました (HTTP \(status))。"
        case .invalidResponse:
            "応答を解釈できませんでした。"
        case .network(let error):
            "通信に失敗しました: \(error.localizedDescription)"
        }
    }
}
