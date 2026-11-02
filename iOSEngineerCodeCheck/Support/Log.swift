import Foundation
import os

/// 失敗を握り潰さず記録するためのロガー。Console.app でサブシステム名で絞り込める。
///
/// 文字列の補間は既定で `<private>` に伏せられるため、エラーの説明やキー名など個人情報を含まない値には
/// `privacy: .public` を付ける。検索語そのものはログに出さない。
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "jp.yumemi.iOSEngineerCodeCheck"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let search = Logger(subsystem: subsystem, category: "search")
}
