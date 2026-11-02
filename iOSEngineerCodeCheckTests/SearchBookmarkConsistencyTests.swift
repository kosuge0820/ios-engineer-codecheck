import Foundation
import Testing
@testable import iOSEngineerCodeCheck

/// 検索結果（複数ページ）とブックマークが同じ `BookmarkStore` を `id` で参照し、ページに依存しないことを確認する。
@Suite("検索結果とブックマークの一貫性")
@MainActor
struct SearchBookmarkConsistencyTests {
    @Test("追加読み込みで表示した項目も同じストアでブックマークでき、重複行や状態のずれが生じない")
    func bookmarkStateFollowsRepositoryIDAcrossPages() async throws {
        let page2Item = Repository.fixture(id: 2, fullName: "a/two", stargazersCount: 10)
        // 順位がずれて次のページに再登場（Star 数が変わっている）
        let page3Duplicate = Repository.fixture(id: 2, fullName: "a/two", stargazersCount: 12)
        let stub = StubRepositorySearcher(outcomes: [
            .success(.fixture([.fixture(id: 1)], totalCount: 4)),
            .success(.fixture([page2Item], totalCount: 4)),
            .success(.fixture([page3Duplicate, .fixture(id: 3, fullName: "a/three")], totalCount: 4)),
        ])
        let model = SearchModel(searcher: stub)
        let storage = InMemoryBookmarkStorage()
        let store = BookmarkStore(storage: storage)

        model.query = "swift"
        await model.search()
        await model.loadMore()
        let shown = try #require(model.state.results?.items.first { $0.id == 2 })

        store.toggle(shown)  // 詳細画面の Add to Bookmark に相当

        #expect(store.isBookmarked(shown))
        #expect(storage.stored.map(\.id) == [2], "即座に保存される")

        await model.loadMore()  // 同じ id が Star 数違いで再登場するページ

        let items = model.state.results?.items ?? []
        #expect(items.map(\.id) == [1, 2, 3], "重複行は増えない")
        #expect(items.allSatisfy { store.isBookmarked($0) == ($0.id == 2) }, "ブックマーク状態は id で決まり、ページに依存しない")
        #expect(store.isBookmarked(page3Duplicate), "Star 数が違っても同じリポジトリとして扱う")

        store.toggle(page3Duplicate)  // 詳細画面の Remove from Bookmark に相当

        #expect(!store.isBookmarked(shown))
        #expect(storage.stored.isEmpty)
    }
}
