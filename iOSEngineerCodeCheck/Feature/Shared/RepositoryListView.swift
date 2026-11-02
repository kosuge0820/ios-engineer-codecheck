import SwiftUI

/// リポジトリの一覧。行をタップすると詳細へ遷移する。Search / Bookmark の両タブで使う。
struct RepositoryListView: View {
    let repositories: [Repository]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(repositories) { repository in
                    NavigationLink(value: repository) {
                        RepositoryRow(repository: repository)
                    }
                    // 既定のボタンスタイルではラベルがアクセント色になる。詳細画面のリポジトリ名と同じラベル色（ダーク対応）で描く
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            // 縦 ScrollView の幅は内容に従うため、0 件のときに overlay の文言が幅 0 にならないよう全幅にする
            .frame(maxWidth: .infinity)
        }
        .navigationDestination(for: Repository.self) { repository in
            RepositoryDetailView(repository: repository)
        }
    }
}

struct RepositoryRow: View {
    let repository: Repository

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(repository.fullName)

            Spacer(minLength: 16)

            Text(repository.language ?? "")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // .plain スタイルではラベルの余白がヒット領域に入らないため、行全体をタップできるようにする
        .contentShape(Rectangle())
    }
}
