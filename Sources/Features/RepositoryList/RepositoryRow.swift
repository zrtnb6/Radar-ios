import SwiftUI

struct RepositoryRow: View {
    let repository: Repository
    let latestRelease: Release?
    let hasIPA: Bool
    /// iPad 分栏下被选中的行：用作色调整，避免蓝色选中背景上出现低对比的浅蓝徽标。
    var isEmphasized = false

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
                        .foregroundStyle(isEmphasized ? Color.white : Color.primary)
                        .lineLimit(1)
                    if isUnread {
                        Circle()
                            .fill(isEmphasized ? Color.white : AppColors.accent)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("有未读更新")
                    }
                    if repository.isArchived {
                        StatusPill(text: "已归档", color: isEmphasized ? .white : AppColors.secondary)
                    }
                }

                Text(repository.fullName)
                    .font(.caption)
                    .foregroundStyle(isEmphasized ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let latestRelease {
                        StatusPill(
                            text: latestRelease.tagName,
                            color: isEmphasized ? .white : AppColors.accent,
                            systemImage: "tag"
                        )
                        if hasIPA {
                            KindBadge(kind: .ipa)
                        }
                        Text(AppFormatters.relativeDate(latestRelease.sortDate))
                            .font(.caption2)
                            .foregroundStyle(isEmphasized ? Color.white.opacity(0.8) : Color.secondary.opacity(0.8))
                    } else {
                        Text(repository.lastCheckedAt == nil ? "尚未检查" : "暂无 Release")
                            .font(.caption2)
                            .foregroundStyle(isEmphasized ? Color.white.opacity(0.8) : Color.secondary.opacity(0.8))
                    }
                }
            }

            Spacer(minLength: 4)

            if repository.lastError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(isEmphasized ? Color.white : AppColors.warning)
                    .accessibilityLabel("同步失败")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
