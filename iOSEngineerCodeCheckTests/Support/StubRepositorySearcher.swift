import Foundation
import Testing
@testable import iOSEngineerCodeCheck

/// 通信を差し替えるスタブ。応答内容・エラー・完了順序・遅延をテスト側から制御できる。
///
/// - 既定では `enqueue` した結果を呼び出し順に返す。
/// - `hold()` 後は `search` が保留され、`resume(call:with:)` で任意の順に完了させられる。
actor StubRepositorySearcher: RepositorySearching {
    typealias Outcome = Result<SearchResponse, GitHubSearchError>

    private var scripted: [Outcome]
    private var holding = false
    private var pending: [Int: CheckedContinuation<Outcome, Never>] = [:]
    private var earlyOutcomes: [Int: Outcome] = [:]
    private(set) var receivedQueries: [String] = []

    init(outcomes: [Outcome] = []) {
        scripted = outcomes
    }

    func enqueue(_ outcome: Outcome) {
        scripted.append(outcome)
    }

    /// 以降の `search` を `resume` まで保留する。
    func hold() {
        holding = true
    }

    /// `call` 番目（0 始まり）の保留中呼び出しを完了させる。まだ呼ばれていなければ到着時に即適用する。
    func resume(call: Int, with outcome: Outcome) {
        if let continuation = pending.removeValue(forKey: call) {
            continuation.resume(returning: outcome)
        } else {
            earlyOutcomes[call] = outcome
        }
    }

    /// `search` が `count` 回呼ばれるまで待つ。`timeout` を過ぎたら Issue として記録して戻る（テストをハングさせない）。
    func waitForCalls(_ count: Int, timeout: Duration = .seconds(5)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while receivedQueries.count < count {
            if clock.now >= deadline {
                Issue.record("StubRepositorySearcher: search が \(count) 回呼ばれるのを \(timeout) 待ったが \(receivedQueries.count) 回だった")
                return
            }
            await Task.yield()
        }
    }

    func search(query: String) async throws(GitHubSearchError) -> SearchResponse {
        let callIndex = receivedQueries.count
        receivedQueries.append(query)

        let outcome: Outcome
        if holding {
            if let early = earlyOutcomes.removeValue(forKey: callIndex) {
                outcome = early
            } else {
                outcome = await withCheckedContinuation { continuation in
                    pending[callIndex] = continuation
                }
            }
        } else if !scripted.isEmpty {
            outcome = scripted.removeFirst()
        } else {
            outcome = .failure(.invalidResponse("StubRepositorySearcher: 応答が用意されていない"))
        }
        return try outcome.get()
    }
}
