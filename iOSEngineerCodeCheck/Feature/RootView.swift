import SwiftUI

/// Bookmark / Search の 2 タブ。状態は環境から受け取った `SearchModel` と `BookmarkStore` が所有する。
struct RootView: View {
    private enum Tab: Hashable {
        case bookmark
        case search
    }

    @Environment(SearchModel.self) private var searchModel
    @State private var selectedTab = Tab.search
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                BookmarkListView()
                    .navigationTitle("Bookmarks")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "bookmark.fill")
                Text("Bookmark")
            }
            .tag(Tab.bookmark)

            NavigationStack {
                SearchView(isSearchFieldFocused: $isSearchFieldFocused)
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "magnifyingglass.circle.fill")
                Text("Search")
            }
            .tag(Tab.search)
        }
        .tint(.black)
        .background(.ultraThinMaterial)
        .onChange(of: selectedTab) { _, newValue in
            // 初期実装の挙動をそのまま移したもの（プレースホルダ文字列の扱いとフォーカスは初級-02 で見直す）
            if newValue == .search {
                if searchModel.query == SearchView.placeholderText {
                    searchModel.query = ""
                }
                Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        return // キャンセル時はフォーカスしない
                    }
                    isSearchFieldFocused = true
                }
            } else {
                isSearchFieldFocused = false
            }
        }
    }
}

#Preview {
    RootView()
        .environment(SearchModel(searcher: GitHubSearchClient()))
        .environment(BookmarkStore(storage: UserDefaultsBookmarkStorage(defaults: .standard)))
}
