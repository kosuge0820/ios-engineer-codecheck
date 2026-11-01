//
//  iOSEngineerCodeCheckApp.swift
//  iOSEngineerCodeCheck
//

import SwiftUI

@main
struct iOSEngineerCodeCheckApp: App {
    /// 本番の依存はここで組み立てる。テストは `RepositorySearching` / `BookmarkStoring` をスタブに差し替える。
    @State private var searchModel = SearchModel(searcher: GitHubSearchClient())
    @State private var bookmarkStore = BookmarkStore(storage: UserDefaultsBookmarkStorage(defaults: .standard))

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(searchModel)
                .environment(bookmarkStore)
        }
    }
}
