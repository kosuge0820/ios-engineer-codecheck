import SwiftUI

/// Bookmark / Search の 2 タブ。状態は環境から受け取った `SearchModel` と `BookmarkStore` が所有する。
struct RootView: View {
    private enum Tab: Hashable {
        case bookmark
        case search
    }

    @State private var selectedTab = Tab.search
    @FocusState private var isSearchFieldFocused: Bool
    /// タブ切替後の遅延フォーカス。別タブへ戻ったらキャンセルし、Bookmark タブ表示中に検索欄へフォーカスが移らないようにする。
    @State private var focusTask: Task<Void, Never>?

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
        .onChange(of: selectedTab) { _, newValue in
            focusTask?.cancel()
            focusTask = nil
            guard newValue == .search else {
                isSearchFieldFocused = false
                return
            }
            // タブ切替直後はまだ TextField が表示されていないので、少し待ってからフォーカスする
            focusTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return  // 待機中に別タブへ移ったらフォーカスしない
                }
                guard selectedTab == .search else { return }
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
