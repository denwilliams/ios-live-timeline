import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var queueURL: String {
        get { UserDefaults.standard.string(forKey: "queueURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "queueURL") }
    }

    var accessKeyId: String {
        get { UserDefaults.standard.string(forKey: "accessKeyId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "accessKeyId") }
    }

    var secretAccessKey: String {
        get { UserDefaults.standard.string(forKey: "secretAccessKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "secretAccessKey") }
    }

    var region: String {
        get { UserDefaults.standard.string(forKey: "awsRegion") ?? "us-east-1" }
        set { UserDefaults.standard.set(newValue, forKey: "awsRegion") }
    }

    var isConfigured: Bool {
        !queueURL.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty
    }

    private init() {}
}
