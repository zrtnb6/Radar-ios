import UIKit

@MainActor
final class RadarAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // BGTaskScheduler 必须在启动完成前注册，否则系统会拒绝该标识符。
        BackgroundRefreshService.shared.register()
        return true
    }

    /// 后台 URLSession 把控制权交回 App 时，必须持有 completion handler，
    /// 等所有事件处理完再调用，否则系统会认为后台会话异常。
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadManager.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        DownloadManager.shared.handleBackgroundEvents(completion: completionHandler)
    }
}
