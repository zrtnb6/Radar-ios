import Foundation

enum GitHubEndpoint {
    static let baseURL = URL(string: "https://api.github.com")!

    static func repository(owner: String, name: String) -> URL {
        baseURL.appending(path: "repos/\(owner)/\(name)")
    }

    static func releases(owner: String, name: String, page: Int = 1, perPage: Int = 30) -> URL {
        var components = URLComponents(url: repository(owner: owner, name: name).appending(path: "releases"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "page", value: String(page))
        ]
        return components.url!
    }

    /// 该端点不计入 GitHub 速率限制，用于校验令牌是否生效并读取实时配额。
    static func rateLimit() -> URL {
        baseURL.appending(path: "rate_limit")
    }
}
