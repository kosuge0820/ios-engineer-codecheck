import Foundation
import Testing
@testable import iOSEngineerCodeCheck

@Suite("BookmarkStore の追加・削除・永続化")
@MainActor
struct BookmarkStoreTests {
    @Test("初期化時に保存済みブックマークを読み込む")
    func loadsStoredBookmarks() {
        let saved = [Repository.fixture(id: 10, fullName: "a/one")]
        let store = BookmarkStore(storage: InMemoryBookmarkStorage(stored: saved))

        #expect(store.bookmarks == saved)
        #expect(store.isBookmarked(saved[0]))
    }

    @Test("読み込みに失敗しても空で起動し、失敗したことを UI 向けに保持する")
    func startsEmptyWhenLoadFails() {
        let store = BookmarkStore(storage: InMemoryBookmarkStorage(failsOnLoad: true))
        #expect(store.bookmarks.isEmpty)
        #expect(store.failedToLoad)
    }

    @Test("正常に読み込めたときは失敗フラグが立たない")
    func loadFlagIsClearWhenLoadSucceeds() {
        let store = BookmarkStore(storage: InMemoryBookmarkStorage())
        #expect(!store.failedToLoad)
    }

    @Test("読めなかった保存データは、その後の add で上書きされず退避先に残る")
    func unreadableStoredDataSurvivesFirstAdd() throws {
        let temporary = try TemporaryDefaults()
        let unreadable = Data("not json".utf8)
        temporary.defaults.set(unreadable, forKey: UserDefaultsBookmarkStorage.currentKey)

        let store = BookmarkStore(storage: UserDefaultsBookmarkStorage(defaults: temporary.defaults))
        #expect(store.bookmarks.isEmpty)
        #expect(store.failedToLoad)

        store.add(.fixture(id: 1))

        #expect(store.bookmarks == [.fixture(id: 1)])
        let backupKey = UserDefaultsBookmarkStorage.unreadableBackupKey(for: UserDefaultsBookmarkStorage.currentKey)
        #expect(temporary.defaults.data(forKey: backupKey) == unreadable, "読めなかった保存データを黙って消してはいけない")
    }

    @Test("add すると一覧に入り、即座に保存される")
    func addPersistsImmediately() {
        let storage = InMemoryBookmarkStorage()
        let store = BookmarkStore(storage: storage)
        let repository = Repository.fixture(id: 1)

        store.add(repository)

        #expect(store.isBookmarked(repository))
        #expect(store.bookmarks == [repository])
        #expect(storage.stored == [repository])
        #expect(storage.saveCount == 1)
    }

    @Test("同じ id を二重に add しても 1 件のまま。値が変わっていれば新しい値に置き換えて保存する")
    func addIsIdempotent() {
        let storage = InMemoryBookmarkStorage()
        let store = BookmarkStore(storage: storage)

        store.add(.fixture(id: 1, stargazersCount: 1))
        store.add(.fixture(id: 1, stargazersCount: 2))
        store.add(.fixture(id: 1, stargazersCount: 2))

        #expect(store.bookmarks == [.fixture(id: 1, stargazersCount: 2)])
        #expect(storage.saveCount == 2, "同じ値の add では保存しない")
    }

    @Test("remove すると一覧から消え、即座に保存される")
    func removePersistsImmediately() {
        let repository = Repository.fixture(id: 1)
        let storage = InMemoryBookmarkStorage(stored: [repository])
        let store = BookmarkStore(storage: storage)

        store.remove(repository)

        #expect(!store.isBookmarked(repository))
        #expect(store.bookmarks.isEmpty)
        #expect(storage.stored.isEmpty)
        #expect(storage.saveCount == 1)
    }

    @Test("Star 数などが変わった同じリポジトリでも id で remove できる")
    func removeMatchesByID() {
        let stale = Repository.fixture(id: 1, stargazersCount: 100)
        let fresh = Repository.fixture(id: 1, stargazersCount: 200)
        let store = BookmarkStore(storage: InMemoryBookmarkStorage(stored: [stale]))

        #expect(store.isBookmarked(fresh))
        store.remove(fresh)
        #expect(store.bookmarks.isEmpty)
    }

    @Test("toggle は追加と削除を往復する")
    func toggleRoundTrip() {
        let storage = InMemoryBookmarkStorage()
        let store = BookmarkStore(storage: storage)
        let repository = Repository.fixture(id: 1)

        store.toggle(repository)
        #expect(store.isBookmarked(repository))
        store.toggle(repository)
        #expect(!store.isBookmarked(repository))
        #expect(storage.saveCount == 2)
    }

    @Test("保存に失敗しても画面上の状態は維持される（失敗はログに残す）")
    func keepsStateWhenSaveFails() {
        let storage = InMemoryBookmarkStorage(failsOnSave: true)
        let store = BookmarkStore(storage: storage)
        let repository = Repository.fixture(id: 1)

        store.add(repository)

        #expect(store.isBookmarked(repository))
        #expect(storage.stored.isEmpty)
    }

