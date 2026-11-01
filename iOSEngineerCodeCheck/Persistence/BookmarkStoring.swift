import Foundation

/// ブックマークの永続化境界。本番は `UserDefaultsBookmarkStorage`、テストはスタブで差し替える。
/// 利用側（`BookmarkStore`）が `@MainActor` なので `Sendable` は要求しない（`UserDefaults` は SDK 上 `Sendable` でない）。
protocol BookmarkStoring {
    func load() throws -> [Repository]
    func save(_ repositories: [Repository]) throws
}

enum BookmarkStorageError: Error, Equatable {
    /// 保存データを解釈できない。データ自体は削除しない。
    case corruptedData(key: String, reason: String)
    /// エンコードや書き込みに失敗した。
    case writeFailed(key: String, reason: String)
}
