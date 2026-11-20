import Foundation

struct GitHubRepositoryDTO: Decodable, Sendable {
    let id: Int64
    let name: String
    let fullName: String
    let description: String?
    let htmlURL: String
    let homepage: String?
    let stargazersCount: Int
    let forksCount: Int
    let language: String?
    let topics: [String]
    let createdAt: Date?
    let updatedAt: Date?
    let pushedAt: Date?
    let archived: Bool
    let owner: GitHubOwnerDTO

    enum CodingKeys: String, CodingKey {
        case id, name, description, homepage, language, topics, archived, owner
        case fullName = "full_name"
        case htmlURL = "html_url"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case pushedAt = "pushed_at"
    }
}

struct GitHubOwnerDTO: Decodable, Sendable {
    let login: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
    }
}

struct GitHubReleaseDTO: Decodable, Sendable {
    let id: Int64
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let publishedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let isDraft: Bool
    let isPrerelease: Bool
    let assets: [GitHubAssetDTO]

    enum CodingKeys: String, CodingKey {
        case id, name, body, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
    }
}

struct GitHubAssetDTO: Decodable, Sendable {
    let id: Int64
    let name: String
    let size: Int64
    let contentType: String
    let browserDownloadURL: String
    let createdAt: Date?
    let updatedAt: Date?
    let downloadCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, size
        case contentType = "content_type"
        case browserDownloadURL = "browser_download_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case downloadCount = "download_count"
    }
}

extension JSONDecoder {
    static func gitHubDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无效的 ISO 8601 日期：\(value)")
        }
        return decoder
    }
}
