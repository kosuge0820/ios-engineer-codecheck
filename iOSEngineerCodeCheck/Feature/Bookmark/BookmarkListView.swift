import SwiftUI

/// Bookmark タブ。`BookmarkStore` の一覧を描画するだけ。
struct BookmarkListView: View {
    @Environment(BookmarkStore.self) private var bookmarkStore

    var body: some View {
        RepositoryListView(repositories: bookmarkStore.bookmarks)
            .overlay {
                if bookmarkStore.bookmarks.isEmpty {
                    // 文言は初期実装のまま（取り違えの修正は初級-02）
                    Text("検索ボタンをタップして")
                        .foregroundStyle(.secondary)
                }
            }
    }
}
