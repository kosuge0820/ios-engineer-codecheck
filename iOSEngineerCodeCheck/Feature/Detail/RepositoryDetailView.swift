import SwiftUI

/// リポジトリ詳細。名前を見出しに、統計をラベル付きの格子で示す。ブックマーク状態は `BookmarkStore` から導出する。
///
/// 色はシステムのセマンティックカラーだけを使い（ダークモード対応）、文字はテキストスタイルだけで指定する（Dynamic Type）。
/// アクセシビリティサイズではヘッダー（`AdaptiveStack`）と統計を 1 列に並べ替える。
struct RepositoryDetailView: View {
    @Environment(BookmarkStore.self) private var bookmarkStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    let repository: Repository

    private var summary: RepositorySummary {
        RepositorySummary(repository, isBookmarked: bookmarkStore.isBookmarked(repository), locale: locale)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statsGrid
                bookmarkButton
            }
            .padding(20)
            // iPad や横向きで行が間延びしないよう読みやすい幅に収める
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .labelStyle(.compact)
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 旧データ由来の暫定 id を、検索結果から開いた実 id で置き換える（未登録・実 id 同士なら何もしない）
            bookmarkStore.resolveProvisionalID(with: repository)
        }
    }

    private var header: some View {
        AdaptiveStack(verticalAlignment: .top, horizontalSpacing: 16, verticalSpacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Label(summary.languageText, systemImage: RepositorySummary.languageSystemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// オーナーのアバター。装飾なので VoiceOver からは隠す。
    private var avatar: some View {
        AsyncImage(url: repository.owner.avatarURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Image(systemName: "person.crop.square.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(12)
            default:
                ProgressView()
            }
        }
        .frame(width: 72, height: 72)
        .background(.fill.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var statsGrid: some View {
        // アクセシビリティサイズでは 1 列。それ以外は幅に応じて 2 列以上
        let columns =
            dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 140), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(summary.stats) { stat in
                StatCell(stat: stat)
            }
        }
    }

    @ViewBuilder
    private var bookmarkButton: some View {
        if summary.isBookmarked {
            Button {
                bookmarkStore.remove(repository)
            } label: {
                Label("ブックマークから削除", systemImage: "bookmark.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Button {
                bookmarkStore.add(repository)
            } label: {
                Label("ブックマークに追加", systemImage: "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

/// 統計 1 項目のカード。ラベルと値を縦に並べ、VoiceOver には 1 要素として読ませる。
private struct StatCell: View {
    let stat: RepositorySummary.Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(stat.title, systemImage: stat.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(stat.valueText)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.accessibilityLabel)
    }
}
