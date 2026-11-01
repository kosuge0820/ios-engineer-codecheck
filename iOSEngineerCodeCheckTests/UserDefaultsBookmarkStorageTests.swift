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

    @Test("旧キー data だけがある場合は読み込んで v1 に移し、旧キーを消す")
    func migratesLegacyDataOnce() throws {
        temporary.defaults.set(try Fixture.data("legacy-bookmarks-data"), forKey: UserDefaultsBookmarkStorage.legacyKey)

        let migrated = try storage.load()

        #expect(migrated.map(\.fullName) == ["swiftlang/swift", "example/design-docs"])
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

    @Test("v1 が壊れていれば throw し、データは消さない")
    func corruptedV1ThrowsAndKeepsData() throws {
        let garbage = Data("not json".utf8)
        temporary.defaults.set(garbage, forKey: UserDefaultsBookmarkStorage.currentKey)

        #expect(throws: BookmarkStorageError.self) {
            try storage.load()
        }
        #expect(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.currentKey) == garbage)
    }

    @Test("旧キーが壊れていれば throw し、旧キーは残す")
    func corruptedLegacyThrowsAndKeepsData() throws {
        let garbage = Data("[{\"fullName\": 1}]".utf8)
        temporary.defaults.set(garbage, forKey: UserDefaultsBookmarkStorage.legacyKey)

        #expect(throws: BookmarkStorageError.self) {
            try storage.load()
        }
        #expect(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.legacyKey) == garbage)
        #expect(temporary.defaults.data(forKey: UserDefaultsBookmarkStorage.currentKey) == nil)
    }

    @Test("暫定 id は fullName ごとに安定した負の値")
    func provisionalIDIsStableAndNegative() {
        let a = Repository.provisionalID(fullName: "swiftlang/swift")
        #expect(a < 0)
        #expect(a == Repository.provisionalID(fullName: "swiftlang/swift"))
        #expect(a != Repository.provisionalID(fullName: "openstack/swift"))
    }
}
