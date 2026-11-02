import Foundation

/// 一覧と詳細で共有する、リポジトリの表示用の値。
///
/// 文字列の組み立てを View から分離し、桁区切りや VoiceOver の読み上げ文を単体テストできるようにする。
/// 値は使うときに計算する（一覧の行は Star 数しか表示しないため）。
struct RepositorySummary: Equatable {
    /// 詳細画面の統計 1 項目。
    struct Stat: Equatable, Identifiable {
        let title: String
        let systemImage: String
        let valueText: String

        var id: String { title }

        /// VoiceOver が読む文（「Star 70,523」）。
        var accessibilityLabel: String { "\(title) \(valueText)" }
    }

    /// 言語と Star 数のアイコン。一覧と詳細で同じものを使う。
    static let languageSystemImage = "chevron.left.forwardslash.chevron.right"
    static let starSystemImage = "star"

    let isBookmarked: Bool

    private let repository: Repository
    private let locale: Locale

    /// `locale` は桁区切りに使う。View は `@Environment(\.locale)` を渡し、テストは固定する。
    init(_ repository: Repository, isBookmarked: Bool, locale: Locale) {
        self.repository = repository
        self.isBookmarked = isBookmarked
        self.locale = locale
    }

    var title: String { repository.fullName }

    var language: String? { repository.language }

    /// 言語の表示文。不明なら「言語の情報なし」。
    var languageText: String { language ?? "言語の情報なし" }

    /// 桁区切りの Star 数（一覧の補助行）。
    var starText: String { format(repository.stargazersCount) }

    /// 詳細画面に出す順。Watcher は GitHub Search API では Star と同じ値になるため末尾に置く。
    var stats: [Stat] {
        [
            Stat(title: "Star", systemImage: Self.starSystemImage, valueText: starText),
            Stat(title: "Fork", systemImage: "arrow.triangle.branch", valueText: format(repository.forksCount)),
            Stat(
                title: "Open Issue",
                systemImage: "exclamationmark.circle",
                valueText: format(repository.openIssuesCount)
            ),
            Stat(title: "Watcher", systemImage: "eye", valueText: format(repository.watchersCount)),
        ]
    }

    /// 一覧の行を VoiceOver が 1 要素として読む文。名前 → 言語 → Star 数 → ブックマーク済みの順。
    var accessibilityLabel: String {
        var parts = [title]
        if let language {
            parts.append(language)
        }
        parts.append("Star \(starText)")
        if isBookmarked {
            parts.append("ブックマーク済み")
        }
        return parts.joined(separator: "、")
    }

    private func format(_ value: Int) -> String {
        value.formatted(IntegerFormatStyle<Int>().locale(locale))
    }
}