    @Test("旧データ由来の暫定 id を持つ項目は fullName で照合される")
    func provisionalIDMatchesByFullName() {
        let legacy = Repository.fixture(
            id: Repository.provisionalID(fullName: "swiftlang/swift"),
            fullName: "swiftlang/swift"
        )
        let fromSearch = Repository.fixture(id: 44_838_949, fullName: "swiftlang/swift")
        let storage = InMemoryBookmarkStorage(stored: [legacy])
        let store = BookmarkStore(storage: storage)

        #expect(store.isBookmarked(fromSearch))

        store.add(fromSearch)
        #expect(store.bookmarks.count == 1, "暫定 id の項目があるので重複しない")

        store.remove(fromSearch)
        #expect(store.bookmarks.isEmpty)
        #expect(storage.stored.isEmpty)
    }

    @Test("暫定 id の項目は、同じ fullName の実 id を add した時点で実 id の値に置き換えて保存する")
    func addUpgradesProvisionalID() {
        let legacy = Repository.fixture(
            id: Repository.provisionalID(fullName: "swiftlang/swift"),
            fullName: "swiftlang/swift",
            stargazersCount: 70_529
        )
        let storage = InMemoryBookmarkStorage(stored: [legacy])
        let store = BookmarkStore(storage: storage)
        let fromSearch = Repository.fixture(id: 44_838_949, fullName: "swiftlang/swift", stargazersCount: 70_530)

        store.add(fromSearch)

        #expect(store.bookmarks == [fromSearch])
        #expect(storage.stored == [fromSearch])
        #expect(storage.saveCount == 1)

        store.add(fromSearch)
        #expect(storage.saveCount == 1, "実 id になった後は二重 add で保存しない")
    }

    @Test("暫定 id の項目は、同じ fullName の実 id を知った時点（add を経ずに）で置き換えて保存する")
    func resolvesProvisionalIDWithoutAdd() {
        let legacy = Repository.fixture(
            id: Repository.provisionalID(fullName: "swiftlang/swift"),
            fullName: "swiftlang/swift",
            stargazersCount: 70_529
        )
        let storage = InMemoryBookmarkStorage(stored: [legacy])
        let store = BookmarkStore(storage: storage)
        let fromSearch = Repository.fixture(id: 44_838_949, fullName: "swiftlang/swift", stargazersCount: 70_530)

        store.refresh(with: fromSearch)

        #expect(store.bookmarks == [fromSearch])
        #expect(storage.stored == [fromSearch])
        #expect(storage.saveCount == 1)
        #expect(store.isBookmarked(fromSearch), "置き換え後も Remove ボタンのままで、詳細画面の表示は変わらない")

        store.refresh(with: fromSearch)
        #expect(storage.saveCount == 1, "同じ値なら何もしない")
    }

    @Test("refresh は登録済みの項目を、検索から開いた最新の値（説明・更新日時・Star 数）に置き換えて保存する")
    func refreshReplacesStoredValueWithNewer() {
        let stale = Repository.fixture(id: 1, fullName: "a/one", stargazersCount: 1, description: nil, pushedAt: nil)
        let storage = InMemoryBookmarkStorage(stored: [stale])
        let store = BookmarkStore(storage: storage)
        let fresh = Repository.fixture(id: 1, fullName: "a/one", stargazersCount: 99, description: "Now described")

        store.refresh(with: fresh)

        #expect(store.bookmarks == [fresh])
        #expect(storage.stored == [fresh])
        #expect(storage.saveCount == 1)
        #expect(store.isBookmarked(stale), "id が同じなので旧い値でも登録済みと判定される")
    }

    @Test("refresh は値が同じなら保存しない（Bookmark タブから開いた場合は保存値そのものが渡る）")
    func refreshDoesNotSaveWhenUnchanged() {
        let stored = Repository.fixture(id: 1, fullName: "a/one")
        let storage = InMemoryBookmarkStorage(stored: [stored])
        let store = BookmarkStore(storage: storage)

        store.refresh(with: stored)

        #expect(store.bookmarks == [stored])
        #expect(storage.saveCount == 0)
    }

    @Test("refresh は未登録のリポジトリを追加せず、暫定 id の値で上書きもしない")
    func refreshIgnoresUnregisteredAndProvisional() {
        let real = Repository.fixture(id: 1, fullName: "a/one", stargazersCount: 1)
        let storage = InMemoryBookmarkStorage(stored: [real])
        let store = BookmarkStore(storage: storage)

        store.refresh(with: Repository.fixture(id: 2, fullName: "b/two"))
        store.refresh(
            with: Repository.fixture(
                id: Repository.provisionalID(fullName: "a/one"), fullName: "a/one", stargazersCount: 5
            )
        )

        #expect(store.bookmarks == [real], "未登録は追加しない。暫定 id で上書きしない")
        #expect(storage.saveCount == 0)
    }
}
