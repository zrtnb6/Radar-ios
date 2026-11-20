import Foundation
import OSLog

struct DownloadItem: Identifiable, Equatable {
    enum State: String, Equatable {
        case downloading
        case completed
        case failed
        case cancelled
    }

    let id: Int64
    let assetName: String
    let kind: AssetKind
    let startedAt: Date
    var receivedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var state: State = .downloading
    var localURL: URL?
    var errorMessage: String?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
    }

    var progressSummary: String {
        let received = ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)
        guard totalBytes > 0 else { return received }
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(received) / \(total)"
    }

    var isIPA: Bool { kind == .ipa }
}

/// iOS 端下载器：把附件拉到 App 沙盒的 `Documents/Downloads`。
///
/// 移动端的几个额外处理：
/// - 使用 **background URLSession**，App 进入后台或被系统挂起时下载继续，回到前台后进度自动接上；
/// - 目标目录对「文件」App 可见（`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`），
///   下载完的 IPA 可以直接在「文件」里长按分享给 AltStore / Sideloadly 安装；
/// - 任务与目标文件名持久化到 UserDefaults，App 被系统回收后重新启动仍能恢复未完成的下载；
/// - 仍然只在用户点击时下载，不自动安装、不执行下载内容。
@MainActor
final class DownloadManager: ObservableObject {
    static let backgroundSessionIdentifier = "com.releaseradar.ios.downloads"

    @Published private(set) var items: [Int64: DownloadItem] = [:]

    let downloadsDirectory: URL

    private let session: URLSession
    private let fallbackSession: URLSession
    private let delegate: DownloadSessionDelegate
    private var destinations: [Int64: URL] = [:]
    /// 后台会话不可用时（例如未签名的开发包）已经切到前台会话的附件 id，避免反复切换。
    private var fallbackUsed: Set<Int64> = []
    private var pendingBackgroundCompletion: (() -> Void)?
    private let logger = Logger(subsystem: "com.releaseradar.ios", category: "Download")
    private let store = DownloadStore()

    var orderedItems: [DownloadItem] {
        items.values.sorted { $0.startedAt > $1.startedAt }
    }

    var activeCount: Int {
        items.values.filter { $0.state == .downloading }.count
    }

    var completedCount: Int {
        items.values.filter { $0.state == .completed }.count
    }

    init(configuration: URLSessionConfiguration? = nil, downloadsDirectory: URL? = nil) {
        let directory = downloadsDirectory ?? Self.defaultDownloadsDirectory
        self.downloadsDirectory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let resolvedConfiguration = configuration ?? Self.backgroundConfiguration()
        let downloadDelegate = DownloadSessionDelegate()
        self.delegate = downloadDelegate
        self.session = URLSession(configuration: resolvedConfiguration, delegate: downloadDelegate, delegateQueue: nil)
        self.fallbackSession = URLSession(configuration: Self.foregroundConfiguration(), delegate: downloadDelegate, delegateQueue: nil)

        downloadDelegate.onProgress = { [weak self] id, written, expected in
            Task { @MainActor in self?.recordProgress(id: id, received: written, expected: expected) }
        }
        downloadDelegate.onFinish = { [weak self] id, url in
            Task { @MainActor in self?.finish(id: id, localURL: url) }
        }
        downloadDelegate.onFailure = { [weak self] id, message, code in
            Task { @MainActor in self?.fail(id: id, message: message, code: code) }
        }
        downloadDelegate.onCancelled = { [weak self] id in
            Task { @MainActor in self?.markCancelled(id: id) }
        }
        downloadDelegate.onBackgroundEventsFinished = { [weak self] in
            Task { @MainActor in self?.finishBackgroundEvents() }
        }

        restorePersistedState()
        refreshTasksFromSession()
    }

