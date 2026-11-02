import SwiftUI

/// 検索タブ。入力と結果一覧を描画し、検索の実行は `SearchModel` に委ねる。
struct SearchView: View {
    @Environment(SearchModel.self) private var searchModel
    @FocusState.Binding var isSearchFieldFocused: Bool

    var body: some View {
        @Bindable var searchModel = searchModel

        RepositoryListView(repositories: repositories) {
            loadMoreFooter
        }
        .safeAreaInset(edge: .top) {
            TextField("検索", text: $searchModel.query, prompt: Text("GitHub のリポジトリを検索"))
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)
                .onSubmit {
                    Task {
                        await searchModel.search()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .overlay {
            statusView
        }
        .onChange(of: searchModel.query) { _, newValue in
            // 入力を空にしたら結果を捨てる。進行中の検索もキャンセルされる
            if newValue.isEmpty {
                searchModel.reset()
            }
        }
    }

    private var repositories: [Repository] {
        searchModel.state.results?.items ?? []
    }

    /// 一覧末尾の追加読み込み操作。続きが無いとき・結果が無いときは何も出さない。
    @ViewBuilder
    private var loadMoreFooter: some View {
        switch searchModel.state {
        case .loaded(let results) where results.nextPage != nil:
            Button("さらに読み込む") {
                Task {
                    await searchModel.loadMore()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        case .loadingMore:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        case .loadMoreFailed(_, let error):
            VStack(spacing: 8) {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("再試行") {
                    Task {
                        await searchModel.loadMore()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        case .idle, .loading, .loaded, .empty, .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch searchModel.state {
        case .idle:
            Text("キーワードを入力して Search を押すと、GitHub のリポジトリを検索できます")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        case .loading:
            ProgressView()
        case .loaded, .loadingMore, .loadMoreFailed:
            EmptyView()
        case .empty:
            Text("該当するリポジトリがありません")
                .foregroundStyle(.secondary)
        case .failed(let error):
            Text(error.localizedDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
