import SwiftUI

/// リポジトリ詳細。ブックマーク状態は `BookmarkStore` から導出し、ボタンは同じストアを更新する。
struct RepositoryDetailView: View {
    @Environment(BookmarkStore.self) private var bookmarkStore

    let repository: Repository

    private var languageDescription: String {
        repository.language.map { "Written in \($0)" } ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                AsyncImage(url: repository.owner.avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "person.crop.square")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                            .padding(48)
                    default:
                        ProgressView()
                    }
                }
                .frame(maxWidth: 360, maxHeight: 360)
                .frame(maxWidth: .infinity)

                Text(repository.fullName)
                    .font(.title)
                    .multilineTextAlignment(.center)

                HStack(alignment: .top) {
                    Text(languageDescription)
                        .font(.headline)

                    Spacer(minLength: 24)

                    VStack(alignment: .trailing, spacing: 16) {
                        Text("\(repository.stargazersCount) stars")
                        Text("\(repository.watchersCount) watchers")
                        Text("\(repository.forksCount) forks")
                        Text("\(repository.openIssuesCount) open issues")
                    }
                    .font(.subheadline)
                }

                bookmarkButton
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 旧データ由来の暫定 id を、検索結果から開いた実 id で置き換える（未登録・実 id 同士なら何もしない）
            bookmarkStore.resolveProvisionalID(with: repository)
        }
    }

    @ViewBuilder
    private var bookmarkButton: some View {
        if bookmarkStore.isBookmarked(repository) {
            Button("Remove from Bookmark") {
                bookmarkStore.remove(repository)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else {
            Button("Add to Bookmark") {
                bookmarkStore.add(repository)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }
}
