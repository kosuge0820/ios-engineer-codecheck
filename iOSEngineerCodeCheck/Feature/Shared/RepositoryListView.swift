import SwiftUI

/// リポジトリの一覧。行をタップすると詳細へ遷移する。Search / Bookmark の両タブで使う。
///
/// `footer` は一覧の末尾に置く任意の View（Search タブの「さらに読み込む」など）。
struct RepositoryListView<Footer: View>: View {
    @Environment(BookmarkStore.self) private var bookmarkStore
    @Environment(\.locale) private var locale

    let repositories: [Repository]
    /// ブックマーク済みの印を行に出すか。Bookmark タブは全行が該当するので出さない。
    let showsBookmarkState: Bool
    private let footer: Footer

    init(repositories: [Repository], showsBookmarkState: Bool = true, @ViewBuilder footer: () -> Footer) {
        self.repositories = repositories
        self.showsBookmarkState = showsBookmarkState
        self.footer = footer()
    }

    var body: some View {
        List {
            ForEach(repositories) { repository in
                NavigationLink(value: repository) {
                    RepositoryRow(
                        summary: RepositorySummary(
                            repository,
                            isBookmarked: showsBookmarkState && bookmarkStore.isBookmarked(repository),
                            locale: locale,
                            now: .now
                        )
                    )
                }
            }
            footer
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Repository.self) { repository in
            RepositoryDetailView(repository: repository)
        }
    }
}

extension RepositoryListView where Footer == EmptyView {
    init(repositories: [Repository], showsBookmarkState: Bool = true) {
        self.init(repositories: repositories, showsBookmarkState: showsBookmarkState) { EmptyView() }
    }
}

/// 一覧の 1 行。名前 → 説明文（最大 2 行）→ 言語・Star 数・最終更新（またはアーカイブ済み）の 3 段。
///
/// 開く前に「何をするものか」「まだ保守されているか」を判断できるようにする。
/// 補助行はラベル単位で折り返す（`FlowLayout`）。幅が足りないときに単語の途中で折り返されず、
/// アクセシビリティサイズでは自然に 1 行ずつになる。
struct RepositoryRow: View {
    let summary: RepositorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if summary.isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
            }
            if let descriptionText = summary.descriptionText {
                Text(descriptionText)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            FlowLayout(horizontalSpacing: 12, verticalSpacing: 4) {
                if let language = summary.language {
                    Label(language, systemImage: RepositorySummary.languageSystemImage)
                }
                Label(summary.starText, systemImage: RepositorySummary.starSystemImage)
                // 幅を節約するため、アーカイブ済みなら更新日の代わりに示す（詳細では両方出す）
                if summary.isArchived {
                    Label(RepositorySummary.archivedText, systemImage: RepositorySummary.archivedSystemImage)
                } else if let updatedText = summary.updatedText {
                    Label(updatedText, systemImage: RepositorySummary.updatedSystemImage)
                }
            }
            .labelStyle(.compact)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
    }
}
