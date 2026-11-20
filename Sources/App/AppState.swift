import Foundation
import SwiftUI
import SwiftData
import Combine
import UserNotifications

enum RootTab: Hashable {
    case repositories
    case downloads
    case settings
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: RootTab = .repositories
    /// iPhone 上的导航栈：存放 Repository 的本地 id。
    @Published var repositoryPath: [Int64] = []
    /// iPad 分栏模式下选中的项目。
    @Published var selectedRepositoryID: Int64?
    @Published var showingAddRepository = false
    @Published var unreadCount = 0
    @Published var storageError: String?
    @Published var pendingReleaseID: Int64?
    @Published var toast: String?

    let container: ModelContainer
    let syncService: SyncService
    let scheduler: SyncScheduler
    let notificationService: NotificationService
    let downloadManager: DownloadManager
    let backgroundRefresh = BackgroundRefreshService.shared

    private var notificationTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private let initialRepositoryID: Int64?

    init(container suppliedContainer: ModelContainer? = nil, storageError: String? = nil) {
        AppSettings.registerDefaults()
        downloadManager = DownloadManager.shared

        let resolvedContainer: ModelContainer
        let resolvedError: String?
        if let suppliedContainer {
            resolvedContainer = suppliedContainer
            resolvedError = storageError
        } else {
            let persistence = PersistenceController.shared
            resolvedContainer = persistence.container
            resolvedError = persistence.storageError
        }
        container = resolvedContainer
        self.storageError = resolvedError

        if suppliedContainer == nil {
            DefaultRepository.seedIfNeeded(context: resolvedContainer.mainContext)
        }

        let notificationService = NotificationService()
        self.notificationService = notificationService
        let syncService = SyncService(modelContext: resolvedContainer.mainContext, notifications: notificationService)
        self.syncService = syncService
        scheduler = SyncScheduler(syncService: syncService)
        backgroundRefresh.attach(syncService: syncService)

        let repositories = (try? syncService.fetchRepositories()) ?? []
        initialRepositoryID = repositories.count == 1 ? repositories.first?.id : nil
        selectedRepositoryID = initialRepositoryID
        unreadCount = syncService.unreadCount()
        observeNotificationClicks()
        applyBadge()
    }

    // MARK: - Lifecycle

    func onAppear() {
        scheduler.start()
        Task {
            await scheduler.checkIfNeeded()
            updateUnreadCount()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            scheduler.start()
            downloadManager.refreshTasksFromSession()
            Task {
                await scheduler.checkIfNeeded()
                updateUnreadCount()
                applyBadge()
            }
        case .background:
            scheduler.stop()
            backgroundRefresh.scheduleNext()
            applyBadge()
        default:
            break
        }
    }

    // MARK: - Actions

    func refreshAll() async {
        await syncService.refresh()
        updateUnreadCount()
        if let error = syncService.lastSyncError {
            showToast(error)
        }
    }

    func refreshSelected() async {
        if let id = selectedRepositoryID ?? repositoryPath.last {
            await syncService.refresh(repositoryIDs: [id])
        } else {
            await syncService.refresh()
        }
        updateUnreadCount()
        if let error = syncService.lastSyncError {
            showToast(error)
        }
    }

    @discardableResult
    func addRepository(_ url: String) async throws -> AddRepositoryOutcome {
        let outcome = try await syncService.addRepository(urlString: url)
        switch outcome {
        case .added(let repository), .duplicate(let repository):
            open(repository)
        }
        updateUnreadCount()
        return outcome
    }

    func open(_ repository: Repository) {
        selectedRepositoryID = repository.id
        if repositoryPath.last != repository.id {
            repositoryPath.append(repository.id)
        }
    }

    func openRepository(id: Int64) {
        selectedRepositoryID = id
        if repositoryPath.last != id {
            repositoryPath.append(id)
        }
    }

    func deleteRepository(_ repository: Repository) {
        let deletedID = repository.id
        do {
            try syncService.delete(repository)
            repositoryPath.removeAll { $0 == deletedID }
            if selectedRepositoryID == deletedID { selectedRepositoryID = nil }
            updateUnreadCount()
            applyBadge()
            showToast("已删除 \(repository.fullName)")
        } catch {
            showToast("删除项目失败：\(error.localizedDescription)")
        }
    }

    func markRead(_ repository: Repository) {
        syncService.markRepositoryRead(repository)
        updateUnreadCount()
        applyBadge()
    }

    func updateUnreadCount() {
        unreadCount = syncService.unreadCount()
    }

    func requestNotificationPermission() async -> Bool {
        let granted = await notificationService.requestAuthorizationIfNeeded()
        if !granted {
            showToast("通知权限未开启，可在「设置 → 通知 → Radar」中打开")
        }
        return granted
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Deep link

    /// 支持 `radar://repo/owner/name` 与 `radar://https://github.com/owner/name`，
    /// 方便从 Safari、快捷指令或其他 App 直接跳到某个项目。
    func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "radar" else { return }
        let target: String?
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let query = components.queryItems?.first(where: { $0.name == "url" })?.value {
            target = query
        } else if url.host == "repo" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            target = path.isEmpty ? nil : "https://github.com/\(path)"
        } else {
            target = nil
        }
        guard let target else { return }
        selectedTab = .repositories
        Task {
            if let parsed = try? GitHubURLParser.parse(target),
               let existing = (try? syncService.fetchRepositories())?.first(where: {
                   $0.fullName.caseInsensitiveCompare(parsed.fullName) == .orderedSame
               }) {
                open(existing)
            } else {
                showToast("无法识别链接：\(target)")
            }
        }
    }

    // MARK: - Helpers

    func repository(id: Int64) -> Repository? {
        let descriptor = FetchDescriptor<Repository>(predicate: #Predicate { $0.id == id })
        return try? container.mainContext.fetch(descriptor).first
    }

    private func applyBadge() {
        let count = unreadCount
        Task { await notificationService.updateBadge(count) }
    }

    private func observeNotificationClicks() {
        notificationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: NotificationService.openReleaseNotification)
            for await notification in notifications {
                guard let self,
                      let repositoryString = notification.userInfo?["repositoryID"] as? String,
                      let repositoryID = Int64(repositoryString),
                      let releaseString = notification.userInfo?["releaseID"] as? String,
                      let releaseID = Int64(releaseString) else { continue }
                selectedTab = .repositories
                openRepository(id: repositoryID)
                pendingReleaseID = releaseID
                if let repository = repository(id: repositoryID) {
                    syncService.markRepositoryRead(repository)
                    updateUnreadCount()
                    applyBadge()
                }
            }
        }
    }
}

extension DownloadManager {
    /// iOS App 只有一个下载中心，用共享实例让通知、后台回调与界面拿到同一份任务。
    static let shared: DownloadManager = DownloadManager()
}