    static var defaultDownloadsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("Downloads", isDirectory: true)
    }

    private static func backgroundConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: backgroundSessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.httpMaximumConnectionsPerHost = 3
        return configuration
    }

    /// 后台会话依赖系统后台传输守护进程。未签名 / 调试环境下它可能连不上，
    /// 这时用前台会话兜底，保证下载仍然可用（代价是切后台会被挂起）。
    private static func foregroundConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.httpMaximumConnectionsPerHost = 3
        return configuration
    }

    // MARK: - Public API

    func start(asset: Asset) {
        let id = asset.id
        guard items[id]?.state != .downloading else { return }

        let url: URL
        let fileName: String
        let destination: URL
        do {
            url = try DownloadPolicy.validatedURL(asset.downloadURL)
            fileName = DownloadPolicy.sanitizedFileName(asset.name)
            do {
                try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
            } catch {
                throw DownloadError.fileSystem(error.localizedDescription)
            }
            destination = DownloadPolicy.destinationURL(for: fileName, in: downloadsDirectory)
        } catch {
            var item = DownloadItem(id: id, assetName: asset.name, kind: asset.kind, startedAt: Date())
            item.state = .failed
            item.errorMessage = (error as? DownloadError)?.errorDescription ?? error.localizedDescription
            items[id] = item
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        // 不注入 Token：附件直链会 302 到签名 CDN，认证头不能跟着跳转到第三方主机。
        request.setValue("Radar-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let task = session.downloadTask(with: request)
        task.taskDescription = String(id)
        delegate.setDestination(destination, for: id)
        destinations[id] = destination
        store.saveDestination(fileName: destination.lastPathComponent, assetID: id)
        store.saveActive(id: id, name: fileName, kind: asset.kind, total: asset.size, url: url, downloadURL: asset.downloadURL)

        var item = DownloadItem(id: id, assetName: fileName, kind: asset.kind, startedAt: Date())
        if asset.size > 0 { item.totalBytes = asset.size }
        items[id] = item
        task.resume()
    }

    func retry(asset: Asset) {
        // 只有失败 / 取消的条目才会显示「重试」，此时已经没有运行中的任务；
        // 直接清掉旧记录再重新开始，避免取消回调把新任务误标成已取消。
        items.removeValue(forKey: asset.id)
        destinations.removeValue(forKey: asset.id)
        store.remove(id: asset.id)
        start(asset: asset)
    }

    func cancel(id: Int64) {
        let description = String(id)
        let markCancelled = { [weak self] in
            Task { @MainActor in self?.markCancelled(id: id) }
        }
        session.getAllTasks { tasks in
            if let task = tasks.first(where: { $0.taskDescription == description }) {
                task.cancel()
            } else {
                markCancelled()
            }
        }
        fallbackSession.getAllTasks { tasks in
            tasks.first { $0.taskDescription == description }?.cancel()
        }
    }

    func remove(id: Int64) {
        cancel(id: id)
        items.removeValue(forKey: id)
        destinations.removeValue(forKey: id)
        store.remove(id: id)
    }

    func clearFinished() {
        for (id, item) in items where item.state != .downloading {
            items.removeValue(forKey: id)
            store.remove(id: id)
        }
    }

    func deleteFile(id: Int64) {
        guard let url = items[id]?.localURL ?? destinations[id] else {
            items.removeValue(forKey: id)
            store.remove(id: id)
            return
        }
        try? FileManager.default.removeItem(at: url)
        items.removeValue(forKey: id)
        destinations.removeValue(forKey: id)
        store.remove(id: id)
    }

    /// 把 App 被系统回收期间遗漏的后台回调补一次，回到前台时调用。
    func refreshTasksFromSession() {
        session.getAllTasks { [weak self] tasks in
            let running = tasks.compactMap { task -> Int64? in
                guard task.state == .running || task.state == .suspended else { return nil }
                guard let raw = task.taskDescription, let id = Int64(raw) else { return nil }
                return id
            }
            Task { @MainActor in
                guard let self else { return }
                for id in running {
                    if var item = self.items[id] {
                        if item.state != .downloading {
                            item.state = .downloading
                            item.errorMessage = nil
                            self.items[id] = item
                        }
                    } else if let record = self.store.record(for: id) {
                        var item = DownloadItem(id: id, assetName: record.name, kind: record.kind, startedAt: record.startedAt)
                        item.totalBytes = record.total
                        self.items[id] = item
                    }
                }
            }
        }
    }

    func handleBackgroundEvents(completion: @escaping () -> Void) {
        pendingBackgroundCompletion = completion
    }

    private func finishBackgroundEvents() {
        pendingBackgroundCompletion?()
        pendingBackgroundCompletion = nil
    }

    // MARK: - State updates

    private func restorePersistedState() {
        for record in store.activeRecords() {
            var item = DownloadItem(id: record.id, assetName: record.name, kind: record.kind, startedAt: record.startedAt)
            item.totalBytes = record.total
            items[record.id] = item
        }
        for (id, fileName) in store.destinationMap() {
            destinations[id] = downloadsDirectory.appendingPathComponent(fileName)
        }
        // 已经下载完成但进程被杀：文件还在，标记为已完成。
        for (id, url) in destinations where FileManager.default.fileExists(atPath: url.path) {
            guard var item = items[id], item.state == .downloading else { continue }
            item.state = .completed
            item.localURL = url
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber {
                item.totalBytes = size.int64Value
                item.receivedBytes = size.int64Value
            }
            items[id] = item
        }
    }

    private func recordProgress(id: Int64, received: Int64, expected: Int64) {
        guard var item = items[id], item.state == .downloading else { return }
        item.receivedBytes = received
        if expected > 0 { item.totalBytes = expected }
        items[id] = item
    }

    private func finish(id: Int64, localURL: URL) {
        guard var item = items[id] else { return }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path),
           let size = attributes[.size] as? NSNumber {
            item.totalBytes = size.int64Value
            item.receivedBytes = size.int64Value
        }
        item.state = .completed
        item.localURL = localURL
        item.errorMessage = nil
        items[id] = item
        destinations[id] = localURL
        store.remove(id: id)
        logger.info("Download finished: \(item.assetName, privacy: .public)")
    }

    private func fail(id: Int64, message: String, code: Int?) {
        guard var item = items[id], item.state == .downloading else { return }

        // 后台会话依赖系统守护进程：未签名的开发包、模拟器或进程被强制回收时可能直接失败。
        // 这种情况自动降级到前台会话再试一次，避免「点了下载却什么都没发生」。
        if let code, Self.backgroundSessionFailureCodes.contains(code),
           !fallbackUsed.contains(id),
           let record = store.record(for: id),
           let url = try? DownloadPolicy.validatedURL(record.downloadURL) {
            fallbackUsed.insert(id)
            logger.notice("后台会话不可用（\(code)），改用前台会话重试")
            startForegroundTask(id: id, url: url, item: item)
            return
        }

        item.state = .failed
        item.errorMessage = message
        items[id] = item
        store.remove(id: id)
        logger.error("Download failed: \(message, privacy: .public)")
    }

    private static let backgroundSessionFailureCodes: Set<Int> = [
        NSURLErrorUnknown,
        NSURLErrorBackgroundSessionWasDisconnected,
        NSURLErrorBackgroundSessionInUseByAnotherProcess
    ]

    private func startForegroundTask(id: Int64, url: URL, item: DownloadItem) {
        guard let destination = destinations[id] else {
            var failed = item
            failed.state = .failed
            failed.errorMessage = "无法确定保存位置"
            items[id] = failed
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("Radar-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let task = fallbackSession.downloadTask(with: request)
        task.taskDescription = String(id)
        delegate.setDestination(destination, for: id)
        items[id] = item
        task.resume()
    }

    private func markCancelled(id: Int64) {
        guard var item = items[id], item.state == .downloading else { return }
        item.state = .cancelled
        items[id] = item
        store.remove(id: id)
    }
}

/// 下载任务的轻量持久化：进程被杀后仍能恢复「下载中」条目与目标文件名。
private struct DownloadStore {
    struct Record: Codable {
        let id: Int64
        let name: String
        let kindRaw: String
        let total: Int64
        let startedAt: Date
        /// 原始直链，后台会话不可用时用它在当前会话里重试。
        let downloadURL: String

        var kind: AssetKind { AssetKind(rawValue: kindRaw) ?? .other }
    }

    private let defaults = UserDefaults.standard
    private let activeKey = "radar.downloads.active"
    private let destinationKey = "radar.downloads.destinations"

    func activeRecords() -> [Record] {
        guard let data = defaults.data(forKey: activeKey),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return records
    }

    func record(for id: Int64) -> Record? {
        activeRecords().first { $0.id == id }
    }

    func saveActive(id: Int64, name: String, kind: AssetKind, total: Int64, url: URL, downloadURL: String) {
        var records = activeRecords().filter { $0.id != id }
        records.append(Record(
            id: id,
            name: name,
            kindRaw: kind.rawValue,
            total: total,
            startedAt: .now,
            downloadURL: downloadURL.isEmpty ? url.absoluteString : downloadURL
        ))
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: activeKey) }
    }

    func remove(id: Int64) {
        let records = activeRecords().filter { $0.id != id }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: activeKey) }
    }

    func saveDestination(fileName: String, assetID: Int64) {
        var map = destinationMap()
        map[assetID] = fileName
        defaults.set(map.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value }, forKey: destinationKey)
    }

    func destinationMap() -> [Int64: String] {
        guard let raw = defaults.dictionary(forKey: destinationKey) as? [String: String] else { return [:] }
        var map: [Int64: String] = [:]
        for (key, value) in raw {
            if let id = Int64(key) { map[id] = value }
        }
        return map
    }
}

