import SwiftUI
import SwiftData

struct DownloadsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if downloads.orderedItems.isEmpty {
                    ContentUnavailableView {
                        Label("还没有下载", systemImage: "arrow.down.circle")
                    } description: {
                        Text("在项目详情里点「下载」，IPA 会保存到本机「文件 → 我的 iPhone → Radar → Downloads」。")
                    }
                } else {
                    List {
                        Section {
                            ForEach(downloads.orderedItems) { item in
                                DownloadRow(item: item, onRetry: { retry(item) })
                            }
                        } header: {
                            SectionHeader(
                                title: "下载任务",
                                subtitle: "\(downloads.activeCount) 个进行中",
                                systemImage: "arrow.down.circle"
                            )
                        } footer: {
                            Text("文件保存在「文件」App 的 Radar → Downloads 中，可在那里分享给 AltStore、Sideloadly 等侧载工具安装。")
                                .font(.caption2)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("下载")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            downloads.clearFinished()
                        } label: {
                            Label("清除已完成 / 失败记录", systemImage: "trash")
                        }
                        .disabled(downloads.completedCount == 0 && downloads.activeCount == downloads.orderedItems.count)
                        Button {
                            UIPasteboard.general.string = downloads.downloadsDirectory.path
                            appState.showToast("已复制保存路径")
                        } label: {
                            Label("复制保存路径", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("下载操作")
                }
            }
        }
    }

    private func retry(_ item: DownloadItem) {
        let id = item.id
        let descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
        if let asset = try? modelContext.fetch(descriptor).first {
            downloads.retry(asset: asset)
        } else {
            appState.showToast("该附件已不在仓库中，请在项目页重新下载")
        }
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    let onRetry: () -> Void

    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.kind.systemImage)
                    .font(.footnote)
                    .foregroundStyle(item.kind.tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.assetName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        KindBadge(kind: item.kind)
                        Text(statusText)
                            .font(.caption2)
                            .foregroundStyle(statusColor)
                    }
                }

                Spacer(minLength: 4)

                trailingControls
            }

            if item.state == .downloading {
                ProgressView(value: item.progress)
                    .tint(AppColors.accent)
                Text(item.progressSummary)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if item.state == .failed, let message = item.errorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(AppColors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch item.state {
        case .downloading:
            return item.totalBytes > 0
                ? "\(Int((item.progress * 100).rounded()))%"
                : "下载中"
        case .completed:
            return ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file)
        case .failed:
            return "下载失败"
        case .cancelled:
            return "已取消"
        }
    }

    private var statusColor: Color {
        switch item.state {
        case .downloading: return .secondary
        case .completed: return AppColors.ipa
        case .failed: return AppColors.error
        case .cancelled: return Color(uiColor: .tertiaryLabel)
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch item.state {
        case .downloading:
            Button {
                downloads.cancel(id: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消下载")
        case .completed:
            HStack(spacing: 10) {
                if let url = item.localURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                    }
                    .accessibilityLabel("分享文件")
                }
                Button(role: .destructive) {
                    downloads.deleteFile(id: item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除本地文件")
            }
        case .failed, .cancelled:
            HStack(spacing: 10) {
                Button("重试", action: onRetry)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(role: .destructive) {
                    downloads.remove(id: item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除记录")
            }
        }
    }
}
