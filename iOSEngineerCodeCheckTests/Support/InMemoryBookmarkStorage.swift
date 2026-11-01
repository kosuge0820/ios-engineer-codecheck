import Foundation
import Synchronization
@testable import iOSEngineerCodeCheck

/// 永続化を差し替えるスタブ。読み込み失敗・保存失敗を注入でき、保存回数と内容を観察できる。
final class InMemoryBookmarkStorage: BookmarkStoring {
    private struct State {
        var stored: [Repository]
        var saveCount = 0
        var failsOnLoad: Bool
        var failsOnSave: Bool
    }

    private let state: Mutex<State>

    init(stored: [Repository] = [], failsOnLoad: Bool = false, failsOnSave: Bool = false) {
        state = Mutex(State(stored: stored, failsOnLoad: failsOnLoad, failsOnSave: failsOnSave))
    }

    var stored: [Repository] { state.withLock { $0.stored } }
    var saveCount: Int { state.withLock { $0.saveCount } }

    func load() throws -> [Repository] {
        try state.withLock { state in
            if state.failsOnLoad {
                throw BookmarkStorageError.corruptedData(key: "in-memory", reason: "テストで注入した読み込み失敗")
            }
            return state.stored
        }
    }

    func save(_ repositories: [Repository]) throws {
        try state.withLock { state in
            state.saveCount += 1
            if state.failsOnSave {
                throw BookmarkStorageError.writeFailed(key: "in-memory", reason: "テストで注入した保存失敗")
            }
            state.stored = repositories
        }
    }
}
