import SwiftUI

/// 单个 Release 附件行：识别类型、下载、进度、分享、删除文件。
/// iOS 上 IPA 行会被高亮成主操作，其它格式只提供「仍要下载」。
struct AssetRow: View {
    let asset: Asset

    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var appState: AppState

    private var item: DownloadItem? { downloads.items[asset.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: asset.kind.systemImage)
                    .font(.footnote)
                    .foregroundStyle(asset.kind.tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        KindBadge(kind: asset.kind)
                        Text(asset.formattedSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let count = asset.downloadCount, count > 0 {
                            Text("· \(AppFormatters.compactCount(count)) 次下载")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer(minLength: 8)
                trailingControl
            }

            if let item, item.state == .downloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: item.progress)
                        .tint(AppColors.accent)
                    HStack {
                        Text(item.progressSummary)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("取消") { downloads.cancel(id: asset.id) }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let item, item.state == .failed {
                InlineNotice(level: .error, message: item.errorMessage ?? "下载失败", actionTitle: "重试") {
                    downloads.retry(asset: asset)
                }
            }

            if asset.kind == .dmg {
                Text("DMG 是 macOS 安装包，iOS 无法安装；本客户端只把 IPA 作为安装目标。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if let item {
            switch item.state {
            case .downloading:
                Button(role: .destructive) {
                    downloads.cancel(id: asset.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消下载")
            case .completed:
                Menu {
                    if let url = item.localURL {
                        ShareLink(item: url) {
                            Label("分享 / 存储到「文件」", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(role: .destructive) {
                        downloads.deleteFile(id: asset.id)
                        appState.showToast("已删除本地文件")
                    } label: {
                        Label("删除本地文件", systemImage: "trash")
                    }
                } label: {
                    Label("已完成", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(AppColors.ipa)
                }
                .accessibilityLabel("下载完成，可分享")
            case .failed, .cancelled:
                Button("重试") { downloads.retry(asset: asset) }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else {
            Button {
                downloads.start(asset: asset)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("下载", systemImage: "arrow.down.circle")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(asset.kind == .ipa ? AppColors.ipa : AppColors.accent)
        }
    }
}
