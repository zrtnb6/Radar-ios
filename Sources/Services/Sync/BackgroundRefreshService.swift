import Foundation
import BackgroundTasks
import OSLog

/// iOS 后台刷新：用 BGAppRefreshTask 让系统在合适时机唤醒 App 拉一次 Release。
///
/// 关键点：
/// - `register` 必须在 `didFinishLaunching` 之前完成，否则系统会拒绝注册；
/// - 每次执行完立即把下一次排进队列，否则后台刷新链路会断掉；
/// - `expirationHandler` 只负责让任务尽早收尾，完成回调保证只调用一次。
@MainActor
final class BackgroundRefreshService {
    static let shared = BackgroundRefreshService()
    static let taskIdentifier = "com.releaseradar.ios.refresh"

    private weak var syncService: SyncService?
    private let logger = Logger(subsystem: "com.releaseradar.ios", category: "Background")
    private var isRegistered = false

    private init() {}

    func attach(syncService: SyncService) {
        self.syncService = syncService
    }

    func register() {
        guard !isRegistered else { return }
        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                BackgroundRefreshService.shared.handle(refreshTask)
            }
        }
        if !isRegistered {
            logger.error("BGTaskScheduler 注册失败，后台刷新不可用")
        }
    }

    /// 按设置里的检查间隔排下一次后台刷新（系统最早 15 分钟后执行）。
    func scheduleNext() {
        guard UserDefaults.standard.bool(forKey: AppSettings.backgroundRefresh) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
            return
        }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)

        let hours = max(1, UserDefaults.standard.double(forKey: AppSettings.checkInterval))
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: max(15 * 60, hours * 3600 * 0.5))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("后台刷新排程失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        // 先把下一次排进队列，任务被取消也不会断链。
        scheduleNext()

        let completion = TaskCompletionGuard(task: task)
        let work = Task { @MainActor [weak self] in
            guard let self, let syncService = self.syncService else {
                completion.finish(success: false)
                return
            }
            await syncService.refresh()
            let success = syncService.lastSyncError == nil
            self.logger.info("后台刷新完成，success=\(success, privacy: .public)")
            completion.finish(success: success)
        }
        task.expirationHandler = {
            work.cancel()
            completion.finish(success: false)
        }
    }
}

/// BGTask 的完成回调只允许触发一次，超时与正常结束可能同时发生。
private final class TaskCompletionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private let task: BGAppRefreshTask

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}
