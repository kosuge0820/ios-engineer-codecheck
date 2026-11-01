import Foundation

/// `UserDefaults` にブックマークを保存する。
///
/// - 保存形式は API モデルと切り離した `BookmarkRecordV1`（キー `bookmarks.v1`）。
/// - 旧キー `data`（`id` を持たない形式）は一度だけ読み込んで v1 に移行し、成功したら旧キーを消す。
/// - 解釈できないデータは例外にし、黙って消さない。
struct UserDefaultsBookmarkStorage: BookmarkStoring {
    static let currentKey = "bookmarks.v1"
    static let legacyKey = "data"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> [Repository] {
        if let data = defaults.data(forKey: Self.currentKey) {
            return try decode([BookmarkRecordV1].self, from: data, key: Self.currentKey).map(\.repository)
        }

        guard let legacyData = defaults.data(forKey: Self.legacyKey) else {
            return []
        }
        let migrated = try decode([LegacyBookmarkRecord].self, from: legacyData, key: Self.legacyKey)
            .map { try $0.repository() }
        try save(migrated)
        defaults.removeObject(forKey: Self.legacyKey)
        Log.persistence.notice("旧キー \(Self.legacyKey) から \(migrated.count) 件を \(Self.currentKey) へ移行した")
        return migrated
    }

    func save(_ repositories: [Repository]) throws {
        let records = repositories.map(BookmarkRecordV1.init)
        do {
            defaults.set(try JSONEncoder().encode(records), forKey: Self.currentKey)
        } catch {
            Log.persistence.error("ブックマークのエンコードに失敗: \(error)")
            throw BookmarkStorageError.writeFailed(key: Self.currentKey, reason: String(describing: error))
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, key: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Log.persistence.error("キー \(key) の保存データを解釈できない: \(error)")
            throw BookmarkStorageError.corruptedData(key: key, reason: String(describing: error))
        }
    }
}

/// `bookmarks.v1` の保存形式。フィールドを変えるときはキーを上げて移行処理を追加する。
private struct BookmarkRecordV1: Codable {
    let id: Int
    let fullName: String
    let language: String?
    let stargazersCount: Int
    let watchersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let avatarURL: URL

    init(_ repository: Repository) {
        id = repository.id
        fullName = repository.fullName
        language = repository.language
        stargazersCount = repository.stargazersCount
        watchersCount = repository.watchersCount
        forksCount = repository.forksCount
        openIssuesCount = repository.openIssuesCount
        avatarURL = repository.owner.avatarURL
    }

    var repository: Repository {
        Repository(
            id: id,
            fullName: fullName,
            language: language,
            stargazersCount: stargazersCount,
            watchersCount: watchersCount,
            forksCount: forksCount,
            openIssuesCount: openIssuesCount,
            owner: Repository.Owner(avatarURL: avatarURL)
        )
    }
}

/// 旧キー `data` の形式（初期実装が `DataItem` をそのまま保存していたもの）。GitHub の `id` を持たない。
private struct LegacyBookmarkRecord: Decodable {
    struct Owner: Decodable {
        let avatarUrl: String
    }

    let fullName: String
    let language: String?
    let stargazersCount: Int
    let watchersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let owner: Owner

    func repository() throws -> Repository {
        guard let avatarURL = URL(string: owner.avatarUrl) else {
            throw BookmarkStorageError.corruptedData(
                key: UserDefaultsBookmarkStorage.legacyKey,
                reason: "avatarUrl が URL として不正: \(owner.avatarUrl)"
            )
        }
        return Repository(
            id: Repository.provisionalID(fullName: fullName),
            fullName: fullName,
            language: language,
            stargazersCount: stargazersCount,
            watchersCount: watchersCount,
            forksCount: forksCount,
            openIssuesCount: openIssuesCount,
            owner: Repository.Owner(avatarURL: avatarURL)
        )
    }
}
