import Foundation
import SwiftData
import AWSSQS
import AWSSDKIdentity

@Observable
final class SQSService {
    private(set) var isPolling = false
    private(set) var lastError: String?
    private var pollingTask: Task<Void, Never>?

    private var client: SQSClient?
    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func startPolling() {
        guard pollingTask == nil else { return }

        let queueURL = AppSettings.shared.queueURL
        let accessKey = AppSettings.shared.accessKeyId
        let secretKey = AppSettings.shared.secretAccessKey
        let region = AppSettings.shared.region

        guard !queueURL.isEmpty, !accessKey.isEmpty, !secretKey.isEmpty else {
            lastError = "AWS credentials not configured. Open Settings to enter them."
            return
        }

        lastError = nil
        isPolling = true

        pollingTask = Task { [weak self] in
            do {
                let credentials = AWSCredentialIdentity(
                    accessKey: accessKey,
                    secret: secretKey
                )
                let resolver = try StaticAWSCredentialIdentityResolver(credentials)
                let config = try await SQSClient.SQSClientConfiguration(
                    awsCredentialIdentityResolver: resolver,
                    region: region
                )
                let sqsClient = SQSClient(config: config)
                self?.client = sqsClient

                while !Task.isCancelled {
                    await self?.poll(client: sqsClient, queueURL: queueURL)
                }
            } catch {
                await MainActor.run {
                    self?.lastError = "Failed to initialize SQS client: \(error.localizedDescription)"
                    self?.isPolling = false
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        client = nil
    }

    private func poll(client: SQSClient, queueURL: String) async {
        do {
            let input = ReceiveMessageInput(
                maxNumberOfMessages: 10,
                queueUrl: queueURL,
                waitTimeSeconds: 20
            )

            let output = try await client.receiveMessage(input: input)

            guard let messages = output.messages, !messages.isEmpty else {
                return
            }

            for message in messages {
                guard let body = message.body,
                      let data = body.data(using: .utf8) else {
                    continue
                }

                do {
                    let payload = try JSONDecoder().decode(EventPayload.self, from: data)
                    await processEvent(payload)

                    if let receiptHandle = message.receiptHandle {
                        let deleteInput = DeleteMessageInput(
                            queueUrl: queueURL,
                            receiptHandle: receiptHandle
                        )
                        _ = try await client.deleteMessage(input: deleteInput)
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.lastError = "Failed to decode message: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.lastError = "Poll error: \(error.localizedDescription)"
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @MainActor
    private func processEvent(_ payload: EventPayload) {
        guard let modelContext else { return }

        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = iso8601Formatter.date(from: payload.timestamp)
            ?? ISO8601DateFormatter().date(from: payload.timestamp)
            ?? Date()

        // Upsert: find existing event with same taskId and replace it
        let taskId = payload.taskId
        let fetchDescriptor = FetchDescriptor<TimelineEvent>(
            predicate: #Predicate { $0.taskId == taskId }
        )

        if let existing = try? modelContext.fetch(fetchDescriptor).first {
            existing.id = payload.id
            existing.agentId = payload.agentId
            existing.title = payload.title
            existing.body = payload.body ?? ""
            existing.status = payload.status
            existing.category = payload.category ?? ""
            existing.timestamp = timestamp
            existing.receivedAt = Date()
        } else {
            let event = TimelineEvent(
                id: payload.id,
                agentId: payload.agentId,
                taskId: payload.taskId,
                title: payload.title,
                body: payload.body ?? "",
                status: payload.status,
                category: payload.category ?? "",
                timestamp: timestamp
            )
            modelContext.insert(event)
        }

        try? modelContext.save()
    }
}
