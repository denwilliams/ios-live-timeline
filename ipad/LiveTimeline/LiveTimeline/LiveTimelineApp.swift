import SwiftUI
import SwiftData

@main
struct LiveTimelineApp: App {
    @State private var queueService = UpstashQueueService()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    TimelineView(queueService: queueService)
                        .navigationTitle("Timeline")
                }
                .tabItem {
                    Label("Timeline", systemImage: "clock")
                }

                NavigationStack {
                    SettingsView(queueService: queueService)
                        .navigationTitle("Settings")
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            }
            .onAppear {
                // Keep screen awake while app is running
                UIApplication.shared.isIdleTimerDisabled = true
                print("🔋 Screen idle timer disabled: \(UIApplication.shared.isIdleTimerDisabled)")
            }
            .onDisappear {
                // Re-enable idle timer when app goes to background
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .modelContainer(for: TimelineEvent.self)
    }
}
