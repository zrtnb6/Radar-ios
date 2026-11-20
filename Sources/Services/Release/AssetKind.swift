import SwiftUI

/// Release 附件的类型判定。
///
/// iOS 客户端把 `.ipa` 作为一等公民：它是唯一能在 iPhone / iPad 上安装的格式；
/// `.dmg` 仍然识别（同一个仓库常常同时发布 macOS 与 iOS 版本），但在 iOS 上只作信息展示。
enum AssetKind: String, CaseIterable, Sendable {
    case ipa
    case dmg
    case archive
    case other

    /// 按扩展名判定，大小写不敏感，不依赖 Content-Type（GitHub 常把 IPA 标成 octet-stream）。
    static func detect(fileName: String) -> AssetKind {
        switch extensionOf(fileName) {
        case "ipa": return .ipa
        case "dmg": return .dmg
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar": return .archive
        default: return .other
        }
    }

    /// 只取最后一段扩展名，兼容 `App 1.2.0 (build 8).ipa` 与大小写混写。
    static func extensionOf(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed as NSString).pathExtension.lowercased()
    }

    var displayName: String {
        switch self {
        case .ipa: return "IPA 安装包"
        case .dmg: return "DMG 磁盘映像"
        case .archive: return "压缩包"
        case .other: return "其他文件"
        }
    }

    var shortLabel: String {
        switch self {
        case .ipa: return "IPA"
        case .dmg: return "DMG"
        case .archive: return "ZIP"
        case .other: return "FILE"
        }
    }

    var systemImage: String {
        switch self {
        case .ipa: return "app.badge.checkmark"
        case .dmg: return "externaldrive"
        case .archive: return "archivebox"
        case .other: return "doc"
        }
    }

    /// 能否在 iOS 上直接安装（交给 AltStore / Sideloadly / TrollStore 等侧载工具）。
    var isInstallableOnIOS: Bool { self == .ipa }

    var tint: Color {
        switch self {
        case .ipa: return AppColors.ipa
        case .dmg: return AppColors.dmg
        case .archive: return AppColors.secondary
        case .other: return AppColors.secondary
        }
    }

    /// 排序权重：IPA 排最前，其余按体积所在组别。
    var sortRank: Int {
        switch self {
        case .ipa: return 0
        case .archive: return 1
        case .dmg: return 2
        case .other: return 3
        }
    }
}
