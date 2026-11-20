import Foundation

enum GitHubError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case repositoryNotFound
    case privateOrForbidden
    case unauthorized
    case rateLimited(retryAt: Date?)
    case serverError(Int)
    case decodingFailed
    case network(String)

    private static let tokenHint =
        "未配置 GitHub 令牌时同一 IP 每小时仅 60 次请求；可在「设置 → GitHub 令牌」中配置令牌，将限额提升至最高 5000 次/小时。"

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "请输入有效的 GitHub 仓库链接。"
        case .invalidResponse:
            return "GitHub 返回了无法识别的响应。"
        case .repositoryNotFound:
            return "未找到该仓库，请检查链接是否正确。"
        case .privateOrForbidden:
            return "无法访问该仓库。它可能是私有仓库，或当前访问被拒绝。"
        case .unauthorized:
            return "GitHub 令牌无效或已过期，请在「设置 → GitHub 令牌」中更新。"
        case .rateLimited(let retryAt):
            if let retryAt {
                return "GitHub API 已限流，预计 \(AppFormatters.releaseDate(retryAt)) 恢复。\(Self.tokenHint)"
            }
            return "GitHub API 已限流，请稍后重试。\(Self.tokenHint)"
        case .serverError(let code):
            return "GitHub 服务暂时异常（HTTP \(code)），缓存数据已保留。"
        case .decodingFailed:
            return "无法解析 GitHub 返回的数据。"
        case .network(let message):
            return "网络请求失败：\(message)"
        }
    }
}

extension Error {
    var userFacingMessage: String {
        if let error = self as? GitHubError {
            return error.errorDescription ?? "发生未知错误。"
        }
        if let error = self as? URLError {
            switch error.code {
            case .timedOut:
                return "网络请求超时，请检查连接后重试。"
            case .cannotFindHost, .dnsLookupFailed:
                return "无法解析 GitHub 域名，请检查网络或 DNS 设置。"
            case .notConnectedToInternet:
                return "当前网络不可用，请联网后重试。"
            default:
                return "网络请求失败：\(error.localizedDescription)"
            }
        }
        return localizedDescription
    }
}
