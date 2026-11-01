import Foundation
import Testing

/// テストごとに隔離した `UserDefaults`。破棄時にドメインごと削除するので端末設定に残らない。
final class TemporaryDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "iOSEngineerCodeCheckTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName), "UserDefaults(suiteName:) が nil")
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
