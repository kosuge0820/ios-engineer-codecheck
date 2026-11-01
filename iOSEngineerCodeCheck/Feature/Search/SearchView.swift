import SwiftUI

/// 検索タブ。入力と結果一覧を描画し、検索の実行は `SearchModel` に委ねる。
struct SearchView: View {
    /// 初期実装がプレースホルダとして実値に入れていた文字列。初級-02 で TextField の prompt に置き換える。
    static let placeholderText = "GitHubのリポジトリを検索できるよー"

    @Environment(SearchModel.self) private var searchModel
    @FocusState.Binding var isSearchFieldFocused: Bool

    var body: some View {
        @Bindable var searchModel = searchModel

        RepositoryListView(repositories: repositories)
            .safeAreaInset(edge: .top) {
                TextField("", text: $searchModel.query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .focused($isSearchFieldFocused)
                    .onTapGesture {
                        if searchModel.query == Self.placeholderText {
                            searchModel.query = ""
                        }
                    }
                    .onSubmit {
                        submit()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .overlay {
                statusView
            }
            .onChange(of: searchModel.query) { _, newValue in
                if newValue.isEmpty {
                    searchModel.reset()
                }
            }
    }

    private var repositories: [Repository] {
        if case .loaded(let repositories) = searchModel.state {
            return repositories
        }
        return []
    }

    @ViewBuilder
    private var statusView: some View {
        switch searchModel.state {
        case .idle:
            Text(Self.placeholderText)
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView()
        case .loaded:
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

    private func submit() {
        if searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines) == Self.placeholderText {
            return
        }
        Task {
            await searchModel.search()
        }
    }
}
