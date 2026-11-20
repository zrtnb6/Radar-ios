import SwiftUI

struct RepositoryRow: View {
    let repository: Repository
    let latestRelease: Release?
    let hasIPA: Bool

    private var isUnread: Bool {
        guard let latestRelease else { return false }
        return !latestRelease.isRead
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RepositoryAvatar(urlString: repository.avatarURL, size: AppLayout.rowIconSize)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(repository.name)
                        .font(AppTypography.itemTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isUnread {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("有未读更新")
                    }
                    if repository.isArchived {
                        StatusPill(text: "已归档")
                    }
                }

                Text(repository.fullName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let latestRelease {
                        StatusPill(text: latestRelease.tagName, color: AppColors.accent, systemImage: "tag")
                        if hasIPA {
                            KindBadge(kind: .ipa)
                        }
                        Text(AppFormatters.relativeDate(latestRelease.sortDate))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(repository.lastCheckedAt == nil ? "尚未检查" : "暂无 Release")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            if repository.lastError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppColors.warning)
                    .accessibilityLabel("同步失败")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
