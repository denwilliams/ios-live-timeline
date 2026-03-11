import SwiftUI

struct SettingsView: View {
    @Bindable var ablyService: AblyService
    @State private var ablyApiKey: String = AppSettings.shared.ablyApiKey
    @State private var channelName: String = AppSettings.shared.channelName

    var body: some View {
        Form {
            Section {
                SecureField("API Key", text: $ablyApiKey)
                    .font(.system(.body, design: .monospaced))

                TextField("Channel Name", text: $channelName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Ably")
            } footer: {
                Text("Get your API key from ably.com → Your App → API Keys.\nChannel name defaults to \"timeline-events\".")
                    .font(.caption)
            }

            Section {
                Button("Save & Connect") {
                    save()
                    ablyService.connect()
                }
                .disabled(!isValid)

                if ablyService.isConnected {
                    Button("Disconnect", role: .destructive) {
                        ablyService.disconnect()
                    }
                }
            }

            if let error = ablyService.lastError {
                Section("Status") {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    private var isValid: Bool {
        !ablyApiKey.isEmpty
    }

    private func save() {
        AppSettings.shared.ablyApiKey = ablyApiKey
        AppSettings.shared.channelName = channelName
    }
}
