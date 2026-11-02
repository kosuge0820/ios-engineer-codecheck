import SwiftUI

/// Bookmark タブ。`BookmarkStore` の一覧を描画するだけ。
struct BookmarkListView: View {
    @Environment(BookmarkStore.self) private var bookmarkStore

    var body: some View {
        RepositoryListView(repositories: bookmarkStore.bookmarks, showsBookmarkState: false)
            .safeAreaInset(edge: .top) {
                if bookmarkStore.failedToLoad {
                    Text("保存済みのブックマークを読み込めませんでした。読めなかったデータは退避してあり、新しいブックマークで上書きされることはありません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
            .overlay {
                if bookmarkStore.bookmarks.isEmpty {
                    Text("ブックマークはまだありません")
                        .foregroundStyle(.secondary)
                }
            }
    }
}
