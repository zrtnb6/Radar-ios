import SwiftUI
import SwiftData

struct RepositoryDetailView: View {
    let repository: Repository

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var syncService: SyncService
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @Query private var releases: [Release]
    @State private var showingAllHistory = false
    @State private var pendingDelete = false

    init(repository: Repository) {
        self.repository = repository
        let repositoryID = repository.id
        _releases = Query(
            filter: #Predicate<Release> { $0.repositoryID == repositoryID && !$0.isDraft },
            sort: [SortDescriptor(\Release.publishedAt, order: .reverse)]
        )
    }

    private var latestRelease: Release? {
        releases.first { $0.id == repository.latestReleaseID } ?? releases.first
    }

    private var history: [Release] {
        releases.filter { $0.id != latestRelease?.id }
    }

    private var visibleHistory: [Release] {
        showingAllHistory ? history : Array(history.prefix(6))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                header
                if let error = repository.lastError {
                    InlineNotice(level: .warning, message: error, actionTitle: "重试") {
                        Task { await appState.refreshSelected() }
                    }
                }
                latestSection
                historySection
            }
            .padding(AppLayout.pagePadding)
            .padding(.bottom, 24)
        }
        .background(AppColors.groupedBackground)
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await appState.refreshSelected()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await appState.refreshSelected() }
                } label: {
                    if syncService.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(syncService.isRefreshing)
                .accessibilityLabel("刷新该项目")

                Menu {
                    Button {
                        appState.markRead(repository)
                        appState.showToast("已标为已读")
                    } label: {
                        Label("标为已读", systemImage: "checkmark.circle")
                    }
                    if let url = URL.safeHTTPS(repository.url) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("在 GitHub 打开", systemImage: "safari")
                        }
                    }
                    Button {
                        UIPasteboard.general.string = repository.url
                        appState.showToast("已复制仓库链接")
                    } label: {
                        Label("复制仓库链接", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) {
                        pendingDelete = true
                    } label: {
                        Label("删除项目", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
        }
        .confirmationDialog("删除 \(repository.fullName)？", isPresented: $pendingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                appState.deleteRepository(repository)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除本机缓存的版本记录，不影响 GitHub 上的仓库。")
        }
        .task(id: latestRelease?.id) {
            // 进入详情即视为看过最新版本，延迟一点让用户先看到未读标记。
            try? await Task.sleep(for: .seconds(1.2))
            if let latestRelease, !latestRelease.isRead {
                appState.markRead(repository)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RepositoryAvatar(urlString: repository.avatarURL, size: AppLayout.detailIconSize)
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.fullName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 10) {
                        if let language = repository.language, !language.isEmpty {
                            StatChip(systemImage: "chevron.left.forwardslash.chevron.right", text: language)
                        }
                        StatChip(systemImage: "star", text: AppFormatters.compactCount(repository.stars))
                        StatChip(systemImage: "arrow.triangle.branch", text: AppFormatters.compactCount(repository.forks))
                    }
                }
                Spacer(minLength: 0)
            }

            Text(repository.displayDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !repository.topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(repository.topics.prefix(8), id: \.self) { topic in
                            StatusPill(text: topic)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                if repository.isArchived {
                    StatusPill(text: "已归档", color: AppColors.warning, systemImage: "archivebox")
                }
                Text(repository.lastCheckedAt.map { "上次检查 \(AppFormatters.relativeDate($0))" } ?? "尚未检查")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .appCard()
    }

    @ViewBuilder
    private var latestSection: some View {
        if let latestRelease {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    SectionHeader(title: "最新版本", systemImage: "sparkles")
                    Spacer(minLength: 4)
                    StatusPill(text: latestRelease.tagName, color: AppColors.accent, systemImage: "tag")
                }

                HStack(spacing: 6) {
                    Text(latestRelease.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                    if latestRelease.isPrerelease {
                        StatusPill(text: "预发布", color: AppColors.warning)
                    }
                    Spacer(minLength: 0)
                }

                Text(AppFormatters.releaseDate(latestRelease.publishedAt ?? latestRelease.createdAt)
                     + " · " + AppFormatters.relativeDate(latestRelease.sortDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ReleaseAssetList(release: latestRelease)
                    .padding(.top, 4)

                if let notes = latestRelease.notes {
                    Divider()
                    ReleaseNotesView(markdown: notes, initiallyExpanded: appState.pendingReleaseID == latestRelease.id)
                }

                if let url = URL.safeHTTPS(latestRelease.htmlURL) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("在 GitHub 查看此版本", systemImage: "safari")
                            .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.accent)
                }
            }
            .appCard()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "最新版本", systemImage: "sparkles")
                Text("还没有可用的正式版本")
                    .font(.subheadline.weight(.medium))
                Text("仓库可能尚未发布 Release，或只发布了预发布版本；可在设置中打开「监控预发布版本」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("立即检查") {
                    Task { await appState.refreshSelected() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            }
            .appCard()
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "历史版本", subtitle: "共 \(history.count) 个", systemImage: "clock.arrow.circlepath")
                    .padding(.bottom, 4)

                ForEach(visibleHistory) { release in
                    NavigationLink {
                        ReleaseDetailView(repository: repository, release: release)
                    } label: {
                        historyRow(release)
                    }
                    .buttonStyle(.plain)
                    if release.id != visibleHistory.last?.id {
                        Divider().padding(.leading, 2)
                    }
                }

                if history.count > 6 {
                    Button(showingAllHistory ? "收起" : "显示全部 \(history.count) 个版本") {
                        withAnimation(.snappy(duration: 0.2)) { showingAllHistory.toggle() }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.accent)
                    .padding(.top, 8)
                }
            }
            .appCard()
        }
    }

    private func historyRow(_ release: Release) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(release.tagName)
                        .font(.subheadline.weight(.medium).monospaced())
                    if release.isPrerelease {
                        StatusPill(text: "预发布", color: AppColors.warning)
                    }
                    if !release.isRead {
                        Circle().fill(AppColors.accent).frame(width: 6, height: 6)
                    }
                }
                Text(AppFormatters.releaseDate(release.publishedAt ?? release.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
