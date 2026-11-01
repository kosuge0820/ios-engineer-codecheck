import Foundation
import Testing

/// `Fixtures/` 配下の JSON をテストバンドルから読み込む。
enum Fixture {
    private final class BundleLocator {}

    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleLocator.self)
        let url = try #require(
            bundle.url(forResource: name, withExtension: "json")
                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "フィクスチャ \(name).json がテストバンドルに見つからない"
        )
        return try Data(contentsOf: url)
    }
}
