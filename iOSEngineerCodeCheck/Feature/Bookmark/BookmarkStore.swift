import Foundation
import Observation

/// ブックマーク一覧を所有する唯一の場所。Search / Bookmark どちらの画面もここを通して更新し、変更は即座に保存する。
@Observable
@MainActor
final class BookmarkStore {
    private(set) var bookmarks: [Repository] = []
    /// 起動時に保存データを読めなかったとき true。UI はこれを見て利用者に伝える。
    /// 読めなかったデータはストレージ側で退避されており、以降の保存で上書きされない。
    private(set) var failedToLoad = false

    private let storage: any BookmarkStoring

    init(storage: any BookmarkStoring) {
        self.storage = storage
        do {
            bookmarks = try storage.load()
        } catch {
            Log.persistence.error("ブックマークを読み込めないため空で開始する: \(String(describing: error), privacy: .public)")
            bookmarks = []
            failedToLoad = true
        }
    }

    func isBookmarked(_ repository: Repository) -> Bool {
        index(of: repository) != nil
    }

    /// 未登録なら追加する。登録済みなら暫定 id の置き換えだけを試みる（`resolveProvisionalID(with:)`）。
    func add(_ repository: Repository) {
        if isBookmarked(repository) {
            resolveProvisionalID(with: repository)
            return
        }
        bookmarks.append(repository)
        persist()
    }

    /// 旧データ由来の暫定 id の項目に、同じリポジトリの実 id が分かった時点で置き換えて保存する。
    ///
    /// 詳細画面の表示時にも呼ぶ。`isBookmarked` が true の経路では `add` が呼ばれないため、ここで置き換えないと暫定 id が残り続ける。
    func resolveProvisionalID(with repository: Repository) {
        guard !repository.hasProvisionalID,
            let index = index(of: repository),
            bookmarks[index].hasProvisionalID
        else { return }
        bookmarks[index] = repository
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
            Log.persistence.error("ブックマークの保存に失敗（画面上の状態は維持）: \(String(describing: error), privacy: .public)")
        }
    }
}
