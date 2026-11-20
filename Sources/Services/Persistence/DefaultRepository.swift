import Foundation
import SwiftData

/// 首次安装预置的默认项目：Radar 的 iOS 仓库，开箱即能看到自己的版本与 IPA 附件。
///
/// - 只写本地 SwiftData，不联网，离线也能看到条目；
/// - 负数占位 id 不会与 GitHub 真实仓库 id 冲突，首次刷新按 owner/name 拉取真实数据；
/// - 首次刷新只建立已读基线，不会为历史版本推送通知；
/// - 用 UserDefaults 标记保证只注入一次，删掉后不会复活。
enum DefaultRepository {
    static let owner = "zrtnb6"
    static let name = "Radar-ios"
    static let fullName = "\(owner)/\(name)"
    static let url = "https://github.com/\(fullName)"

    static let seedID: Int64 = -1
    static let seedFlagKey = "hasSeededDefaultRepository.ios"

    @discardableResult
    static func seedIfNeeded(context: ModelContext) -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seedFlagKey) else { return false }

        let existingCount = (try? context.fetchCount(FetchDescriptor<Repository>())) ?? 0
        guard existingCount == 0 else {
            defaults.set(true, forKey: seedFlagKey)
            return false
        }

        let repository = Repository(
            id: seedID,
            owner: owner,
            name: name,
            fullName: fullName,
            url: url,
            repositoryDescription: "Radar · 原生 iOS GitHub Release 监控客户端",
            language: "Swift",
            topics: ["ios", "swiftui", "swiftdata", "github-releases", "ipa"]
        )
        context.insert(repository)
        do {
            try context.save()
        } catch {
            context.delete(repository)
            return false
        }
        defaults.set(true, forKey: seedFlagKey)
        return true
    }
}
