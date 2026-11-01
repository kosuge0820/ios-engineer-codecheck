import SwiftUI

/// Bookmark タブ。`BookmarkStore` の一覧を描画するだけ。
struct BookmarkListView: View {
    @Environment(BookmarkStore.self) private var bookmarkStore

    var body: some View {
        RepositoryListView(repositories: bookmarkStore.bookmarks)
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
                    // 文言は初期実装のまま（取り違えの修正は初級-02）
                    Text("検索ボタンをタップして")
                        .foregroundStyle(.secondary)
                }
            }
    }
}
