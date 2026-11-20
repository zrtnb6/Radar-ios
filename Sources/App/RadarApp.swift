import SwiftUI
import SwiftData

@main
struct RadarApp: App {
    @UIApplicationDelegateAdaptor(RadarAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
                .environmentObject(appState.syncService)
                .environmentObject(appState.downloadManager)
                .tint(AppColors.accent)
                .task { appState.onAppear() }
                .onOpenURL { appState.handleURL($0) }
                .onChange(of: scenePhase) { _, newPhase in
                    appState.handleScenePhase(newPhase)
                }
                .overlay(alignment: .top) {
                    ToastBanner()
                        .environmentObject(appState)
                }
        }
        .modelContainer(appState.container)
    }
}
