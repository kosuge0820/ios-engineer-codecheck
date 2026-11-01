import Foundation

/// GitHub Search API が返すリポジトリ。同一性は GitHub の数値 `id` で決まる。UI 状態（ブックマーク済みかどうか等）は持たない。
struct Repository: Decodable, Hashable, Identifiable, Sendable {
    struct Owner: Decodable, Hashable, Sendable {
        let avatarURL: URL

        private enum CodingKeys: String, CodingKey {
            case avatarURL = "avatar_url"
        }
    }

    let id: Int
    let fullName: String
    let language: String?
    let stargazersCount: Int
    let watchersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let owner: Owner

    private enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case language
        case stargazersCount = "stargazers_count"
        case watchersCount = "watchers_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
        case owner
    }
}

extension Repository {
    /// 旧保存形式（GitHub の id を持たない）から移行した項目に割り当てる暫定 id。
    ///
    /// `fullName` から決定論的に計算した負の値。GitHub の id は正なので実データと衝突しない。
    /// 暫定 id を持つ項目は `fullName` でも照合される（`BookmarkStore` 参照）。
    static func provisionalID(fullName: String) -> Int {
        // FNV-1a 64bit
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in fullName.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        let magnitude = Int(truncatingIfNeeded: hash & 0x7fff_ffff_ffff_ffff)
        return -max(magnitude, 1)
    }

    var hasProvisionalID: Bool { id < 0 }
}

/// `/search/repositories` の応答。
struct SearchResponse: Decodable, Sendable {
    let totalCount: Int
    let items: [Repository]

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case items
    }
}
