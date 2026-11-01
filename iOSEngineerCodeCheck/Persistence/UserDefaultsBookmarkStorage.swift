import Foundation

/// `UserDefaults` にブックマークを保存する。
///
/// - 保存形式は API モデルと切り離した `BookmarkRecordV1`（キー `bookmarks.v1`）。
/// - 旧キー `data`（`id` を持たない形式）は一度だけ読み込んで v1 に移行し、成功したら旧キーを消す。
/// - 解釈できないデータは例外にし、黙って消さない。元キーは次の `save` で上書きされるため、
///   退避キー（`<元のキー>.unreadable`）へ複製してから例外を投げる。
struct UserDefaultsBookmarkStorage: BookmarkStoring {
    static let currentKey = "bookmarks.v1"
    static let legacyKey = "data"

    /// 解釈できなかった保存データの退避先。既に退避データがあれば上書きしない。
    static func unreadableBackupKey(for key: String) -> String {
        "\(key).unreadable"
    }

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
        let legacyRecords = try decode([LegacyBookmarkRecord].self, from: legacyData, key: Self.legacyKey)
        // 旧アプリは Bookmark タブから Remove した項目を marked: false のまま保存していたので、利用者の意図どおり移行しない
        let activeRecords = legacyRecords.filter { $0.marked != false }
        let migrated: [Repository]
        do {
            migrated = try activeRecords.map { try $0.repository() }
        } catch {
            throw preserveUnreadable(legacyData, key: Self.legacyKey, reason: String(describing: error))
        }
        try save(migrated)
        defaults.removeObject(forKey: Self.legacyKey)
        Log.persistence.notice(
            "旧キー \(Self.legacyKey) から \(migrated.count) 件を \(Self.currentKey) へ移行した（Remove 済み \(legacyRecords.count - activeRecords.count) 件は除外）"
        )
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
            throw preserveUnreadable(data, key: key, reason: String(describing: error))
        }
    }

    /// 解釈できなかったデータを退避キーへ複製し、呼び出し元が投げるエラーを返す。
    private func preserveUnreadable(_ data: Data, key: String, reason: String) -> BookmarkStorageError {
        let backupKey = Self.unreadableBackupKey(for: key)
        if defaults.data(forKey: backupKey) == nil {
            defaults.set(data, forKey: backupKey)
            Log.persistence.error("キー \(key) の保存データを解釈できないため \(backupKey) へ退避した: \(reason)")
        } else {
            Log.persistence.error("キー \(key) の保存データを解釈できない。退避先 \(backupKey) は既存のものを保持: \(reason)")
        }
        return .corruptedData(key: key, reason: reason)
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
/// `marked` は旧アプリのブックマーク状態。`false` は Remove 済み、`nil` は未設定（ブックマーク扱い）。
private struct LegacyBookmarkRecord: Decodable {
    struct Owner: Decodable {
        let avatarUrl: String
    }

    struct InvalidAvatarURL: Error, CustomStringConvertible {
        let value: String
        var description: String { "avatarUrl が URL として不正: \(value)" }
    }

    let fullName: String
    let language: String?
    let stargazersCount: Int
    let watchersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let owner: Owner
    let marked: Bool?

    func repository() throws -> Repository {
        guard let avatarURL = URL(string: owner.avatarUrl) else {
            throw InvalidAvatarURL(value: owner.avatarUrl)
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
