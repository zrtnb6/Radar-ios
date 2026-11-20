import Foundation
import SwiftData
import OSLog

enum AddRepositoryOutcome {
    case added(Repository)
    case duplicate(Repository)
}

@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var isRefreshing = false
    @Published var lastSyncError: String?
    /// 最后一次成功刷新的时间，用于列表页展示「刚刚检查过」。
    @Published private(set) var lastSuccessAt: Date?
    private(set) var rateLimitNotBefore: Date?

    let modelContext: ModelContext
    private let client: any GitHubFetching
    private let notifications: any NotificationSending
    private let logger = Logger(subsystem: "com.releaseradar.ios", category: "Sync")

    init(
        modelContext: ModelContext,
        client: any GitHubFetching = GitHubClient(),
        notifications: any NotificationSending = NotificationService()
    ) {
        self.modelContext = modelContext
        self.client = client
        self.notifications = notifications
        self.lastSuccessAt = try? fetchRepositories().compactMap(\.lastCheckedAt).max()
    }

    // MARK: - Add / delete

    func addRepository(urlString: String) async throws -> AddRepositoryOutcome {
        let parsed = try GitHubURLParser.parse(urlString)
        let repositoryDTO = try await client.fetchRepository(owner: parsed.owner, name: parsed.repository)

        let allRepositories = try fetchRepositories()
        if let existing = allRepositories.first(where: {
            $0.id == repositoryDTO.id || $0.fullName.caseInsensitiveCompare(repositoryDTO.fullName) == .orderedSame
        }) {
            return .duplicate(existing)
        }

        let releases = try await client.fetchReleases(owner: parsed.owner, name: parsed.repository)
        let repository = Repository(
            id: repositoryDTO.id,
            owner: repositoryDTO.owner.login,
            name: repositoryDTO.name,
            fullName: repositoryDTO.fullName,
            url: repositoryDTO.htmlURL
        )
        modelContext.insert(repository)
        update(repository, from: repositoryDTO)
        _ = applyReleases(releases, to: repository, isBaseline: true)
        repository.lastCheckedAt = .now
        repository.lastError = nil
        try modelContext.save()
        return .added(repository)
    }

    func delete(_ repository: Repository) throws {
        let repositoryID = repository.id
        let releases = try fetchReleases(for: repositoryID)
        let releaseIDs = Set(releases.map(\.id))
        let assets = try modelContext.fetch(FetchDescriptor<Asset>()).filter { releaseIDs.contains($0.releaseID) }
        let events = try modelContext.fetch(FetchDescriptor<NotificationEvent>()).filter { $0.repositoryID == repositoryID }
        assets.forEach(modelContext.delete)
        events.forEach(modelContext.delete)
        releases.forEach(modelContext.delete)
        modelContext.delete(repository)
        try modelContext.save()
    }

    // MARK: - Refresh

    func refresh(repositoryIDs: [Int64]? = nil) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastSyncError = nil
        rateLimitNotBefore = nil

        do {
            let ignoreArchived = UserDefaults.standard.bool(forKey: AppSettings.ignoreArchived)
            var repositories = try fetchRepositories().filter { !$0.isIgnored }
            if let repositoryIDs {
                let ids = Set(repositoryIDs)
                repositories = repositories.filter { ids.contains($0.id) }
            }
            if ignoreArchived {
                repositories = repositories.filter { !$0.isArchived }
            }
            guard !repositories.isEmpty else { return }

            var pendingNotifications: [PendingNotification] = []
            let client = self.client
            // 移动网络下控制并发：每批 3 个仓库，单仓库失败只影响自己。
            for start in stride(from: 0, to: repositories.count, by: 3) {
                let batch = Array(repositories[start..<min(start + 3, repositories.count)])
                let results = await withTaskGroup(of: FetchResult.self, returning: [FetchResult].self) { group in
                    for repository in batch {
                        group.addTask {
                            do {
                                let snapshot = try await client.fetchSnapshot(owner: repository.owner, name: repository.name)
                                return FetchResult(repositoryID: repository.id, snapshot: snapshot, failure: nil)
                            } catch {
                                let retryAt: Date?
                                if case GitHubError.rateLimited(let date) = error { retryAt = date } else { retryAt = nil }
                                return FetchResult(
                                    repositoryID: repository.id,
                                    snapshot: nil,
                                    failure: FetchFailure(message: error.userFacingMessage, retryAt: retryAt)
                                )
                            }
                        }
                    }
                    var results: [FetchResult] = []
                    for await result in group { results.append(result) }
                    return results
                }

                for result in results {
                    guard let repository = repositories.first(where: { $0.id == result.repositoryID }) else { continue }
                    // 首次检查只建立基线：历史 Release 全部视为已读，不推送通知。
                    let isFirstCheck = repository.lastCheckedAt == nil
                    repository.lastCheckedAt = .now
                    if let failure = result.failure {
                        repository.lastError = failure.message
                        lastSyncError = failure.message
                        if let retryAt = failure.retryAt {
                            rateLimitNotBefore = max(rateLimitNotBefore ?? .distantPast, retryAt)
                        }
                        continue
                    }
                    guard let snapshot = result.snapshot else { continue }
                    update(repository, from: snapshot.repository)
                    repository.lastError = nil
                    pendingNotifications.append(contentsOf: applyReleases(snapshot.releases, to: repository, isBaseline: isFirstCheck))
                }
            }

            try modelContext.save()
            lastSuccessAt = .now

            for pending in pendingNotifications {
                let delivered: Bool
                switch pending.kind {
                case .newRelease:
                    guard UserDefaults.standard.bool(forKey: AppSettings.newReleaseNotifications) else { continue }
                    delivered = await notifications.sendNewRelease(
                        repository: pending.repository,
                        release: pending.release,
                        hasIPA: pending.hasIPA
                    )
                case .assetChange:
                    guard UserDefaults.standard.bool(forKey: AppSettings.assetChangeNotifications) else { continue }
                    delivered = await notifications.sendAssetChange(
                        repository: pending.repository,
                        release: pending.release,
                        hasIPA: pending.hasIPA
                    )
                }
                pending.event.isDelivered = delivered
            }
            try modelContext.save()
        } catch {
            lastSyncError = "同步或保存数据失败：\(error.localizedDescription)"
            logger.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reads

    func fetchRepositories() throws -> [Repository] {
        try modelContext.fetch(FetchDescriptor<Repository>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))
    }

    func fetchReleases(for repositoryID: Int64) throws -> [Release] {
        try modelContext.fetch(FetchDescriptor<Release>(
            predicate: #Predicate { $0.repositoryID == repositoryID },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        ))
    }

    func fetchAssets(for releaseID: Int64) throws -> [Asset] {
        try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.releaseID == releaseID },
            sortBy: [SortDescriptor(\.name)]
        ))
    }

    func latestRelease(for repository: Repository) throws -> Release? {
        guard let latestID = repository.latestReleaseID else {
            return try fetchReleases(for: repository.id).first
        }
        return try fetchReleases(for: repository.id).first { $0.id == latestID }
    }

    func assets(for release: Release) throws -> [Asset] {
        ReleaseDetector.orderedAssets(try fetchAssets(for: release.id))
    }

    /// 某个 Release 是否带 IPA（决定通知文案与「可安装」提示）。
    func hasIPA(release: Release) -> Bool {
        ((try? fetchAssets(for: release.id)) ?? []).contains(where: \.isIPA)
    }

    func markRepositoryRead(_ repository: Repository) {
        guard let latestID = repository.latestReleaseID,
              let release = try? fetchReleases(for: repository.id).first(where: { $0.id == latestID }) else { return }
        release.isRead = true
        try? modelContext.save()
    }

    func markReleaseRead(_ release: Release) {
        release.isRead = true
        try? modelContext.save()
    }

    func unreadCount() -> Int {
        let descriptor = FetchDescriptor<Release>(predicate: #Predicate { !$0.isRead && !$0.isDraft })
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Mutation helpers

    private func update(_ repository: Repository, from dto: GitHubRepositoryDTO) {
        repository.owner = dto.owner.login
        repository.name = dto.name
        repository.fullName = dto.fullName
        repository.url = dto.htmlURL
        repository.avatarURL = dto.owner.avatarURL
        repository.repositoryDescription = dto.description
        repository.homepage = dto.homepage
        repository.stars = dto.stargazersCount
        repository.forks = dto.forksCount
        repository.language = dto.language
        repository.topics = dto.topics
        repository.createdAt = dto.createdAt
        repository.updatedAt = dto.updatedAt
        repository.pushedAt = dto.pushedAt
        repository.isArchived = dto.archived
    }

    @discardableResult
    private func applyReleases(_ dtos: [GitHubReleaseDTO], to repository: Repository, isBaseline: Bool) -> [PendingNotification] {
        let includePrerelease = UserDefaults.standard.bool(forKey: AppSettings.monitorPrerelease)
        let existingReleases = (try? fetchReleases(for: repository.id)) ?? []
        var releaseMap = Dictionary(uniqueKeysWithValues: existingReleases.map { ($0.id, $0) })
        let previousLatest = existingReleases.first { $0.id == repository.latestReleaseID }
        let eligible = ReleaseDetector.eligibleReleases(from: dtos, includePrerelease: includePrerelease)
        let candidate = eligible.first
        let change = candidate.map { ReleaseDetector.detectChange(candidate: $0, current: previousLatest) } ?? .none

        let previousAssetIDs: Set<Int64>?
        if let candidate {
            let candidateID = candidate.id
            let assets = try? modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.releaseID == candidateID }))
            previousAssetIDs = assets.map { Set($0.map(\.id)) }
        } else {
            previousAssetIDs = nil
        }

        for dto in dtos where !dto.isDraft {
            let release: Release
            if let existing = releaseMap[dto.id] {
                release = existing
            } else {
                release = Release(id: dto.id, repositoryID: repository.id, tagName: dto.tagName, htmlURL: dto.htmlURL, isRead: isBaseline)
                modelContext.insert(release)
                releaseMap[dto.id] = release
            }
            release.tagName = dto.tagName
            release.name = dto.name
            release.body = dto.body
            release.htmlURL = dto.htmlURL
            release.publishedAt = dto.publishedAt
            release.createdAt = dto.createdAt
            release.updatedAt = dto.updatedAt
            release.isDraft = dto.isDraft
            release.isPrerelease = dto.isPrerelease
            if let candidate, dto.id == candidate.id, change != .none, !isBaseline {
                release.isRead = false
            }
            upsertAssets(dto.assets, for: release)
        }

        repository.latestReleaseID = candidate?.id
        guard !isBaseline, let candidate, let latestRelease = releaseMap[candidate.id] else { return [] }
        let candidateHasIPA = candidate.assets.contains { ReleaseDetector.isIPA(fileName: $0.name) }

        var pending: [PendingNotification] = []
        let existingEvents = (try? modelContext.fetch(FetchDescriptor<NotificationEvent>())) ?? []
        let eventIDs = Set(existingEvents.map(\.id))

        if change != .none {
            let eventID = "release:\(repository.id):\(candidate.id)"
            if !eventIDs.contains(eventID) {
                let event = NotificationEvent(id: eventID, repositoryID: repository.id, releaseID: candidate.id)
                modelContext.insert(event)
                pending.append(PendingNotification(
                    kind: .newRelease,
                    repository: repository,
                    release: latestRelease,
                    hasIPA: candidateHasIPA,
                    event: event
                ))
            }
        } else if let previousAssetIDs,
                  ReleaseDetector.assetsChanged(from: previousAssetIDs, to: candidate.assets) {
            let signature = candidate.assets.map(\.id).sorted().map(String.init).joined(separator: "-")
            let eventID = "assets:\(repository.id):\(candidate.id):\(signature)"
            if !eventIDs.contains(eventID) {
                let event = NotificationEvent(id: eventID, repositoryID: repository.id, releaseID: candidate.id)
                modelContext.insert(event)
                pending.append(PendingNotification(
                    kind: .assetChange,
                    repository: repository,
                    release: latestRelease,
                    hasIPA: candidateHasIPA,
                    event: event
                ))
            }
        }
        return pending
    }

    private func upsertAssets(_ dtos: [GitHubAssetDTO], for release: Release) {
        let existing = (try? fetchAssets(for: release.id)) ?? []
        let assetMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(dtos.map(\.id))
        for asset in existing where !incomingIDs.contains(asset.id) {
            modelContext.delete(asset)
        }
        for dto in dtos {
            let kind = AssetKind.detect(fileName: dto.name)
            let asset = assetMap[dto.id] ?? Asset(
                id: dto.id,
                releaseID: release.id,
                name: dto.name,
                size: dto.size,
                contentType: dto.contentType,
                downloadURL: dto.browserDownloadURL,
                kind: kind
            )
            if assetMap[dto.id] == nil { modelContext.insert(asset) }
            asset.name = dto.name
            asset.size = dto.size
            asset.contentType = dto.contentType
            asset.downloadURL = dto.browserDownloadURL
            asset.createdAt = dto.createdAt
            asset.updatedAt = dto.updatedAt
            asset.downloadCount = dto.downloadCount
            asset.kind = kind
        }
    }
}

private struct FetchResult: Sendable {
    let repositoryID: Int64
    let snapshot: GitHubSnapshot?
    let failure: FetchFailure?
}

private struct FetchFailure: Sendable {
    let message: String
    let retryAt: Date?
}

private struct PendingNotification {
    enum Kind { case newRelease, assetChange }
    let kind: Kind
    let repository: Repository
    let release: Release
    let hasIPA: Bool
    let event: NotificationEvent
}
