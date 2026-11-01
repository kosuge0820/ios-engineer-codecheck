import Foundation
import Observation

/// ブックマーク一覧を所有する唯一の場所。Search / Bookmark どちらの画面もここを通して更新し、変更は即座に保存する。
@Observable
@MainActor
final class BookmarkStore {
    private(set) var bookmarks: [Repository] = []

    private let storage: any BookmarkStoring

    init(storage: any BookmarkStoring) {
        self.storage = storage
        do {
            bookmarks = try storage.load()
        } catch {
            Log.persistence.error("ブックマークを読み込めないため空で開始する: \(String(describing: error))")
            bookmarks = []
        }
    }

    func isBookmarked(_ repository: Repository) -> Bool {
        index(of: repository) != nil
    }

    func add(_ repository: Repository) {
        guard !isBookmarked(repository) else { return }
        bookmarks.append(repository)
        persist()
    }

    func remove(_ repository: Repository) {
        guard let index = index(of: repository) else { return }
        bookmarks.remove(at: index)
        persist()
    }

    func toggle(_ repository: Repository) {
        if isBookmarked(repository) {
            remove(repository)
        } else {
            add(repository)
        }
    }

    /// GitHub の `id` で照合する。旧データ由来の暫定 id を持つ項目だけは `fullName` でも一致とみなす。
    private func index(of repository: Repository) -> Int? {
        bookmarks.firstIndex { stored in
            stored.id == repository.id || (stored.hasProvisionalID && stored.fullName == repository.fullName)
        }
    }

    private func persist() {
        do {
            try storage.save(bookmarks)
        } catch {
            Log.persistence.error("ブックマークの保存に失敗（画面上の状態は維持）: \(String(describing: error))")
        }
    }
}
