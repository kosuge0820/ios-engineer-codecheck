import Foundation
import Synchronization

/// `URLSession` の応答を固定する `URLProtocol`。クエリ `q` の値ごとにステータスと本文、または通信エラーを登録する。
final class StubURLProtocol: URLProtocol {
    enum Scripted: Sendable {
        case response(status: Int, body: Data)
        case failure(URLError)
    }

    private struct State {
        var scripted: [String: Scripted] = [:]
        var requestedURLs: [URL] = []
    }

    private static let state = Mutex(State())

    static func register(query: String, status: Int, body: Data) {
        state.withLock { $0.scripted[query] = .response(status: status, body: body) }
    }

    static func registerFailure(query: String, error: URLError) {
        state.withLock { $0.scripted[query] = .failure(error) }
    }

    static var requestedURLs: [URL] {
        state.withLock { $0.requestedURLs }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let query = queryItems?.first { $0.name == "q" }?.value ?? ""
        let scripted = Self.state.withLock { state -> Scripted? in
            state.requestedURLs.append(url)
            return state.scripted[query]
        }

        switch scripted {
        case .response(let status, let body):
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json; charset=utf-8"]
            )
            guard let response else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
        }
    }

    override func stopLoading() {}
}
