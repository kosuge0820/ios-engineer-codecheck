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
        #expect(model.state == .loaded(newItems))

        let oldItems = [Repository.fixture(id: 1, fullName: "old/repo")]
        await stub.resume(call: 0, with: .success(.fixture(oldItems)))
        await first.value
        #expect(model.state == .loaded(newItems), "古い応答で新しい結果を上書きしてはいけない")
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
        #expect(model.state == .loaded(newItems))
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
        #expect(model.state == .loaded(items))

        await stub.resume(call: 0, with: .success(.fixture([.fixture(id: 1, fullName: "first/repo")])))
        await first.value
        #expect(model.state == .loaded(items))
    }
}
