import Foundation
import Testing
@testable import iOSEngineerCodeCheck

@Suite("リポジトリの表示用の値")
struct RepositorySummaryTests {
    private let locale = Locale(identifier: "en_US")

    @Test("Star 数は桁区切りで表示する")
    func starCountIsGrouped() {
        let summary = RepositorySummary(.fixture(stargazersCount: 70523), isBookmarked: false, locale: locale)
        #expect(summary.starText == "70,523")
    }

    @Test("VoiceOver の読み上げは 名前 → 言語 → Star 数 → ブックマーク済み の順")
    func accessibilityLabelOrder() {
        let repository = Repository.fixture(fullName: "swiftlang/swift", language: "Swift", stargazersCount: 70523)
        #expect(
            RepositorySummary(repository, isBookmarked: true, locale: locale).accessibilityLabel
                == "swiftlang/swift、Swift、Star 70,523、ブックマーク済み"
        )
        #expect(
            RepositorySummary(repository, isBookmarked: false, locale: locale).accessibilityLabel
                == "swiftlang/swift、Swift、Star 70,523"
        )
    }

    @Test("言語が無いリポジトリは読み上げと一覧で言語を省き、詳細では「言語の情報なし」と示す")
    func missingLanguage() {
        let repository = Repository.fixture(language: nil, stargazersCount: 5)
        let summary = RepositorySummary(repository, isBookmarked: false, locale: locale)
        #expect(summary.language == nil)
        #expect(summary.languageText == "言語の情報なし")
        #expect(summary.accessibilityLabel == "octocat/hello-world、Star 5")
    }

    @Test("詳細の統計は Star → Fork → Open Issue → Watcher の順で、値は桁区切り")
    func statsOrderAndFormatting() {
        let repository = Repository.fixture(
            stargazersCount: 70523, watchersCount: 70523, forksCount: 10887, openIssuesCount: 9544
        )
        let stats = RepositorySummary(repository, isBookmarked: false, locale: locale).stats
        #expect(stats.map(\.title) == ["Star", "Fork", "Open Issue", "Watcher"])
        #expect(stats.map(\.valueText) == ["70,523", "10,887", "9,544", "70,523"])
        #expect(stats[0].accessibilityLabel == "Star 70,523")
    }
}
