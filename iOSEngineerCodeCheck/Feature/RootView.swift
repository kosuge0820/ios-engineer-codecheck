import SwiftUI

/// Bookmark / Search の 2 タブ。状態は環境から受け取った `SearchModel` と `BookmarkStore` が所有する。
struct RootView: View {
    private enum Tab: Hashable {
        case bookmark
        case search
    }

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
            guard newValue == .search else {
                isSearchFieldFocused = false
                return
            }
            // タブ切替直後はまだ TextField が表示されていないので、少し待ってからフォーカスする
            Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return // キャンセル時はフォーカスしない
                }
                isSearchFieldFocused = true
            }
        }
    }
}

#Preview {
    RootView()
        .environment(SearchModel(searcher: GitHubSearchClient()))
        .environment(BookmarkStore(storage: UserDefaultsBookmarkStorage(defaults: .standard)))
}
