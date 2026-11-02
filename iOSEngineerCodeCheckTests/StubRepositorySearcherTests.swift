import Foundation
import Testing
@testable import iOSEngineerCodeCheck

/// テストの土台であるスタブ自体の挙動を固定する。ここが壊れると SearchModel のテストが誤った理由で落ちる。
@Suite("StubRepositorySearcher の順序制御")
struct StubRepositorySearcherTests {
    @Test("hold 中の呼び出しは到着順ではなく resume で指定した順に完了し、要求内容を記録する")
    func resumesCallsInSpecifiedOrder() async throws {
        let stub = StubRepositorySearcher()
        await stub.hold()

        let first = Task { try await stub.search(SearchRequest(query: "swift", page: 1)) }
        await stub.waitForCalls(1)
        let second = Task { try await stub.search(SearchRequest(query: "swift", page: 2)) }
        await stub.waitForCalls(2)

        await stub.resume(call: 1, with: .success(.fixture([.fixture(id: 2)], totalCount: 100)))
        let secondResponse = try await second.value
        #expect(secondResponse.items.map(\.id) == [2])
        #expect(secondResponse.totalCount == 100)

        await stub.resume(call: 0, with: .failure(.rateLimited))
        await #expect(throws: GitHubSearchError.rateLimited) {
            try await first.value
        }

        let requests = await stub.receivedRequests
        #expect(requests == [SearchRequest(query: "swift", page: 1), SearchRequest(query: "swift", page: 2)])
    }

    @Test("到着前に resume した応答は、その番号の呼び出しが来た時点で即適用される")
    func earlyResumeAppliesOnArrival() async throws {
        let stub = StubRepositorySearcher()
        await stub.hold()
        await stub.resume(call: 0, with: .success(.fixture([.fixture(id: 7)])))

        let response = try await stub.search(SearchRequest(query: "q", page: 1))

        #expect(response.items.map(\.id) == [7])
        #expect(response.totalCount == 1, "totalCount 省略時は items の件数")
    }
}
