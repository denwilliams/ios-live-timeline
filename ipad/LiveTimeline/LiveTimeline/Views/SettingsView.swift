import SwiftUI

struct SettingsView: View {
    @Bindable var queueService: UpstashQueueService
    @State private var restURL: String = AppSettings.shared.restURL
    @State private var restToken: String = AppSettings.shared.restToken
    @State private var pollingInterval: Double = AppSettings.shared.pollingInterval

    var body: some View {
        Form {
            Section {
                TextField("REST URL", text: $restURL, axis: .vertical)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...4)

                SecureField("REST Token", text: $restToken)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Upstash Redis REST API")
            } footer: {
                Text("Get your REST URL and token from console.upstash.com/redis → REST API tab")
                    .font(.caption)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Polling Interval: \(Int(pollingInterval))s")
                        .font(.subheadline)

                    Slider(value: $pollingInterval, in: 5...60, step: 5) {
                        Text("Interval")
                    } minimumValueLabel: {
                        Text("5s")
                            .font(.caption2)
                    } maximumValueLabel: {
                        Text("60s")
                            .font(.caption2)
                    }
                }
            } header: {
                Text("Performance")
            } footer: {
                Text("How often to check for new events. Lower = more responsive, higher = fewer API requests.\n\n20s ≈ 130K requests/month\n30s ≈ 86K requests/month\n60s ≈ 43K requests/month")
                    .font(.caption)
            }

            Section {
                Button("Save & Connect") {
                    save()
                    queueService.stopPolling()
                    queueService.startPolling()
                }
                .disabled(!isValid)

                if queueService.isPolling {
                    Button("Disconnect", role: .destructive) {
                        queueService.stopPolling()
                    }
                }
            }

            if let error = queueService.lastError {
                Section("Status") {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    private var isValid: Bool {
        !restURL.isEmpty && !restToken.isEmpty
    }

    private func save() {
        AppSettings.shared.restURL = restURL
        AppSettings.shared.restToken = restToken
        AppSettings.shared.pollingInterval = pollingInterval
    }
}
