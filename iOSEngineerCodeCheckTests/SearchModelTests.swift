import Foundation
import Testing
@testable import iOSEngineerCodeCheck

@Suite("SearchModel の状態遷移")
@MainActor
struct SearchModelTests {
    @Test("初期状態は idle")
    func startsIdle() {
        let model = SearchModel(searcher: StubRepositorySearcher())
        #expect(model.state == .idle)
        #expect(model.query.isEmpty)
    }

    @Test("空白だけのクエリでは通信せず状態も変えない", arguments: ["", "   ", "\n\t"])
    func blankQueryDoesNotSearch(query: String) async {
        let stub = StubRepositorySearcher()
        let model = SearchModel(searcher: stub)
        model.query = query

        await model.search()

        #expect(model.state == .idle)
        #expect(await stub.receivedQueries.isEmpty)
    }

    @Test("前後の空白を除いたクエリで検索し、結果があれば loaded になる")
    func loadedWhenItemsReturned() async {
        let items = [Repository.fixture(id: 1), Repository.fixture(id: 2, fullName: "a/b")]
        let stub = StubRepositorySearcher(outcomes: [.success(.fixture(items))])
        let model = SearchModel(searcher: stub)
        model.query = "  swift \n"

        await model.search()

        #expect(model.state == .loaded(.fixture(query: "swift", items: items)))
        #expect(await stub.receivedQueries == ["swift"])
    }

    @Test("0 件なら empty になる")
    func emptyWhenNoItems() async {
        let stub = StubRepositorySearcher(outcomes: [.success(.fixture([]))])
        let model = SearchModel(searcher: stub)
        model.query = "nothing"

        await model.search()

        #expect(model.state == .empty)
    }

    @Test("通信が失敗したらエラーを保持した failed になる")
    func failedOnError() async {
        let stub = StubRepositorySearcher(outcomes: [.failure(.rateLimited)])
        let model = SearchModel(searcher: stub)
        model.query = "swift"

        await model.search()

        #expect(model.state == .failed(.rateLimited))
    }

    @Test("応答を待っている間は loading で、完了後に結果へ移る")
    func loadingWhileWaiting() async {
        let stub = StubRepositorySearcher()
        await stub.hold()
        let model = SearchModel(searcher: stub)
        model.query = "swift"

        let searching = Task { await model.search() }
        await stub.waitForCalls(1)
        #expect(model.state == .loading)

        let items = [Repository.fixture(id: 1)]
        await stub.resume(call: 0, with: .success(.fixture(items)))
        await searching.value

        #expect(model.state == .loaded(.fixture(query: "swift", items: items)))
    }

    @Test("reset で結果を捨てて idle に戻る")
    func resetReturnsToIdle() async {
        let stub = StubRepositorySearcher(outcomes: [.success(.fixture([.fixture()]))])
        let model = SearchModel(searcher: stub)
        model.query = "swift"
        await model.search()

        model.reset()

        #expect(model.state == .idle)
    }

    @Test("先に投げた古い検索の応答が後から届いても、新しい検索の結果を上書きしない")
    func staleResponseDoesNotOverwriteNewerResult() async {
        let stub = StubRepositorySearcher()
        await stub.hold()
        let model = SearchModel(searcher: stub)

        model.query = "old"
        let first = Task { await model.search() }
        await stub.waitForCalls(1)

        model.query = "new"
        let second = Task { await model.search() }
        await stub.waitForCalls(2)

        let newItems = [Repository.fixture(id: 2, fullName: "new/repo")]
        await stub.resume(call: 1, with: .success(.fixture(newItems)))
        await second.value
        #expect(model.state == .loaded(.fixture(query: "new", items: newItems)))

        let oldItems = [Repository.fixture(id: 1, fullName: "old/repo")]
        await stub.resume(call: 0, with: .success(.fixture(oldItems)))
        await first.value
        #expect(model.state == .loaded(.fixture(query: "new", items: newItems)), "古い応答で新しい結果を上書きしてはいけない")
    }

