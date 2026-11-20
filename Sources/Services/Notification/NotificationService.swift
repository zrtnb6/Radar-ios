import Foundation
import UserNotifications
import OSLog
import UIKit

protocol NotificationSending: AnyObject {
    func sendNewRelease(repository: Repository, release: Release, hasIPA: Bool) async -> Bool
    func sendAssetChange(repository: Repository, release: Release, hasIPA: Bool) async -> Bool
}

/// iOS 通知：前台也显示横幅，点按直接跳到对应 Release；
/// 同时维护 App 图标角标（未读 Release 数）。
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, NotificationSending, @unchecked Sendable {
    /// 点按通知时通过 NotificationCenter 广播，AppState 收到后切 Tab 并推进导航栈。
    static let openReleaseNotification = Notification.Name("RadarIOS.OpenRelease")

    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: "com.releaseradar.ios", category: "Notifications")

    override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        do {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                return true
            case .notDetermined:
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            case .denied:
                return false
            @unknown default:
                return false
            }
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func updateBadge(_ count: Int) async {
        do {
            try await center.setBadgeCount(max(0, count))
        } catch {
            logger.debug("Badge update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func sendNewRelease(repository: Repository, release: Release, hasIPA: Bool) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = repository.name
        content.subtitle = repository.fullName
        content.body = hasIPA
            ? "新版本 \(release.tagName)，已附带 IPA 安装包"
            : "新版本 \(release.tagName)，该版本暂无 IPA 附件"
        content.sound = .default
        content.threadIdentifier = "radar-new-releases"
        content.userInfo = ["repositoryID": String(repository.id), "releaseID": String(release.id)]
        return await deliver(content: content, identifier: "release-\(repository.id)-\(release.id)")
    }

    @discardableResult
    func sendAssetChange(repository: Repository, release: Release, hasIPA: Bool) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = repository.name
        content.subtitle = repository.fullName
        content.body = hasIPA
            ? "\(release.tagName) 的附件已更新，含新的 IPA"
            : "\(release.tagName) 的附件列表已更新"
        content.sound = .default
        content.threadIdentifier = "radar-asset-changes"
        content.userInfo = ["repositoryID": String(repository.id), "releaseID": String(release.id)]
        return await deliver(content: content, identifier: "assets-\(repository.id)-\(release.id)-\(UUID().uuidString)")
    }

    private func deliver(content: UNMutableNotificationContent, identifier: String) async -> Bool {
        guard UserDefaults.standard.bool(forKey: AppSettings.notificationsEnabled) else { return false }
        guard await requestAuthorizationIfNeeded() else { return false }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            logger.error("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let repositoryID = userInfo["repositoryID"] as? String,
           let releaseID = userInfo["releaseID"] as? String {
            NotificationCenter.default.post(
                name: Self.openReleaseNotification,
                object: nil,
                userInfo: ["repositoryID": repositoryID, "releaseID": releaseID]
            )
        }
        completionHandler()
    }
}
