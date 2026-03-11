import Foundation
import SwiftData
import Ably

@Observable
final class AblyService {
    private(set) var isConnected = false
    private(set) var lastError: String?

    private var realtime: ARTRealtime?
    private var channel: ARTRealtimeChannel?
    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func connect() {
        let apiKey = AppSettings.shared.ablyApiKey
        let channelName = AppSettings.shared.channelName

        guard !apiKey.isEmpty else {
            lastError = "Ably API key not configured. Open Settings to enter it."
            return
        }

        disconnect()
        lastError = nil

        let options = ARTClientOptions(key: apiKey)
        options.clientId = "ipad-live-timeline"
        realtime = ARTRealtime(options: options)

        realtime?.connection.on { [weak self] stateChange in
            DispatchQueue.main.async {
                switch stateChange.current {
                case .connected:
                    self?.isConnected = true
                    self?.lastError = nil
                    print("✅ Ably connected")
                case .disconnected, .suspended:
                    self?.isConnected = false
                    print("⚠️ Ably disconnected: \(stateChange.reason?.message ?? "unknown")")
                case .failed:
                    self?.isConnected = false
                    self?.lastError = "Connection failed: \(stateChange.reason?.message ?? "unknown")"
                    print("❌ Ably failed: \(stateChange.reason?.message ?? "unknown")")
                default:
                    break
                }
            }
        }

        channel = realtime?.channels.get(channelName)
        fetchHistory()
        subscribe()
    }

    func disconnect() {
        channel?.unsubscribe()
        realtime?.close()
        realtime = nil
        channel = nil
        isConnected = false
    }

    private func fetchHistory() {
        let query = ARTRealtimeHistoryQuery()
        query.limit = 100

        do {
            try channel?.history(query) { [weak self] paginatedResult, error in
                guard let self else { return }

                if let error {
                    print("⚠️ History fetch error: \(error.message)")
                    return
                }

                guard let messages = paginatedResult?.items else {
                    print("📭 No history messages")
                    return
                }

                print("📜 Fetched \(messages.count) messages from history")
                for message in messages {
                    self.processMessage(message)
                }
            }
        } catch {
            print("⚠️ History query error: \(error)")
        }
    }

    private func subscribe() {
        channel?.subscribe { [weak self] message in
            print("📨 Received live message: \(message.name ?? "unnamed")")
            self?.processMessage(message)
        }
    }

    private func processMessage(_ message: ARTMessage) {
        guard let data = message.data else {
            print("⚠️ Skipped message with no data")
            return
        }

        do {
            let jsonData: Data

            if let dict = data as? NSDictionary {
                jsonData = try JSONSerialization.data(withJSONObject: dict)
            } else if let string = data as? String {
                guard let strData = string.data(using: .utf8) else {
                    print("⚠️ Skipped non-UTF8 message")
                    return
                }
                jsonData = strData
            } else {
                print("⚠️ Skipped message with unexpected data type: \(type(of: data))")
                return
            }

            let payload = try JSONDecoder().decode(EventPayload.self, from: jsonData)

            DispatchQueue.main.async { [weak self] in
                self?.processEvent(payload)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.lastError = "Skipped malformed message: \(error.localizedDescription)"
            }
            print("⚠️ Skipped malformed event: \(error)")
            print("Raw message data: \(data)")
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
