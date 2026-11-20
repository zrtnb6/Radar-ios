import SwiftUI
import SwiftData

struct RepositoryListView: View {
    var isSidebar: Bool = false

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var syncService: SyncService
    @Query(sort: \Repository.addedAt, order: .reverse) private var repositories: [Repository]

    @State private var searchText = ""
    @State private var pendingDelete: Repository?
    @State private var showingDeleteConfirmation = false

    private var filtered: [Repository] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return repositories }
        return repositories.filter {
            $0.fullName.localizedCaseInsensitiveContains(keyword)
                || $0.displayDescription.localizedCaseInsensitiveContains(keyword)
                || ($0.language?.localizedCaseInsensitiveContains(keyword) ?? false)
        }
    }

    var body: some View {
        Group {
            if isSidebar {
                List(selection: $appState.selectedRepositoryID) {
                    content
                }
            } else {
                List {
                    content
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Radar")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索项目、owner 或语言")
        .refreshable {
            await appState.refreshAll()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .overlay {
            if repositories.isEmpty && searchText.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await appState.refreshAll() }
                } label: {
                    if syncService.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(syncService.isRefreshing)
                .accessibilityLabel("立即检查")

                Button {
                    appState.showingAddRepository = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加项目")
            }
        }
        .confirmationDialog(
            "删除 \(pendingDelete?.fullName ?? "该项目")？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let pendingDelete { appState.deleteRepository(pendingDelete) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("只删除本机缓存的版本记录，不影响 GitHub 上的仓库。")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = syncService.lastSyncError, !repositories.isEmpty {
            Section {
                InlineNotice(level: .error, message: error, actionTitle: "重试") {
                    Task { await appState.refreshAll() }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }
        }

        Section {
            ForEach(filtered) { repository in
                row(for: repository)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = repository
                            showingDeleteConfirmation = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            appState.markRead(repository)
                        } label: {
                            Label("标为已读", systemImage: "checkmark.circle")
                        }
                        .tint(AppColors.accent)
                    }
                    .contextMenu {
                        Button {
                            appState.open(repository)
                        } label: {
                            Label("查看详情", systemImage: "chevron.right.circle")
                        }
                        Button {
                            appState.markRead(repository)
                        } label: {
                            Label("标为已读", systemImage: "checkmark.circle")
                        }
                        if let url = URL.safeHTTPS(repository.url) {
                            Link(destination: url) {
                                Label("在 GitHub 打开", systemImage: "safari")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            pendingDelete = repository
                            showingDeleteConfirmation = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        } header: {
            SectionHeader(
                title: "监控中",
                subtitle: summaryText,
                systemImage: "dot.radiowaves.up.forward"
            )
        } footer: {
            if let lastSuccess = syncService.lastSuccessAt {
                Text("上次成功检查：\(AppFormatters.relativeDate(lastSuccess))")
                    .font(.caption2)
            }
        }
    }

    private var summaryText: String {
        let unread = filtered.filter { repository in
            guard let release = try? syncService.latestRelease(for: repository) else { return false }
            return !release.isRead
        }.count
        var parts = ["\(filtered.count) 个项目"]
        if unread > 0 { parts.append("\(unread) 条未读") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func row(for repository: Repository) -> some View {
        let release = try? syncService.latestRelease(for: repository)
        let hasIPA = release.map { syncService.hasIPA(release: $0) } ?? false
        let row = RepositoryRow(repository: repository, latestRelease: release, hasIPA: hasIPA)

        if isSidebar {
            row.tag(repository.id)
        } else {
            NavigationLink(value: repository.id) { row }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有监控任何项目", systemImage: "dot.radiowaves.left.and.right")
        } description: {
            Text("添加 GitHub 仓库后，Radar 会在新版本发布时提醒你，并把 IPA 附件直接下载到「文件」里。")
        } actions: {
            Button("添加项目") {
                appState.showingAddRepository = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
