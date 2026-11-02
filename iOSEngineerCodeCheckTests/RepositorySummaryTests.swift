import Foundation
import Testing
@testable import iOSEngineerCodeCheck

@Suite("リポジトリの表示用の値")
struct RepositorySummaryTests {
    private let locale = Locale(identifier: "ja_JP")
    /// `Repository.fixture` の既定の最終更新（`fixturePushedAt`）から 3 日と 1 時間後
    private let now = Repository.fixturePushedAt.addingTimeInterval(3 * 86_400 + 3_600)

    private func summary(_ repository: Repository, isBookmarked: Bool = false) -> RepositorySummary {
        RepositorySummary(repository, isBookmarked: isBookmarked, locale: locale, now: now)
    }

    @Test("Star 数は桁区切りで表示する")
    func starCountIsGrouped() {
        #expect(summary(.fixture(stargazersCount: 70523)).starText == "70,523")
    }

    @Test("VoiceOver の読み上げは 名前 → 説明 → 言語 → Star 数 → 更新 → ブックマーク済み の順")
    func accessibilityLabelOrder() {
        let repository = Repository.fixture(
            fullName: "swiftlang/swift", language: "Swift", stargazersCount: 70523,
            description: "The Swift Programming Language"
        )
        #expect(
            summary(repository, isBookmarked: true).accessibilityLabel
                == "swiftlang/swift、The Swift Programming Language、Swift、Star 70,523、3日前に更新、ブックマーク済み"
        )
        #expect(
            summary(repository, isBookmarked: false).accessibilityLabel
                == "swiftlang/swift、The Swift Programming Language、Swift、Star 70,523、3日前に更新"
        )
    }

    @Test("言語が無いリポジトリは読み上げと一覧で言語を省き、詳細では「言語の情報なし」と示す")
    func missingLanguage() {
        let repository = Repository.fixture(language: nil, stargazersCount: 5, description: nil, pushedAt: nil)
        let summary = summary(repository)
        #expect(summary.language == nil)
        #expect(summary.languageText == "言語の情報なし")
        #expect(summary.accessibilityLabel == "octocat/hello-world、Star 5")
    }

    @Test("詳細の統計は Star → Fork → Open Issue → Watcher の順で、値は桁区切り")
    func statsOrderAndFormatting() {
        let repository = Repository.fixture(
            stargazersCount: 70523, watchersCount: 70523, forksCount: 10887, openIssuesCount: 9544
        )
        let stats = summary(repository).stats
        #expect(stats.map(\.title) == ["Star", "Fork", "Open Issue", "Watcher"])
        #expect(stats.map(\.valueText) == ["70,523", "10,887", "9,544", "70,523"])
        #expect(stats[0].accessibilityLabel == "Star 70,523")
    }

    @Test("説明文は前後の空白と改行を除き、無い・空白だけなら出さない")
    func descriptionIsTrimmed() {
        let padded = Repository.fixture(description: "  NOTE: Find the official repo elsewhere \n")
        #expect(summary(padded).descriptionText == "NOTE: Find the official repo elsewhere")
        #expect(summary(.fixture(description: "   \n")).descriptionText == nil)
        #expect(summary(.fixture(description: nil)).descriptionText == nil)
        #expect(summary(.fixture(description: nil)).accessibilityLabel == "octocat/hello-world、Swift、Star 10、3日前に更新")
    }

    @Test("最終更新は最も大きい単位 1 つの相対表記。1 分未満と未来の日時は「たった今」")
    func updatedTextUsesLargestUnit() {
        #expect(summary(.fixture(pushedAt: now.addingTimeInterval(-3 * 86_400 - 3_600))).updatedText == "3日前に更新")
        #expect(summary(.fixture(pushedAt: now.addingTimeInterval(-40 * 86_400))).updatedText == "1か月前に更新")
        #expect(summary(.fixture(pushedAt: now.addingTimeInterval(-2 * 366 * 86_400))).updatedText == "2年前に更新")
        #expect(summary(.fixture(pushedAt: now.addingTimeInterval(-3 * 3_600))).updatedText == "3時間前に更新")
        #expect(summary(.fixture(pushedAt: now.addingTimeInterval(-90))).updatedText == "1分前に更新")
        #expect(summary(.fixture(pushedAt: now.addingTimeInterval(-30))).updatedText == "たった今更新")
        #expect(summary(.fixture(pushedAt: now.addingTimeInterval(3_600))).updatedText == "たった今更新", "端末時計のずれ")
        #expect(summary(.fixture(pushedAt: nil)).updatedText == nil)
    }

    @Test("アーカイブ済みは更新日より優先して読み上げ、一覧の補助行でも更新日の代わりに示す")
    func archivedTakesPrecedenceOverUpdate() {
        let archived = Repository.fixture(
            fullName: "tensorflow/swift", language: "Jupyter Notebook", stargazersCount: 6114, isArchived: true
        )
        let summary = summary(archived)
        #expect(summary.isArchived)
        #expect(RepositorySummary.archivedText == "アーカイブ済み")
        #expect(summary.updatedText == "3日前に更新", "詳細では両方出すので更新日も持つ")
        #expect(
            summary.accessibilityLabel == "tensorflow/swift、A test repository、Jupyter Notebook、Star 6,114、アーカイブ済み"
        )
    }

    @Test("GitHub のページは API の html_url を使い、無ければ fullName から導出する")
    func webURLFallsBackToFullName() throws {
        let renamed = Repository.fixture(fullName: "a/b", htmlURL: URL(string: "https://github.com/a/b-renamed"))
        #expect(summary(renamed).webURL?.absoluteString == "https://github.com/a/b-renamed")
        let withoutURL = Repository(
            id: 1, fullName: "octocat/hello-world", language: nil, stargazersCount: 0, watchersCount: 0, forksCount: 0,
            openIssuesCount: 0, owner: Repository.Owner(avatarURL: URL(filePath: "/avatar.png")),
            description: nil, htmlURL: nil, pushedAt: nil, isArchived: false
        )
        #expect(summary(withoutURL).webURL?.absoluteString == "https://github.com/octocat/hello-world")
    }
}
