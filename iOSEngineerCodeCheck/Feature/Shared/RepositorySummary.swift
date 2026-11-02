import Foundation

/// 一覧と詳細で共有する、リポジトリの表示用の値。
///
/// 文字列の組み立てを View から分離し、桁区切りや VoiceOver の読み上げ文を単体テストできるようにする。
struct RepositorySummary: Equatable {
    /// 詳細画面の統計 1 項目。
    struct Stat: Equatable, Identifiable {
        let title: String
        let systemImage: String
        let value: Int
        let valueText: String

        var id: String { title }

        /// VoiceOver が読む文（「Star 70,523」）。
        var accessibilityLabel: String { "\(title) \(valueText)" }
    }

    let title: String
    let language: String?
    let isBookmarked: Bool
    /// 桁区切りの Star 数（一覧の補助行）。
    let starText: String
    /// 詳細画面に出す順。Watcher は GitHub Search API では Star と同じ値になるため末尾に置く。
    let stats: [Stat]

    init(_ repository: Repository, isBookmarked: Bool, locale: Locale = .current) {
        let format = IntegerFormatStyle<Int>().locale(locale)
        title = repository.fullName
        language = repository.language
        self.isBookmarked = isBookmarked
        starText = repository.stargazersCount.formatted(format)
        let items: [(title: String, systemImage: String, value: Int)] = [
            ("Star", "star", repository.stargazersCount),
            ("Fork", "arrow.triangle.branch", repository.forksCount),
            ("Open Issue", "exclamationmark.circle", repository.openIssuesCount),
            ("Watcher", "eye", repository.watchersCount),
        ]
        stats = items.map {
            Stat(title: $0.title, systemImage: $0.systemImage, value: $0.value, valueText: $0.value.formatted(format))
        }
    }

    /// 言語の表示文。不明なら「言語の情報なし」。
    var languageText: String { language ?? "言語の情報なし" }

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
}
