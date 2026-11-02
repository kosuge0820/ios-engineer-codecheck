import Foundation
import Testing
@testable import iOSEngineerCodeCheck

@Suite("GitHubSearchClient の HTTP ステータス検証と URL 構築", .serialized)
struct GitHubSearchClientTests {
    private let client = GitHubSearchClient(session: StubURLProtocol.makeSession())

    @Test("200 なら SearchResponse を返す")
    func returnsResponseOn200() async throws {
        StubURLProtocol.register(query: "ok", status: 200, body: try Fixture.data("search-success"))

        let response = try await client.search(SearchRequest(query: "ok", page: 1))

        #expect(response.items.map(\.fullName) == ["swiftlang/swift", "openstack/swift"])
    }

    @Test("403 はレート制限として型付きエラーになる", arguments: [403, 429])
    func rateLimited(status: Int) async throws {
        let body = try Fixture.data("error-403-rate-limit")
        StubURLProtocol.register(query: "limit-\(status)", status: status, body: body)

        await #expect(throws: GitHubSearchError.rateLimited) {
            try await client.search(SearchRequest(query: "limit-\(status)", page: 1))
        }
    }

    @Test("422 は GitHub のメッセージ付きで invalidQuery になる")
    func invalidQueryOn422() async throws {
        StubURLProtocol.register(query: "too-long", status: 422, body: try Fixture.data("error-422"))

        let message = "Validation Failed: The search is longer than 256 characters."
        let expected = GitHubSearchError.invalidQuery(message: message)
        await #expect(throws: expected) {
            try await client.search(SearchRequest(query: "too-long", page: 1))
        }
    }

    @Test("想定外のステータスはコード付きで失敗する")
    func unexpectedStatus() async throws {
        StubURLProtocol.register(query: "boom", status: 500, body: Data("<html>".utf8))

        await #expect(throws: GitHubSearchError.unexpectedStatus(500)) {
            try await client.search(SearchRequest(query: "boom", page: 1))
        }
    }

    @Test("200 でも本文を解釈できなければ invalidResponse になる")
    func invalidBodyOn200() async throws {
        StubURLProtocol.register(query: "broken", status: 200, body: Data("{\"total_count\": 1}".utf8))

        do {
            _ = try await client.search(SearchRequest(query: "broken", page: 1))
            Issue.record("エラーが投げられるべき")
        } catch {
            guard case .invalidResponse = error else {
                Issue.record("invalidResponse 以外: \(error)")
                return
            }
        }
    }

    @Test("通信エラーは URLError を保ったまま network になる")
    func networkFailure() async throws {
        StubURLProtocol.registerFailure(query: "offline", error: URLError(.notConnectedToInternet))

        // URLSession は URLError の userInfo にタスク情報を足すので、値全体ではなく code で比べる
        do {
            _ = try await client.search(SearchRequest(query: "offline", page: 1))
            Issue.record("エラーが投げられるべき")
        } catch {
            guard case .network(let urlError) = error else {
                Issue.record("network 以外: \(error)")
                return
            }
            #expect(urlError.code == .notConnectedToInternet)
        }
    }

    @Test("クエリは URLQueryItem でエンコードされ & が区切りとして漏れない")
    func encodesAmpersandInQuery() async throws {
        StubURLProtocol.register(query: "a&b", status: 200, body: try Fixture.data("search-empty"))

        _ = try await client.search(SearchRequest(query: "a&b", page: 1))

        let requested = try #require(StubURLProtocol.requestedURLs.last)
        #expect(requested.absoluteString == "https://api.github.com/search/repositories?q=a%26b&page=1&per_page=30")
    }

    @Test("ページ番号と 1 ページの件数（既定 30）をクエリに付ける")
    func sendsPageAndPerPageQueryItems() async throws {
        StubURLProtocol.register(query: "paged", status: 200, body: try Fixture.data("search-empty"))

        _ = try await client.search(SearchRequest(query: "paged", page: 3))

        let requested = try #require(StubURLProtocol.requestedURLs.last)
        #expect(requested.absoluteString == "https://api.github.com/search/repositories?q=paged&page=3&per_page=30")
    }

    @Test("1 ページの件数は初期化時に変えられる")
    func perPageIsConfigurable() async throws {
        let client = GitHubSearchClient(session: StubURLProtocol.makeSession(), perPage: 100)
        StubURLProtocol.register(query: "wide", status: 200, body: try Fixture.data("search-empty"))

        _ = try await client.search(SearchRequest(query: "wide", page: 1))

        let requested = try #require(StubURLProtocol.requestedURLs.last)
        #expect(requested.absoluteString == "https://api.github.com/search/repositories?q=wide&page=1&per_page=100")
    }

    @Test("クエリ中の + はサーバで空白と解釈されないよう %2B に符号化される")
    func encodesPlusInQuery() async throws {
        StubURLProtocol.register(query: "c++", status: 200, body: try Fixture.data("search-empty"))

        _ = try await client.search(SearchRequest(query: "c++", page: 1))

        let requested = try #require(StubURLProtocol.requestedURLs.last)
        #expect(requested.absoluteString == "https://api.github.com/search/repositories?q=c%2B%2B&page=1&per_page=30")
    }

    @Test("空白と = を含むクエリも区切りとして漏れずに送られる")
    func encodesSpaceAndEqualsInQuery() async throws {
        StubURLProtocol.register(query: "language:swift a=b", status: 200, body: try Fixture.data("search-empty"))

        _ = try await client.search(SearchRequest(query: "language:swift a=b", page: 1))

        let requested = try #require(StubURLProtocol.requestedURLs.last)
        let expected = "https://api.github.com/search/repositories?q=language:swift%20a%3Db&page=1&per_page=30"
        #expect(requested.absoluteString == expected)
    }
}
