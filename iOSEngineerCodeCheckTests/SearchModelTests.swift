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

        #expect(model.state == .loaded(items))
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

        #expect(model.state == .loaded(items))
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
}
