import SwiftUI

struct SettingsView: View {
    @Bindable var sqsService: SQSService
    @State private var queueURL: String = AppSettings.shared.queueURL
    @State private var accessKeyId: String = AppSettings.shared.accessKeyId
    @State private var secretAccessKey: String = AppSettings.shared.secretAccessKey
    @State private var region: String = AppSettings.shared.region

    var body: some View {
        Form {
            Section("AWS SQS Configuration") {
                TextField("Queue URL", text: $queueURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                TextField("Access Key ID", text: $accessKeyId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("Secret Access Key", text: $secretAccessKey)

                TextField("Region", text: $region)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section {
                Button("Save & Connect") {
                    save()
                    sqsService.stopPolling()
                    sqsService.startPolling()
                }
                .disabled(!isValid)

                if sqsService.isPolling {
                    Button("Disconnect", role: .destructive) {
                        sqsService.stopPolling()
                    }
                }
            }

            if let error = sqsService.lastError {
                Section("Status") {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    private var isValid: Bool {
        !queueURL.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty && !region.isEmpty
    }

    private func save() {
        AppSettings.shared.queueURL = queueURL
        AppSettings.shared.accessKeyId = accessKeyId
        AppSettings.shared.secretAccessKey = secretAccessKey
        AppSettings.shared.region = region
    }
}
