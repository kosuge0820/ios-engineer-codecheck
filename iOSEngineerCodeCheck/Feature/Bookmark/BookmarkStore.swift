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

    /// 未登録なら追加する。登録済みなら最新の値への置き換えだけを試みる（`refresh(with:)`）。
    func add(_ repository: Repository) {
        if isBookmarked(repository) {
            refresh(with: repository)
            return
        }
        bookmarks.append(repository)
        persist()
    }

    /// 登録済みの項目を、検索結果から得た最新の値に置き換えて保存する。値が同じなら何もしない。
    ///
    /// 保存した値は時間とともに古くなり（Star 数）、旧データ由来の項目は説明や最終更新日時を持たず暫定 id のままなので、
    /// 詳細画面の表示時に呼んで通信なしで埋める。Bookmark タブから開いた場合は保存値そのものが渡るので保存は起きない。
    /// 暫定 id の値（旧データ）では置き換えない。
    func refresh(with repository: Repository) {
        guard !repository.hasProvisionalID,
            let index = index(of: repository),
            bookmarks[index] != repository
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
