import Foundation
import SwiftData

@Model
final class NotificationEvent {
    @Attribute(.unique) var id: String
    var repositoryID: Int64
    var releaseID: Int64
    var createdAt: Date
    var isDelivered: Bool

    init(id: String, repositoryID: Int64, releaseID: Int64, createdAt: Date = .now, isDelivered: Bool = false) {
        self.id = id
        self.repositoryID = repositoryID
        self.releaseID = releaseID
        self.createdAt = createdAt
        self.isDelivered = isDelivered
    }
}
