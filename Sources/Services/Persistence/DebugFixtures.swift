#if DEBUG
import Foundation
import SwiftData

/// 视觉验收用夹具：只在 DEBUG 构建、且显式传 `--ui-fixtures` 时注入，
/// 方便在没有有效 GitHub 配额（或断网）的情况下检查列表、详情与附件的排版。
enum DebugFixtures {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-fixtures")
            || ProcessInfo.processInfo.environment["RADAR_UI_FIXTURES"] == "1"
    }

    /// `--ui-tab=settings` / `--ui-tab=downloads`：直接打开指定 Tab 截图。
    static var initialTabName: String? {
        let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--ui-tab=") }
        return argument.map { String($0.dropFirst("--ui-tab=".count)) }
    }

    /// `--ui-open=Orbit`：直接打开某个仓库的详情，便于逐屏截图。
    static var openRepositoryName: String? {
        let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--ui-open=") }
        return argument.map { String($0.dropFirst("--ui-open=".count)) }
    }

    static func populate(context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<Repository>())) == 0 else { return }
        let now = Date()

        let orbit = Repository(
            id: 900_001,
            owner: "lumen-labs",
            name: "Orbit",
            fullName: "lumen-labs/Orbit",
            url: "https://github.com/lumen-labs/Orbit",
            repositoryDescription: "Keep every release of your iOS app in one place.",
            homepage: "https://example.com/orbit",
            stars: 8_420,
            forks: 312,
            language: "Swift",
            topics: ["ios", "releases", "ipa"],
            addedAt: now.addingTimeInterval(-86_400 * 12),
            lastCheckedAt: now.addingTimeInterval(-420),
            latestReleaseID: 910_004
        )

        let mono = Repository(
            id: 900_002,
            owner: "inkstone",
            name: "Mono",
            fullName: "inkstone/Mono",
            url: "https://github.com/inkstone/Mono",
            repositoryDescription: "A focused writing app, now with iPad support.",
            stars: 3_120,
            forks: 147,
            language: "Swift",
            topics: ["markdown", "writing"],
            addedAt: now.addingTimeInterval(-86_400 * 8),
            lastCheckedAt: now.addingTimeInterval(-3_600)
        )

        let beacon = Repository(
            id: 900_003,
            owner: "field-notes",
            name: "Beacon",
            fullName: "field-notes/Beacon",
            url: "https://github.com/field-notes/Beacon",
            repositoryDescription: "Lightweight status monitoring for small teams.",
            stars: 640,
            forks: 31,
            language: "TypeScript",
            topics: ["monitoring"],
            addedAt: now.addingTimeInterval(-86_400 * 2),
            lastCheckedAt: now.addingTimeInterval(-18_000),
            lastError: "网络请求超时，请检查连接后重试。"
        )

        [orbit, mono, beacon].forEach(context.insert)

        let latest = Release(
            id: 910_004,
            repositoryID: orbit.id,
            tagName: "v2.4.0",
            name: "Orbit 2.4",
            body: """
            ## 新增

            - **画中画** 支持横屏与分屏，退出后仍可继续播放。
            - 新的版本详情页会优先展示 IPA 附件。
            - 下载中心支持按状态筛选。

            ### 修复

            - 修复了在 iPad 分栏模式下详情页可能空白的问题。
            - 修复长文本 Release Notes 展开后滚动位置跳动。
            """,
            htmlURL: "https://github.com/lumen-labs/Orbit/releases/tag/v2.4.0",
            publishedAt: now.addingTimeInterval(-7_800),
            createdAt: now.addingTimeInterval(-7_800),
            updatedAt: now.addingTimeInterval(-4_200),
            isRead: false
        )
        let previous = Release(
            id: 910_003,
            repositoryID: orbit.id,
            tagName: "v2.3.1",
            name: "Orbit 2.3.1",
            body: "稳定性更新，修复若干崩溃。",
            htmlURL: "https://github.com/lumen-labs/Orbit/releases/tag/v2.3.1",
            publishedAt: now.addingTimeInterval(-86_400 * 26),
            createdAt: now.addingTimeInterval(-86_400 * 26),
            updatedAt: now.addingTimeInterval(-86_400 * 26),
            isRead: true
        )
        let monoRelease = Release(
            id: 910_031,
            repositoryID: mono.id,
            tagName: "v1.8.1",
            name: "Mono 1.8.1",
            body: "提升表格渲染与导出性能。",
            htmlURL: "https://github.com/inkstone/Mono/releases/tag/v1.8.1",
            publishedAt: now.addingTimeInterval(-86_400 * 4),
            createdAt: now.addingTimeInterval(-86_400 * 4),
            updatedAt: now.addingTimeInterval(-86_400 * 4),
            isRead: true
        )
        [latest, previous, monoRelease].forEach(context.insert)
        mono.latestReleaseID = monoRelease.id

        let assets = [
            Asset(id: 920_001, releaseID: latest.id, name: "Orbit-2.4.0.ipa", size: 24_800_000, contentType: "application/octet-stream", downloadURL: "https://github.com/lumen-labs/Orbit/releases/download/v2.4.0/Orbit-2.4.0.ipa", downloadCount: 2_300, kind: .ipa),
            Asset(id: 920_002, releaseID: latest.id, name: "Orbit-2.4.0-macOS.dmg", size: 12_100_000, contentType: "application/x-apple-diskimage", downloadURL: "https://github.com/lumen-labs/Orbit/releases/download/v2.4.0/Orbit-2.4.0-macOS.dmg", downloadCount: 940, kind: .dmg),
            Asset(id: 920_003, releaseID: latest.id, name: "Orbit-2.4.0-source.zip", size: 3_300_000, contentType: "application/zip", downloadURL: "https://github.com/lumen-labs/Orbit/releases/download/v2.4.0/Orbit-2.4.0-source.zip", downloadCount: 130, kind: .archive),
            Asset(id: 920_004, releaseID: monoRelease.id, name: "Mono-1.8.1.ipa", size: 9_400_000, contentType: "application/octet-stream", downloadURL: "https://github.com/inkstone/Mono/releases/download/v1.8.1/Mono-1.8.1.ipa", downloadCount: 680, kind: .ipa)
        ]
        assets.forEach(context.insert)

        context.insert(NotificationEvent(id: "release:\(orbit.id):\(latest.id)", repositoryID: orbit.id, releaseID: latest.id, isDelivered: true))
        try? context.save()
    }
}
#endif
