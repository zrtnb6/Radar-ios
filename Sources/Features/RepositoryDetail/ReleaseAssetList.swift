import SwiftUI
import SwiftData

/// 某个 Release 的附件列表。
/// 自己持有 `@Query`，刷新后新附件、新 Release 会自动刷新界面。
struct ReleaseAssetList: View {
    let release: Release

    @EnvironmentObject private var downloads: DownloadManager
    @Query private var assets: [Asset]

    init(release: Release) {
        self.release = release
        let releaseID = release.id
        _assets = Query(
            filter: #Predicate<Asset> { $0.releaseID == releaseID },
            sort: [SortDescriptor(\Asset.name)]
        )
    }

    private var onlyIPA: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.onlyIPA)
    }

    private var ordered: [Asset] {
        ReleaseDetector.orderedAssets(assets)
    }

    private var ipaAssets: [Asset] { ordered.filter(\.isIPA) }
    private var visibleOthers: [Asset] { onlyIPA ? [] : ordered.filter { !$0.isIPA } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !ipaAssets.isEmpty {
                ForEach(ipaAssets) { asset in
                    AssetRow(asset: asset)
                    if asset.id != ipaAssets.last?.id || !visibleOthers.isEmpty {
                        Divider().padding(.leading, 26)
                    }
                }
            } else {
                noIPANotice
                if !visibleOthers.isEmpty {
                    Divider().padding(.leading, 26)
                }
            }

            if !visibleOthers.isEmpty {
                ForEach(visibleOthers) { asset in
                    AssetRow(asset: asset)
                    if asset.id != visibleOthers.last?.id {
                        Divider().padding(.leading, 26)
                    }
                }
            }

            if onlyIPA && !ipaAssets.isEmpty && assets.count > ipaAssets.count {
                Text("已隐藏 \(assets.count - ipaAssets.count) 个非 IPA 附件，可在设置中关闭「仅显示 IPA 附件」。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
    }

    private var noIPANotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(AppColors.warning)
                Text("该版本没有 IPA 附件")
                    .font(.subheadline.weight(.medium))
            }
            Text(onlyIPA
                 ? "这个 Release 没有发布 .ipa 文件，可能只面向 macOS 或其它平台。"
                 : "没有 .ipa 文件，下面的其它格式无法直接在 iOS 上安装。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}
