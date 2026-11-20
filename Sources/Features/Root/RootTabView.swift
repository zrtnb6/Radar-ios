import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            RepositoriesTabView()
                .tabItem { Label("项目", systemImage: "shippingbox") }
                .tag(RootTab.repositories)
                .badge(appState.unreadCount)

            DownloadsView()
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }
                .tag(RootTab.downloads)
                .badge(downloads.activeCount)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(RootTab.settings)
        }
        .sheet(isPresented: $appState.showingAddRepository) {
            AddRepositoryView()
                .environmentObject(appState)
                .environmentObject(appState.syncService)
        }
    }
}

/// iPhone 用导航栈逐级进入；iPad / 横屏用分栏，左侧列表右侧详情。
struct RepositoriesTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                RepositoryListView(isSidebar: true)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
            } detail: {
                NavigationStack {
                    if let id = appState.selectedRepositoryID, let repository = appState.repository(id: id) {
                        RepositoryDetailView(repository: repository)
                            .id(repository.id)
                    } else {
                        ContentUnavailableView(
                            "选择一个项目",
                            systemImage: "shippingbox",
                            description: Text("从左侧选择要查看的 GitHub 项目")
                        )
                    }
                }
            }
        } else {
            NavigationStack(path: $appState.repositoryPath) {
                RepositoryListView(isSidebar: false)
                    .navigationDestination(for: Int64.self) { id in
                        if let repository = appState.repository(id: id) {
                            RepositoryDetailView(repository: repository)
                        } else {
                            ContentUnavailableView(
                                "项目已删除",
                                systemImage: "trash",
                                description: Text("该项目已从 Radar 中移除")
                            )
                        }
                    }
            }
        }
    }
}
