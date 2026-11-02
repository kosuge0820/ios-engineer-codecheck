import Foundation
import Testing
@testable import iOSEngineerCodeCheck

@Suite("UserDefaultsBookmarkStorage の保存形式と旧データ移行")
struct UserDefaultsBookmarkStorageTests {
    private let temporary: TemporaryDefaults
    private let storage: UserDefaultsBookmarkStorage

    init() throws {
        temporary = try TemporaryDefaults()
        storage = UserDefaultsBookmarkStorage(defaults: temporary.defaults)
    }

    @Test("何も保存されていなければ空")
    func emptyWhenNothingStored() throws {
        #expect(try storage.load().isEmpty)
    }

    @Test("save した内容を bookmarks.v1 から load できる")
    func roundTrip() throws {
        let repositories = [
            Repository.fixture(id: 1, fullName: "a/one", language: nil),
            Repository.fixture(id: 2, fullName: "b/two", language: "Swift"),
        ]

        try storage.save(repositories)

        #expect(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.currentKey) != nil)
        #expect(try storage.load() == repositories)
    }

    @Test("固定した v1 フィクスチャを読める（保存形式を変えたらキーを上げる）")
    func decodesFrozenV1Fixture() throws {
        // Fixtures/bookmarks-v1.json は出荷済みの bookmarks.v1 の形式を固定したもの（save() の出力と同じ内容）。
        // このテストが落ちたら BookmarkRecordV1 を直すのではなく、キーを bookmarks.v2 に上げて移行処理とテストを足す。
        temporary.defaults.set(try Fixture.data("bookmarks-v1"), forKey: UserDefaultsBookmarkStorage.currentKey)

        let loaded = try storage.load()

        let expected = [
            Repository(
                id: 44_838_949,
                fullName: "swiftlang/swift",
                language: "Swift",
                stargazersCount: 70530,
                watchersCount: 70530,
                forksCount: 10884,
                openIssuesCount: 9528,
                owner: Repository.Owner(
                    avatarURL: try #require(URL(string: "https://avatars.githubusercontent.com/u/42816656?v=4"))
                )
            ),
            Repository(
                id: 123_456_789,
                fullName: "example/design-docs",
                language: nil,
                stargazersCount: 12,
                watchersCount: 12,
                forksCount: 3,
                openIssuesCount: 1,
                owner: Repository.Owner(
                    avatarURL: try #require(URL(string: "https://avatars.githubusercontent.com/u/1?v=4"))
                )
            ),
        ]
        #expect(loaded == expected)
        #expect(loaded.allSatisfy { !$0.hasProvisionalID }, "v1 は GitHub の id を持つ")

        // encode 方向も固定する: 現行の save() が書く JSON はフィクスチャと同じ内容（language が nil ならキー省略）
        try storage.save(expected)
        let saved = try #require(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.currentKey))
        let savedObject = try JSONSerialization.jsonObject(with: saved) as? NSArray
        let fixtureObject = try JSONSerialization.jsonObject(with: Fixture.data("bookmarks-v1")) as? NSArray
        #expect(savedObject != nil)
        #expect(savedObject == fixtureObject, "save() の出力が変わった。bookmarks.v2 にキーを上げて移行を書く")
    }

    @Test("旧キー data だけがある場合は読み込んで v1 に移し、旧キーを消す")
    func migratesLegacyDataOnce() throws {
        temporary.defaults.set(try Fixture.data("legacy-bookmarks-data"), forKey: UserDefaultsBookmarkStorage.legacyKey)

        let migrated = try storage.load()

        #expect(
            migrated.map(\.fullName) == ["swiftlang/swift", "example/design-docs"],
            "旧アプリで Remove された項目（marked: false）は移行しない。marked 無しは移行する"
        )
        #expect(migrated.map(\.language) == ["Swift", nil])
        #expect(migrated[0].stargazersCount == 70529)
        #expect(migrated[0].owner.avatarURL.absoluteString == "https://avatars.githubusercontent.com/u/42816656?v=4")
        let allProvisional = migrated.allSatisfy { $0.hasProvisionalID }
        #expect(allProvisional, "旧データは GitHub の id を持たないので暫定 id になる")
        #expect(migrated[0].id == Repository.provisionalID(fullName: "swiftlang/swift"))