    @Test("古い検索が失敗で終わっても、新しい検索の結果を failed で上書きしない")
    func staleFailureDoesNotOverwriteNewerResult() async {
        let stub = StubRepositorySearcher()
        await stub.hold()
        let model = SearchModel(searcher: stub)

        model.query = "old"
        let first = Task { await model.search() }
        await stub.waitForCalls(1)

        model.query = "new"
        let second = Task { await model.search() }
        await stub.waitForCalls(2)

        let newItems = [Repository.fixture(id: 2, fullName: "new/repo")]
        await stub.resume(call: 1, with: .success(.fixture(newItems)))
        await second.value

        await stub.resume(call: 0, with: .failure(.rateLimited))
        await first.value
        #expect(model.state == .loaded(.fixture(query: "new", items: newItems)))
    }

    @Test("検索中に reset すると、その後に届いた応答は捨てられ idle のまま")
    func inFlightResponseIsDiscardedAfterReset() async {
        let stub = StubRepositorySearcher()
        await stub.hold()
        let model = SearchModel(searcher: stub)

        model.query = "swift"
        let searching = Task { await model.search() }
        await stub.waitForCalls(1)
        #expect(model.state == .loading)

        model.reset()
        #expect(model.state == .idle)

        await stub.resume(call: 0, with: .success(.fixture([.fixture()])))
        await searching.value
        #expect(model.state == .idle, "捨てた検索の応答が結果として表示されてはいけない")
    }

    @Test("reset 後に改めて検索すれば、新しい応答は通常どおり反映される")
    func searchAfterResetStillWorks() async {
        let stub = StubRepositorySearcher()
        await stub.hold()
        let model = SearchModel(searcher: stub)

        model.query = "first"
        let first = Task { await model.search() }
        await stub.waitForCalls(1)
        model.reset()

        model.query = "second"
        let second = Task { await model.search() }
        await stub.waitForCalls(2)

        let items = [Repository.fixture(id: 9, fullName: "second/repo")]
        await stub.resume(call: 1, with: .success(.fixture(items)))
        await second.value
        #expect(model.state == .loaded(.fixture(query: "second", items: items)))

        await stub.resume(call: 0, with: .success(.fixture([.fixture(id: 1, fullName: "first/repo")])))
        await first.value
        #expect(model.state == .loaded(.fixture(query: "second", items: items)))
    }

    // MARK: - 追加読み込み（完了条件 1: 同じ検索条件での追加読み込み）

    @Test("追加読み込みは同じ検索語で次のページを要求し、結果を末尾に追記する")
    func loadMoreRequestsNextPageWithSameQuery() async {
        let page1 = [Repository.fixture(id: 1), Repository.fixture(id: 2, fullName: "a/two")]
        let page2 = [Repository.fixture(id: 3, fullName: "a/three")]
        let stub = StubRepositorySearcher(outcomes: [
            .success(.fixture(page1, totalCount: 3)),
            .success(.fixture(page2, totalCount: 3)),
        ])
        let model = SearchModel(searcher: stub)
        model.query = " swift "
        await model.search()
        #expect(model.state == .loaded(.fixture(query: "swift", items: page1, nextPage: 2)))

        await model.loadMore()

        #expect(model.state == .loaded(.fixture(query: "swift", items: page1 + page2)))
        let requests = await stub.receivedRequests
        #expect(requests == [SearchRequest(query: "swift", page: 1), SearchRequest(query: "swift", page: 2)])
    }

    @Test("追加読み込みはテキスト欄を書き換えていても、検索した語で要求する")
    func loadMoreUsesSearchedQueryNotEditedText() async {
        let stub = StubRepositorySearcher(outcomes: [
            .success(.fixture([.fixture(id: 1)], totalCount: 2)),
            .success(.fixture([.fixture(id: 2, fullName: "a/two")], totalCount: 2)),
        ])
        let model = SearchModel(searcher: stub)
        model.query = "swift"
        await model.search()
        model.query = "swiftui"  // 未確定の入力

        await model.loadMore()

        #expect(await stub.receivedQueries == ["swift", "swift"])
        #expect(model.state.results?.query == "swift")
    }

