import Foundation
@testable import iOSEngineerCodeCheck

extension Repository {
    /// `fixture` の既定の最終更新日時（2023-11-14T22:13:20Z）。相対表記のテストは `now` をこれに対して決める。
    static let fixturePushedAt = Date(timeIntervalSince1970: 1_700_000_000)

    /// テスト用の値。`id` と `fullName` だけ変えれば同一性の検証に足りる。
    /// `htmlURL` を省略すると `https://github.com/<fullName>` になる（API の値と同じ規則）。
    static func fixture(
        id: Int = 1,
        fullName: String = "octocat/hello-world",
        language: String? = "Swift",
        stargazersCount: Int = 10,
        watchersCount: Int = 10,
        forksCount: Int = 2,
        openIssuesCount: Int = 1,
        description: String? = "A test repository",
        htmlURL: URL? = nil,
        pushedAt: Date? = fixturePushedAt,
        isArchived: Bool = false
    ) -> Repository {
        var avatar = URLComponents()
        avatar.scheme = "https"
        avatar.host = "avatars.example.com"
        avatar.path = "/u/\(id)"
        var page = URLComponents()
        page.scheme = "https"
        page.host = "github.com"
        page.path = "/\(fullName)"
        return Repository(
            id: id,
            fullName: fullName,
            language: language,
            stargazersCount: stargazersCount,
            watchersCount: watchersCount,
            forksCount: forksCount,
            openIssuesCount: openIssuesCount,
            owner: Owner(avatarURL: avatar.url ?? URL(filePath: "/")),
            description: description,
            htmlURL: htmlURL ?? page.url,
            pushedAt: pushedAt,
            isArchived: isArchived
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
