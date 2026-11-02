import Foundation
@testable import iOSEngineerCodeCheck

extension Repository {
    /// テスト用の値。`id` と `fullName` だけ変えれば同一性の検証に足りる。
    static func fixture(
        id: Int = 1,
        fullName: String = "octocat/hello-world",
        language: String? = "Swift",
        stargazersCount: Int = 10,
        watchersCount: Int = 10,
        forksCount: Int = 2,
        openIssuesCount: Int = 1
    ) -> Repository {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "avatars.example.com"
        components.path = "/u/\(id)"
        return Repository(
            id: id,
            fullName: fullName,
            language: language,
            stargazersCount: stargazersCount,
            watchersCount: watchersCount,
            forksCount: forksCount,
            openIssuesCount: openIssuesCount,
            owner: Owner(avatarURL: components.url ?? URL(filePath: "/"))
        )
    }
}

extension SearchResponse {
    /// `totalCount` を省略すると items の件数（＝続きが無い応答）になる。続きがある応答は大きい値を渡す。
    static func fixture(_ items: [Repository], totalCount: Int? = nil) -> SearchResponse {
        SearchResponse(totalCount: totalCount ?? items.count, items: items)
    }
}

extension SearchResults {
    /// 重複の無い items をそのまま表示している状態。`nextPage` 省略時は続き無し。
    static func fixture(query: String, items: [Repository], nextPage: Int? = nil) -> SearchResults {
        SearchResults(query: query, items: items, nextPage: nextPage, receivedCount: items.count)
    }
}
