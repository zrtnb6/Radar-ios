import Foundation

/// `GET /rate_limit` 响应体。GitHub 同时返回 resources 与 rate，
/// 这里只读取与 REST 核心 API 对应的 `rate` 字段。
struct GitHubRateLimitDTO: Decodable, Sendable {
    let rate: Rate

    struct Rate: Decodable, Sendable {
        let limit: Int
        let used: Int
        let remaining: Int
        /// Unix 时间戳（秒）。GitHub 返回的是数字而非 ISO 8601 字符串。
        let reset: TimeInterval
    }
}

struct GitHubRateLimitStatus: Sendable, Equatable {
    let limit: Int
    let used: Int
    let remaining: Int
    let reset: Date

    /// GitHub 匿名请求为 60 次/小时，有效令牌认证后为核心 API 5000 次/小时。
    var isAuthenticated: Bool { limit > 60 }

    init(limit: Int, used: Int, remaining: Int, reset: Date) {
        self.limit = limit
        self.used = used
        self.remaining = remaining
        self.reset = reset
    }

    init(dto: GitHubRateLimitDTO) {
        self.init(
            limit: dto.rate.limit,
            used: dto.rate.used,
            remaining: dto.rate.remaining,
            reset: Date(timeIntervalSince1970: dto.rate.reset)
        )
    }
}
