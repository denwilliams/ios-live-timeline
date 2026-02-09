import SwiftUI
import SwiftData

@main
struct LiveTimelineApp: App {
    @State private var sqsService = SQSService()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    TimelineView(sqsService: sqsService)
                        .navigationTitle("Timeline")
                }
                .tabItem {
                    Label("Timeline", systemImage: "clock")
                }

                NavigationStack {
                    SettingsView(sqsService: sqsService)
                        .navigationTitle("Settings")
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .modelContainer(for: TimelineEvent.self)
    }
}