        #expect(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.legacyKey) == nil, "移行後は旧キーを消す")
        #expect(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.currentKey) != nil)
        #expect(try storage.load() == migrated, "2 回目は v1 から同じ内容を読む")
    }

    @Test("v1 が壊れていれば throw し、データは消さず退避キーにも複製する")
    func corruptedV1ThrowsAndKeepsData() throws {
        let garbage = Data("not json".utf8)
        temporary.defaults.set(garbage, forKey: UserDefaultsBookmarkStorage.currentKey)

        #expect(throws: BookmarkStorageError.self) {
            try storage.load()
        }
        #expect(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.currentKey) == garbage)
        let backupKey = UserDefaultsBookmarkStorage.unreadableBackupKey(for: UserDefaultsBookmarkStorage.currentKey)
        #expect(temporary.defaults.data(forKey: backupKey) == garbage, "次の save で上書きされる前に退避しておく")
    }

    @Test("v1 が壊れた状態で save しても、退避した元データは残る")
    func unreadableV1SurvivesSubsequentSave() throws {
        let garbage = Data("not json".utf8)
        temporary.defaults.set(garbage, forKey: UserDefaultsBookmarkStorage.currentKey)
        #expect(throws: BookmarkStorageError.self) {
            try storage.load()
        }

        try storage.save([.fixture(id: 1)])

        #expect(try storage.load() == [.fixture(id: 1)])
        let backupKey = UserDefaultsBookmarkStorage.unreadableBackupKey(for: UserDefaultsBookmarkStorage.currentKey)
        #expect(temporary.defaults.data(forKey: backupKey) == garbage)
    }

    @Test("既に退避データがあっても、新たに壊れたデータは別の退避キーに残す")
    func secondUnreadableBlobIsAlsoPreserved() throws {
        let currentKey = UserDefaultsBookmarkStorage.currentKey
        let firstBackupKey = UserDefaultsBookmarkStorage.unreadableBackupKey(for: currentKey)
        let older = Data("older garbage".utf8)
        let newer = Data("newer garbage".utf8)
        temporary.defaults.set(older, forKey: firstBackupKey)
        temporary.defaults.set(newer, forKey: UserDefaultsBookmarkStorage.currentKey)

        #expect(throws: BookmarkStorageError.self) {
            try storage.load()
        }

        #expect(temporary.defaults.data(forKey: firstBackupKey) == older, "先に退避したものは消さない")
        let secondBackupKey = UserDefaultsBookmarkStorage.unreadableBackupKey(for: currentKey, index: 2)
        #expect(temporary.defaults.data(forKey: secondBackupKey) == newer, "2 回目に壊れたデータも次の save で消えないよう残す")

        try storage.save([.fixture(id: 1)])
        #expect(temporary.defaults.data(forKey: firstBackupKey) == older)
        #expect(temporary.defaults.data(forKey: secondBackupKey) == newer)
    }

    @Test("旧キーが壊れていれば throw し、旧キーは残して退避キーにも複製する")
    func corruptedLegacyThrowsAndKeepsData() throws {
        let garbage = Data("[{\"fullName\": 1}]".utf8)
        temporary.defaults.set(garbage, forKey: UserDefaultsBookmarkStorage.legacyKey)

        #expect(throws: BookmarkStorageError.self) {
            try storage.load()
        }
        #expect(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.legacyKey) == garbage)
        #expect(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.currentKey) == nil)
        let backupKey = UserDefaultsBookmarkStorage.unreadableBackupKey(for: UserDefaultsBookmarkStorage.legacyKey)
        #expect(temporary.defaults.data(forKey: backupKey) == garbage)
    }

    @Test("旧キーの avatarUrl が URL として不正でも throw し、退避する")
    func legacyWithInvalidAvatarURLThrowsAndPreserves() throws {
        let invalid = Data(
            """
            [{"fullName": "a/b", "language": null, "stargazersCount": 1, "watchersCount": 1,
              "forksCount": 0, "openIssuesCount": 0, "owner": {"avatarUrl": ""}}]
            """.utf8
        )
        temporary.defaults.set(invalid, forKey: UserDefaultsBookmarkStorage.legacyKey)

        #expect(throws: BookmarkStorageError.self) {
            try storage.load()
        }
        #expect(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.legacyKey) == invalid)
        let backupKey = UserDefaultsBookmarkStorage.unreadableBackupKey(for: UserDefaultsBookmarkStorage.legacyKey)
        #expect(temporary.defaults.data(forKey: backupKey) == invalid)
    }

    @Test("暫定 id は fullName ごとに安定した負の値")
    func provisionalIDIsStableAndNegative() {
        let a = Repository.provisionalID(fullName: "swiftlang/swift")
        #expect(a < 0)
        #expect(a == Repository.provisionalID(fullName: "swiftlang/swift"))
        #expect(a != Repository.provisionalID(fullName: "openstack/swift"))
    }
}
