import Foundation
import SwiftData

@Model
final class Release {
    @Attribute(.unique) var id: Int64
    var repositoryID: Int64
    var tagName: String
    var name: String?
    var body: String?
    var htmlURL: String
    var publishedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var isDraft: Bool
    var isPrerelease: Bool
    var detectedAt: Date
    var isRead: Bool

    init(
        id: Int64,
        repositoryID: Int64,
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        htmlURL: String,
        publishedAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        isDraft: Bool = false,
        isPrerelease: Bool = false,
        detectedAt: Date = .now,
        isRead: Bool = false
    ) {
        self.id = id
        self.repositoryID = repositoryID
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.detectedAt = detectedAt
        self.isRead = isRead
    }

    var displayTitle: String {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return tagName
        }
        return name
    }

    var sortDate: Date {
        publishedAt ?? createdAt ?? .distantPast
    }

    var notes: String? {
        guard let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return body
    }
}
