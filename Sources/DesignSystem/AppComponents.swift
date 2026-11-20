import SwiftUI

struct CardStyle: ViewModifier {
    var padding: CGFloat = AppLayout.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(AppColors.separator.opacity(0.4), lineWidth: 0.5)
            }
    }
}

extension View {
    func appCard(padding: CGFloat = AppLayout.cardPadding) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = AppColors.secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .fixedSize()
    }
}

/// 附件类型徽标：IPA 用品牌绿，其它用中性色，一眼能分出能不能装。
struct KindBadge: View {
    let kind: AssetKind
    var compact = true

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.systemImage)
                .font(.caption2.weight(.semibold))
            Text(kind.shortLabel)
                .font(.caption2.weight(.bold).monospaced())
        }
        .foregroundStyle(kind == .ipa ? Color.white : Color.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(kind == .ipa ? AppColors.ipa : AppColors.subtle.opacity(0.35), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .textCase(nil)
    }
}

struct RepositoryAvatar: View {
    let urlString: String?
    var size: CGFloat = AppLayout.rowIconSize

    var body: some View {
        AsyncImage(url: URL(string: urlString ?? "")) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    LinearGradient(
                        colors: [AppColors.accent.opacity(0.20), AppColors.accent.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(AppColors.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .stroke(AppColors.separator.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

struct InlineNotice: View {
    enum Level {
        case error
        case warning
        case info

        var color: Color {
            switch self {
            case .error: return AppColors.error
            case .warning: return AppColors.warning
            case .info: return AppColors.accent
            }
        }

        var icon: String {
            switch self {
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    let level: Level
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: level.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(level.color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(level.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(level.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ToastBanner: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack {
            if let toast = appState.toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.82), in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.22), value: appState.toast)
        .allowsHitTesting(false)
    }
}

/// 详情页顶部统计信息（Star / Fork / 语言），保持一行紧凑展示。
struct StatChip: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}
