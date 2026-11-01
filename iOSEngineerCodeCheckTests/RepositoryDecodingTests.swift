import Foundation
import Testing
@testable import iOSEngineerCodeCheck

@Suite("Repository / SearchResponse のデコード")
struct RepositoryDecodingTests {
    private let decoder = JSONDecoder()

    @Test("成功応答から id・名前・言語・件数・アバター URL を読める")
    func decodesSuccessResponse() throws {
        let response = try decoder.decode(SearchResponse.self, from: Fixture.data("search-success"))

        #expect(response.totalCount == 437679)
        #expect(response.items.count == 2)

        let first = try #require(response.items.first)
        #expect(first.id == 44838949)
        #expect(first.fullName == "swiftlang/swift")
        #expect(first.language == "Swift")
        #expect(first.stargazersCount == 70530)
        #expect(first.watchersCount == 70530)
        #expect(first.forksCount == 10884)
        #expect(first.openIssuesCount == 9528)
        #expect(first.owner.avatarURL.absoluteString == "https://avatars.githubusercontent.com/u/42816656?v=4")
    }

    @Test("language が null なら nil になる")
    func languageNullBecomesNil() throws {
        let response = try decoder.decode(SearchResponse.self, from: Fixture.data("search-language-null"))
        let item = try #require(response.items.first)
        #expect(item.language == nil)
        #expect(item.fullName == "example/design-docs")
    }

    @Test("0 件応答は items が空の SearchResponse になる")
    func decodesEmptyResponse() throws {
        let response = try decoder.decode(SearchResponse.self, from: Fixture.data("search-empty"))
        #expect(response.totalCount == 0)
        #expect(response.items.isEmpty)
    }

    @Test("items が欠けた応答はデコードに失敗する", arguments: ["search-missing-items", "error-403-rate-limit", "error-422"])
    func missingItemsThrows(fixture: String) throws {
        let data = try Fixture.data(fixture)
        #expect(throws: DecodingError.self) {
            try decoder.decode(SearchResponse.self, from: data)
        }
    }

    @Test("同一性は GitHub の id で決まり、他のフィールドの差は無視される")
    func identityIsNumericID() {
        let a = Repository.fixture(id: 7, fullName: "a/b", stargazersCount: 1)
        let b = Repository.fixture(id: 7, fullName: "a/b", stargazersCount: 999)
        #expect(a.id == b.id)
        #expect(a != b, "値としては別物（UI の identity は id、等値性は全フィールド）")
    }
}
