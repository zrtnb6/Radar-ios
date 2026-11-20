import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var syncService: SyncService
    @EnvironmentObject private var downloads: DownloadManager

    @AppStorage(AppSettings.automaticChecks) private var automaticChecks = true
    @AppStorage(AppSettings.checkInterval) private var checkInterval = 6.0
    @AppStorage(AppSettings.backgroundRefresh) private var backgroundRefresh = true
    @AppStorage(AppSettings.ignoreArchived) private var ignoreArchived = true
    @AppStorage(AppSettings.monitorPrerelease) private var monitorPrerelease = false
    @AppStorage(AppSettings.onlyIPA) private var onlyIPA = true
    @AppStorage(AppSettings.newReleaseNotifications) private var newReleaseNotifications = true
    @AppStorage(AppSettings.assetChangeNotifications) private var assetChangeNotifications = false

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var storageSummary = "统计中…"

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GitHubTokenSection()
                } header: {
                    Text("GitHub 令牌")
                }

                Section {
                    Toggle("定时检查", isOn: $automaticChecks)
                    if automaticChecks {
                        Picker("检查间隔", selection: $checkInterval) {
                            ForEach(AppSettings.checkIntervalOptions, id: \.self) { hours in
                                Text(AppSettings.checkIntervalLabel(hours)).tag(hours)
                            }
                        }
                        Toggle("后台刷新", isOn: $backgroundRefresh)
                            .onChange(of: backgroundRefresh) { _, _ in
                                BackgroundRefreshService.shared.scheduleNext()
                            }
                    }
                    Toggle("监控预发布版本", isOn: $monitorPrerelease)
                    Toggle("忽略已归档仓库", isOn: $ignoreArchived)
                    Toggle("仅显示 IPA 附件", isOn: $onlyIPA)
                } header: {
                    Text("检查与筛选")
                } footer: {
                    Text("后台刷新由系统调度，最早约 15 分钟后执行，实际时机取决于电量与使用习惯；打开 App 时总会补一次检查。")
                }

                Section {
                    HStack {
                        Text("通知权限")
                        Spacer()
                        Text(statusLabel)
                            .foregroundStyle(statusColor)
                    }
                    if authorizationStatus != .authorized {
                        Button("开启通知权限") {
                            Task {
                                _ = await appState.requestNotificationPermission()
                                await refreshAuthorizationStatus()
                            }
                        }
                    }
                    Toggle("新版本通知", isOn: $newReleaseNotifications)
                    Toggle("附件变化通知", isOn: $assetChangeNotifications)
                } header: {
                    Text("通知")
                } footer: {
                    Text("同一 Release 只会提醒一次；通知里的 IPA 状态由最新附件决定。")
                }

                Section {
                    LabeledContent("下载文件", value: storageSummary)
                    Button("清除已完成 / 失败记录") {
                        downloads.clearFinished()
                        appState.showToast("已清理下载记录")
                        updateStorageSummary()
                    }
                    Button {
                        UIPasteboard.general.string = downloads.downloadsDirectory.path
                        appState.showToast("已复制保存路径")
                    } label: {
                        Label("复制保存路径", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("存储")
                } footer: {
                    Text("IPA 保存在 App 沙盒的 Documents/Downloads，已开启文件共享，可在「文件」App 中查看、分享与安装。")
                }

                Section {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("项目", value: "\(appState.syncService.unreadCount()) 个未读版本")
                    if let url = URL(string: "https://github.com/zrtnb6/Radar-ios") {
                        Link(destination: url) {
                            Label("Radar-ios 仓库", systemImage: "arrow.up.right.square")
                        }
                    }
                    if let url = URL(string: "https://github.com/zrtnb6/Radar") {
                        Link(destination: url) {
                            Label("Radar macOS 版", systemImage: "desktopcomputer")
                        }
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("Radar 是本地优先的 GitHub Release 监控客户端：无账号体系、无遥测，仓库与版本数据只存在本机 SwiftData 中。")
                }
            }
            .navigationTitle("设置")
            .task {
                await refreshAuthorizationStatus()
                updateStorageSummary()
            }
        }
    }

    private var statusLabel: String {
        switch authorizationStatus {
        case .authorized: return "已开启"
        case .provisional: return "临时授权"
        case .denied: return "已拒绝"
        case .ephemeral: return "临时"
        case .notDetermined: return "未询问"
        @unknown default: return "未知"
        }
    }

    private var statusColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return AppColors.ipa
        case .denied: return AppColors.error
        default: return .secondary
        }
    }

    private func refreshAuthorizationStatus() async {
        authorizationStatus = await appState.notificationService.authorizationStatus()
    }

    private func updateStorageSummary() {
        let directory = downloads.downloadsDirectory
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let totalBytes = files.reduce(into: Int64(0)) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            partial += Int64(size)
        }
        storageSummary = "\(files.count) 个文件 · \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
    }
}
