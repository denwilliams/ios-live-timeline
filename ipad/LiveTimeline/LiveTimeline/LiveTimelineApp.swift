import SwiftUI
import SwiftData

@main
struct LiveTimelineApp: App {
    @State private var ablyService = AblyService()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    TimelineView(ablyService: ablyService)
                        .navigationTitle("Timeline")
                }
                .tabItem {
                    Label("Timeline", systemImage: "clock")
                }

                NavigationStack {
                    SettingsView(ablyService: ablyService)
                        .navigationTitle("Settings")
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .modelContainer(for: TimelineEvent.self)
    }
}
