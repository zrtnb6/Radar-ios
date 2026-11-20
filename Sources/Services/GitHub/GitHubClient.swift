import Foundation
import OSLog

struct GitHubSnapshot: Sendable {
    let repository: GitHubRepositoryDTO
    let releases: [GitHubReleaseDTO]
}

protocol GitHubFetching: Sendable {
    func fetchRepository(owner: String, name: String) async throws -> GitHubRepositoryDTO
    func fetchReleases(owner: String, name: String, page: Int, perPage: Int) async throws -> [GitHubReleaseDTO]
    func fetchSnapshot(owner: String, name: String) async throws -> GitHubSnapshot
}

extension GitHubFetching {
    func fetchReleases(owner: String, name: String) async throws -> [GitHubReleaseDTO] {
        try await fetchReleases(owner: owner, name: name, page: 1, perPage: 30)
    }
}

actor GitHubClient: GitHubFetching {
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?
    private let logger = Logger(subsystem: "com.releaseradar.ios", category: "GitHub")

    init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String? = { KeychainService.loadToken() }) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func fetchRepository(owner: String, name: String) async throws -> GitHubRepositoryDTO {
        try await send(GitHubEndpoint.repository(owner: owner, name: name))
    }

    func fetchReleases(owner: String, name: String, page: Int = 1, perPage: Int = 30) async throws -> [GitHubReleaseDTO] {
        try await send(GitHubEndpoint.releases(owner: owner, name: name, page: page, perPage: perPage))
    }

    func fetchSnapshot(owner: String, name: String) async throws -> GitHubSnapshot {
        async let repository = fetchRepository(owner: owner, name: name)
        async let releases = fetchReleases(owner: owner, name: name)
        return try await GitHubSnapshot(repository: repository, releases: releases)
    }

    /// 读取当前令牌对应的实时配额。该端点不计入速率限制，且强制绕过本地 URLCache，
    /// 保证「验证令牌」按钮每次拿到的都是 GitHub 的最新状态。
    func fetchRateLimit() async throws -> GitHubRateLimitStatus {
        let dto: GitHubRateLimitDTO = try await send(
            GitHubEndpoint.rateLimit(),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return GitHubRateLimitStatus(dto: dto)
    }

    private func send<T: Decodable>(
        _ url: URL,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> T {
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Radar-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("GitHub request failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder.gitHubDecoder().decode(T.self, from: data)
            } catch {
                logger.error("GitHub decoding failed: \(error.localizedDescription, privacy: .public)")
                throw GitHubError.decodingFailed
            }
        case 401:
            throw GitHubError.unauthorized
        case 404:
            throw GitHubError.repositoryNotFound
        case 403, 429:
            if http.statusCode == 429 || http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw GitHubError.rateLimited(retryAt: Self.retryDate(from: http))
            }
            throw GitHubError.privateOrForbidden
        case 500...599:
            throw GitHubError.serverError(http.statusCode)
        default:
            throw GitHubError.invalidResponse
        }
    }

    private static func retryDate(from response: HTTPURLResponse) -> Date? {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(retryAfter) {
                return Date().addingTimeInterval(max(0, seconds))
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: retryAfter) {
                return date
            }
        }
        if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let timestamp = TimeInterval(reset) {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }
}
