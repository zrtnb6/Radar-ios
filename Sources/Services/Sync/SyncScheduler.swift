import Foundation

/// 前台定时检查：App 在前台时每 5 分钟看一次「是否到检查时间」。
/// 真正的后台唤醒交给 `BackgroundRefreshService`（BGAppRefreshTask），
/// 移动端不做常驻轮询，避免无谓的电量与流量消耗。
@MainActor
final class SyncScheduler: ObservableObject {
    private let syncService: SyncService
    private var loop: Task<Void, Never>?

    init(syncService: SyncService) {
        self.syncService = syncService
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkIfNeeded()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// 到间隔才刷新；`force` 用于下拉刷新与前台回到活跃态。
    func checkIfNeeded(force: Bool = false) async {
        guard UserDefaults.standard.bool(forKey: AppSettings.automaticChecks) else { return }
        guard !syncService.isRefreshing else { return }
        if let retryAt = syncService.rateLimitNotBefore, retryAt > .now { return }

        let repositories = (try? syncService.fetchRepositories()) ?? []
        let monitored = repositories.filter { repository in
            !repository.isIgnored
                && !(UserDefaults.standard.bool(forKey: AppSettings.ignoreArchived) && repository.isArchived)
        }
        guard !monitored.isEmpty else { return }

        if force {
            await syncService.refresh()
            return
        }

        let interval = max(1, UserDefaults.standard.double(forKey: AppSettings.checkInterval)) * 3600
        let needsCheck = monitored.contains { repository in
            guard let lastCheckedAt = repository.lastCheckedAt else { return true }
            return Date().timeIntervalSince(lastCheckedAt) >= interval
        }
        if needsCheck {
            await syncService.refresh()
        }
    }
}
