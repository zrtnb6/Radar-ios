import Foundation
import SwiftData

@Model
final class Repository {
    @Attribute(.unique) var id: Int64
    var owner: String
    var name: String
    var fullName: String
    var url: String
    var avatarURL: String?
    var repositoryDescription: String?
    var homepage: String?
    var stars: Int
    var forks: Int
    var language: String?
    var topics: [String]
    var createdAt: Date?
    var updatedAt: Date?
    var pushedAt: Date?
    var isArchived: Bool
    var addedAt: Date
    var lastCheckedAt: Date?
    var lastError: String?
    var latestReleaseID: Int64?
    var isIgnored: Bool

    init(
        id: Int64,
        owner: String,
        name: String,
        fullName: String,
        url: String,
        avatarURL: String? = nil,
        repositoryDescription: String? = nil,
        homepage: String? = nil,
        stars: Int = 0,
        forks: Int = 0,
        language: String? = nil,
        topics: [String] = [],
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        pushedAt: Date? = nil,
        isArchived: Bool = false,
        addedAt: Date = .now,
        lastCheckedAt: Date? = nil,
        lastError: String? = nil,
        latestReleaseID: Int64? = nil,
        isIgnored: Bool = false
    ) {
        self.id = id
        self.owner = owner
        self.name = name
        self.fullName = fullName
        self.url = url
        self.avatarURL = avatarURL
        self.repositoryDescription = repositoryDescription
        self.homepage = homepage
        self.stars = stars
        self.forks = forks
        self.language = language
        self.topics = topics
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pushedAt = pushedAt
        self.isArchived = isArchived
        self.addedAt = addedAt
        self.lastCheckedAt = lastCheckedAt
        self.lastError = lastError
        self.latestReleaseID = latestReleaseID
        self.isIgnored = isIgnored
    }

    var displayDescription: String {
        guard let repositoryDescription,
              !repositoryDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "暂无项目描述"
        }
        return repositoryDescription
    }

    var avatarLink: URL? {
        avatarURL.flatMap(URL.safeHTTPS)
    }
}
