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
                            locale: locale
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

/// 一覧の 1 行。名前を 1 行目、言語と Star 数を補助行に置く。
///
/// アクセシビリティサイズでは補助行を縦に並べ、単語の途中で折り返されるのを避ける。
struct RepositoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            metadata
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
    }

    private var metadata: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if let language = summary.language {
                Label(language, systemImage: RepositorySummary.languageSystemImage)
            }
            Label(summary.starText, systemImage: RepositorySummary.starSystemImage)
        }
        .labelStyle(.compact)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
