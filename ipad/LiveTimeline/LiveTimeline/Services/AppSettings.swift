import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var ablyApiKey: String {
        get { UserDefaults.standard.string(forKey: "ablyApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ablyApiKey") }
    }

    var channelName: String {
        get { UserDefaults.standard.string(forKey: "channelName") ?? "timeline-events" }
        set { UserDefaults.standard.set(newValue, forKey: "channelName") }
    }

    var isConfigured: Bool {
        !ablyApiKey.isEmpty
    }

    private init() {}
}