    @Test("全件を受け取ったら続きは無く、追加読み込みは通信しない")
    func noNextPageWhenAllResultsLoaded() async {
        let items = [Repository.fixture(id: 1), Repository.fixture(id: 2, fullName: "a/two")]
        let stub = StubRepositorySearcher(outcomes: [.success(.fixture(items, totalCount: 2))])
        let model = SearchModel(searcher: stub)
        model.query = "swift"
        await model.search()
        #expect(model.state.results?.nextPage == nil)

        await model.loadMore()

        #expect(model.state == .loaded(.fixture(query: "swift", items: items)))
        #expect(await stub.receivedRequests.count == 1)
    }

    @Test("GitHub の上限 1000 件に達したら、totalCount が大きくても続きは無い")
    func noNextPageBeyondGitHubCap() async {
        // モデルは 1 ページの件数を知らないので、受け取った累計件数で判定する。ここでは 1 応答で上限に達させる
        let page = (1...1000).map { Repository.fixture(id: $0, fullName: "a/\($0)") }
        let stub = StubRepositorySearcher(outcomes: [.success(.fixture(page, totalCount: 437_679))])
        let model = SearchModel(searcher: stub)
        model.query = "swift"
        await model.search()

        #expect(model.state.results?.nextPage == nil)
        #expect(model.state.results?.items.count == 1000)
    }

    @Test("空のページが返ったら、件数が残っていても続きは無い")
    func emptyPageEndsPagination() async {
        let stub = StubRepositorySearcher(outcomes: [
            .success(.fixture([.fixture(id: 1)], totalCount: 50)),
            .success(.fixture([], totalCount: 50)),
        ])
        let model = SearchModel(searcher: stub)
        model.query = "swift"
        await model.search()
        #expect(model.state.results?.nextPage == 2)

        await model.loadMore()

        #expect(model.state.results?.items.map(\.id) == [1])
        #expect(model.state.results?.nextPage == nil)
    }

    @Test("追加読み込み中に再度呼んでも二重に要求しない")
    func loadMoreIsIgnoredWhileRequestInFlight() async {
        let stub = StubRepositorySearcher(outcomes: [.success(.fixture([.fixture(id: 1)], totalCount: 50))])
        let model = SearchModel(searcher: stub)
        model.query = "swift"
        await model.search()
        await stub.hold()

        let loading = Task { await model.loadMore() }
        await stub.waitForCalls(2)
        #expect(model.state == .loadingMore(.fixture(query: "swift", items: [.fixture(id: 1)], nextPage: 2)))

        await model.loadMore()  // 進行中なので何もしない
        #expect(await stub.receivedRequests.count == 2)

        await stub.resume(call: 1, with: .success(.fixture([.fixture(id: 2, fullName: "a/two")], totalCount: 50)))
        await loading.value
        #expect(model.state.results?.items.map(\.id) == [1, 2])
        #expect(model.state.results?.nextPage == 3)
    }

    // MARK: - 重複排除（完了条件 4）

    @Test("次のページに表示済みの id が混ざっても重複して表示しない（先に表示した方を残す）")
    func loadMoreSkipsRepositoriesAlreadyShown() async {
        let shown = Repository.fixture(id: 2, fullName: "a/two", stargazersCount: 10)
        let shifted = Repository.fixture(id: 2, fullName: "a/two", stargazersCount: 11)  // 順位がずれて再登場
        let stub = StubRepositorySearcher(outcomes: [
            .success(.fixture([.fixture(id: 1), shown], totalCount: 4)),
            .success(.fixture([shifted, .fixture(id: 3, fullName: "a/three")], totalCount: 4)),
        ])
        let model = SearchModel(searcher: stub)
        model.query = "swift"
        await model.search()

        await model.loadMore()

        let items = model.state.results?.items
        #expect(items?.map(\.id) == [1, 2, 3])
        #expect(items?[1].stargazersCount == 10, "先に表示した値を保つ")
        #expect(model.state.results?.nextPage == nil, "受け取った累計 4 件で totalCount に達している")
    }

    @Test("最初のページに同じ id が重複していても 1 件にまとめる")
    func firstPageDuplicatesAreCollapsed() async {
        let stub = StubRepositorySearcher(outcomes: [.success(.fixture([.fixture(id: 1), .fixture(id: 1)]))])
        let model = SearchModel(searcher: stub)
        model.query = "swift"

        await model.search()

        #expect(model.state.results?.items.map(\.id) == [1])
    }
}
