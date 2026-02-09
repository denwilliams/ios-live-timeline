import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var redisURL: String {
        get { UserDefaults.standard.string(forKey: "redisURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "redisURL") }
    }

    var restURL: String {
        get { UserDefaults.standard.string(forKey: "restURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "restURL") }
    }

    var restToken: String {
        get { UserDefaults.standard.string(forKey: "restToken") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "restToken") }
    }

    var pollingInterval: TimeInterval {
        get {
            let saved = UserDefaults.standard.double(forKey: "pollingInterval")
            return saved == 0 ? 20 : saved
        }
        set { UserDefaults.standard.set(newValue, forKey: "pollingInterval") }
    }

    var isConfigured: Bool {
        !restURL.isEmpty && !restToken.isEmpty
    }

    private init() {}
}
