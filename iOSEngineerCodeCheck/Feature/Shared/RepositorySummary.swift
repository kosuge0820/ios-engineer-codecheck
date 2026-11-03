import Foundation

/// 一覧と詳細で共有する、リポジトリの表示用の値。
///
/// 文字列の組み立てを View から分離し、桁区切り・相対日付・VoiceOver の読み上げ文を単体テストできるようにする。
/// 値は使うときに計算する（一覧の行は統計のうち Star 数しか表示しないため）。
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

    /// 一覧と詳細で同じものを使うアイコン。
    static let languageSystemImage = "chevron.left.forwardslash.chevron.right"
    static let starSystemImage = "star"
    static let updatedSystemImage = "clock"
    static let archivedSystemImage = "archivebox"
    static let openSystemImage = "safari"

    /// アーカイブ済み（読み取り専用）の表示文。
    static let archivedText = "アーカイブ済み"

    /// 期間の単位（「3日」「1か月」）の整形に使うロケール。文言が日本語固定なので、端末のロケールに関わらず日本語で整える
    /// （桁区切りは端末のロケールに従う）。String Catalog を入れたら環境のロケールに戻す。
    private static let textLocale = Locale(identifier: "ja_JP")

    let isBookmarked: Bool

    private let repository: Repository
    private let locale: Locale
    private let now: Date

    /// `locale` は桁区切りに、`now` は相対日付の基準に使う。View は `@Environment(\.locale)` と `Date.now` を渡し、テストは固定する。
    init(_ repository: Repository, isBookmarked: Bool, locale: Locale, now: Date) {
        self.repository = repository
        self.isBookmarked = isBookmarked
        self.locale = locale
        self.now = now
    }

    var title: String { repository.fullName }

    var language: String? { repository.language }

    /// 言語の表示文。不明なら「言語の情報なし」。
    var languageText: String { language ?? "言語の情報なし" }

    /// 説明文。前後の空白と改行を除き、無い・空白だけなら nil（API に先頭が空白の例がある）。
    var descriptionText: String? {
        guard let text = repository.description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    /// 桁区切りの Star 数（一覧の補助行）。
    var starText: String { format(repository.stargazersCount) }

    var isArchived: Bool { repository.isArchived }

    /// 最終更新の相対表記（「3日前に更新」）。最も大きい単位 1 つで表し、1 分未満と未来の日時（端末時計のずれ）は「たった今更新」。
    /// 最終更新が不明なら nil。
    var updatedText: String? {
        guard let pushedAt = repository.pushedAt else { return nil }
        guard pushedAt < now else { return "たった今更新" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Self.textLocale
        let elapsed = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: pushedAt, to: now)
        let units: [(Calendar.Component, Date.ComponentsFormatStyle.Field)] = [
            (.year, .year), (.month, .month), (.day, .day), (.hour, .hour), (.minute, .minute),
        ]
        guard let (_, field) = units.first(where: { (elapsed.value(for: $0.0) ?? 0) > 0 }) else {
            return "たった今更新"
        }
        let duration = (pushedAt..<now).formatted(
            Date.ComponentsFormatStyle(style: .wide, locale: Self.textLocale, calendar: calendar, fields: [field])
        )
        return "\(duration)前に更新"
    }

    /// GitHub 上のページ。API の `html_url` が無い項目（旧い保存データ）は GitHub の URL 規則（`https://github.com/<fullName>`）から導く。
    /// 表示用の補完であって、モデルには書き戻さない。
    var webURL: URL? {
        if let htmlURL = repository.htmlURL {
            return htmlURL
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repository.fullName)"
        return components.url
    }

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

    /// 一覧の行を VoiceOver が 1 要素として読む文。名前 → 説明 → 言語 → Star 数 → アーカイブ済み / 更新 → ブックマーク済みの順。
    /// 一覧の補助行と同じく、アーカイブ済みなら更新日は読まない。
    var accessibilityLabel: String {
        var parts = [title]
        if let descriptionText {
            parts.append(descriptionText)
        }
        if let language {
            parts.append(language)
        }
        parts.append("Star \(starText)")
        if isArchived {
            parts.append(Self.archivedText)
        } else if let updatedText {
            parts.append(updatedText)
        }
        if isBookmarked {
            parts.append("ブックマーク済み")
        }
        return parts.joined(separator: "、")
    }

    private func format(_ value: Int) -> String {
        value.formatted(IntegerFormatStyle<Int>().locale(locale))
    }
}
