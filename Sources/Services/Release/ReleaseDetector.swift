import Foundation

enum ReleaseChange: Equatable {
    case none
    case newRelease
    case promotedFromPrerelease
}

enum ReleaseDetector {
    /// iOS 端的核心判定：是不是 IPA 附件。
    static func isIPA(fileName: String) -> Bool {
        AssetKind.detect(fileName: fileName) == .ipa
    }

    /// 兼容旧调用：DMG 仍然被识别，只是不再是 iOS 端的安装目标。
    static func isDMG(fileName: String) -> Bool {
        AssetKind.detect(fileName: fileName) == .dmg
    }

    static func eligibleReleases(from releases: [GitHubReleaseDTO], includePrerelease: Bool) -> [GitHubReleaseDTO] {
        releases
            .filter { !$0.isDraft && (includePrerelease || !$0.isPrerelease) }
            .sorted { lhs, rhs in
                let left = lhs.publishedAt ?? lhs.createdAt ?? .distantPast
                let right = rhs.publishedAt ?? rhs.createdAt ?? .distantPast
                if left == right { return lhs.id > rhs.id }
                return left > right
            }
    }

    static func detectChange(candidate: GitHubReleaseDTO, current: Release?) -> ReleaseChange {
        guard let current else { return .newRelease }
        if candidate.id != current.id { return .newRelease }
        if current.isPrerelease && !candidate.isPrerelease { return .promotedFromPrerelease }
        if candidate.tagName != current.tagName { return .newRelease }
        if let candidateDate = candidate.publishedAt, let currentDate = current.publishedAt,
           candidateDate > currentDate {
            return .newRelease
        }
        if candidate.publishedAt != nil && current.publishedAt == nil { return .newRelease }
        return .none
    }

    static func assetsChanged(from oldIDs: Set<Int64>, to newAssets: [GitHubAssetDTO]) -> Bool {
        oldIDs != Set(newAssets.map(\.id))
    }

    /// 只保留可在 iOS 安装的附件（IPA），供「仅显示 IPA」过滤与安装提示使用。
    static func installableAssets(_ assets: [Asset]) -> [Asset] {
        assets.filter(\.isIPA)
    }

    /// 展示排序：IPA 优先，同类型内按文件名。
    static func orderedAssets(_ assets: [Asset]) -> [Asset] {
        assets.sorted { lhs, rhs in
            if lhs.kind.sortRank != rhs.kind.sortRank {
                return lhs.kind.sortRank < rhs.kind.sortRank
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
