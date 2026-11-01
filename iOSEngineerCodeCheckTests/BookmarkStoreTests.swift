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

    @Test("読み込みに失敗しても空で起動し、クラッシュしない")
    func startsEmptyWhenLoadFails() {
        let store = BookmarkStore(storage: InMemoryBookmarkStorage(failsOnLoad: true))
        #expect(store.bookmarks.isEmpty)
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

    @Test("同じ id を二重に add しても 1 件のまま")
    func addIsIdempotent() {
        let storage = InMemoryBookmarkStorage()
        let store = BookmarkStore(storage: storage)

        store.add(.fixture(id: 1, stargazersCount: 1))
        store.add(.fixture(id: 1, stargazersCount: 2))

        #expect(store.bookmarks.count == 1)
        #expect(storage.saveCount == 1)
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
        let legacy = Repository.fixture(id: Repository.provisionalID(fullName: "swiftlang/swift"), fullName: "swiftlang/swift")
        let fromSearch = Repository.fixture(id: 44838949, fullName: "swiftlang/swift")
        let storage = InMemoryBookmarkStorage(stored: [legacy])
        let store = BookmarkStore(storage: storage)

        #expect(store.isBookmarked(fromSearch))

        store.add(fromSearch)
        #expect(store.bookmarks.count == 1, "暫定 id の項目があるので重複しない")

        store.remove(fromSearch)
        #expect(store.bookmarks.isEmpty)
        #expect(storage.stored.isEmpty)
    }
}
