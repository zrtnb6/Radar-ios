import SwiftUI

struct ReleaseDetailView: View {
    let repository: Repository
    let release: Release

    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        StatusPill(text: release.tagName, color: AppColors.accent, systemImage: "tag")
                        if release.isPrerelease {
                            StatusPill(text: "预发布", color: AppColors.warning)
                        }
                        if !release.isRead {
                            StatusPill(text: "未读", color: AppColors.newRelease)
                        }
                    }
                    Text(release.displayTitle)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AppFormatters.releaseDate(release.publishedAt ?? release.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "附件", subtitle: nil, systemImage: "paperclip")
                        .padding(.bottom, 4)
                    ReleaseAssetList(release: release)
                }
                .appCard()

                if let notes = release.notes {
                    ReleaseNotesView(markdown: notes, initiallyExpanded: true)
                }

                if let url = URL.safeHTTPS(release.htmlURL) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("在 GitHub 查看此版本", systemImage: "safari")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(AppLayout.pagePadding)
        }
        .background(AppColors.groupedBackground)
        .navigationTitle(release.tagName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !release.isRead {
                appState.pendingReleaseID = release.id
            }
        }
    }
}