private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    private let lock = NSLock()
    private var destinations: [Int64: URL] = [:]

    var onProgress: ((Int64, Int64, Int64) -> Void)?
    var onFinish: ((Int64, URL) -> Void)?
    var onFailure: ((Int64, String, Int?) -> Void)?
    var onCancelled: ((Int64) -> Void)?
    var onBackgroundEventsFinished: (() -> Void)?

    private func assetID(for task: URLSessionTask) -> Int64? {
        guard let raw = task.taskDescription else { return nil }
        return Int64(raw)
    }

    func setDestination(_ url: URL, for id: Int64) {
        lock.lock()
        destinations[id] = url
        lock.unlock()
    }

    private func destination(for id: Int64) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return destinations[id]
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = assetID(for: downloadTask) else { return }
        onProgress?(id, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = assetID(for: downloadTask) else { return }
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            onFailure?(id, "服务器返回 \(http.statusCode)", nil)
            return
        }
        guard let destination = destination(for: id) else {
            onFailure?(id, "无法确定保存位置", nil)
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            onFinish?(id, destination)
        } catch {
            onFailure?(id, "保存文件失败：\(error.localizedDescription)", nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = assetID(for: task) else { return }
        if let http = task.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            onFailure?(id, "服务器返回 \(http.statusCode)", nil)
            return
        }
        guard let error else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            onCancelled?(id)
        } else {
            onFailure?(id, error.localizedDescription, nsError.domain == NSURLErrorDomain ? nsError.code : nil)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        onBackgroundEventsFinished?()
    }
}
