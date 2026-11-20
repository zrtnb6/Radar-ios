import Foundation

enum AppSettings {
    static let automaticChecks = "automaticChecks"
    static let checkInterval = "checkInterval"
    static let backgroundRefresh = "backgroundRefresh"
    static let ignoreArchived = "ignoreArchived"
    static let monitorPrerelease = "monitorPrerelease"
    /// iOS 端默认只显示 IPA 附件：这是唯一能在设备上安装的格式。
    static let onlyIPA = "onlyIPA"
    static let notificationsEnabled = "notificationsEnabled"
    static let newReleaseNotifications = "newReleaseNotifications"
    static let assetChangeNotifications = "assetChangeNotifications"

    static let checkIntervalOptions: [Double] = [3, 6, 12, 24]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            automaticChecks: true,
            checkInterval: 6.0,
            backgroundRefresh: true,
            ignoreArchived: true,
            monitorPrerelease: false,
            onlyIPA: true,
            notificationsEnabled: true,
            newReleaseNotifications: true,
            assetChangeNotifications: false
        ])
    }

    static var checkIntervalLabel: (Double) -> String = { hours in
        hours < 1 ? "每 30 分钟" : "每 \(Int(hours)) 小时"
    }
}
