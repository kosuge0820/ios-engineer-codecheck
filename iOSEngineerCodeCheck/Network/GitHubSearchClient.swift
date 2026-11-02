import Foundation

/// `URLSession` で GitHub Search API を呼ぶ `RepositorySearching` 実装。
///
/// HTTP ステータスを検証してからデコードし、失敗は `GitHubSearchError` として返す。
struct GitHubSearchClient: RepositorySearching {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String) async throws(GitHubSearchError) -> SearchResponse {
        let request = try makeRequest(query: query)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            Log.network.error("検索リクエストに失敗: \(error.code.rawValue) \(error.localizedDescription, privacy: .public)")
            throw .network(error)
        } catch {
            Log.network.error("検索リクエストに失敗（URLError 以外）: \(String(describing: error), privacy: .public)")
            throw .network(URLError(.unknown))
        }

        guard let http = response as? HTTPURLResponse else {
            Log.network.error("HTTP 応答ではない: \(String(describing: type(of: response)), privacy: .public)")
            throw .invalidResponse("HTTP 応答ではない")
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(SearchResponse.self, from: data)
            } catch {
                Log.network.error("検索応答のデコードに失敗: \(String(describing: error), privacy: .public)")
                throw .invalidResponse(String(describing: error))
            }
        case 403, 429:
            Log.network.notice("レート制限 (HTTP \(http.statusCode)): \(Self.errorMessage(from: data), privacy: .public)")
            throw .rateLimited
        case 422:
            let message = Self.errorMessage(from: data)
            Log.network.notice("クエリが拒否された (HTTP 422): \(message, privacy: .public)")
            throw .invalidQuery(message: message)
        default:
            Log.network.error("想定外のステータス: HTTP \(http.statusCode)")
            throw .unexpectedStatus(http.statusCode)
        }
    }

    /// クエリ値にそのまま残してよい文字。
    ///
    /// `URLComponents.queryItems` は RFC 3986 でクエリに許される `+` `&` `=` を符号化しないが、
    /// GitHub はクエリ文字列の `+` を空白、`&` `=` を区切りとして解釈するため、これらは必ず符号化する。
    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return allowed
    }()

    private func makeRequest(query: String) throws(GitHubSearchError) -> URLRequest {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) else {
            throw .invalidQuery(message: "検索語を URL 用に符号化できません: \(query)")
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/search/repositories"
        components.percentEncodedQueryItems = [URLQueryItem(name: "q", value: encodedQuery)]

        guard let url = components.url else {
            throw .invalidQuery(message: "URL を構築できません: \(query)")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    /// GitHub のエラー本文 `{"message": ..., "errors": [{"message": ...}]}` から表示用メッセージを組み立てる。
    private static func errorMessage(from data: Data) -> String {
        struct ErrorBody: Decodable {
            struct Detail: Decodable {
                let message: String?
            }
            let message: String
            let errors: [Detail]?
        }
        let body: ErrorBody
        do {
            body = try JSONDecoder().decode(ErrorBody.self, from: data)
        } catch {
            // エラー本文が想定形式でなくても呼び出し元の分岐（ステータス別）は変わらないので、先頭だけを文言にする
            Log.network.debug("エラー本文を解釈できない: \(String(describing: error), privacy: .public)")
            return String(decoding: data.prefix(200), as: UTF8.self)
        }
        let details = (body.errors ?? []).compactMap(\.message)
        return details.isEmpty ? body.message : "\(body.message): \(details.joined(separator: " "))"
    }
}
