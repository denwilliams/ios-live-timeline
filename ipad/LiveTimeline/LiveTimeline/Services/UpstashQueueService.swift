import Foundation
import SwiftData

@Observable
final class UpstashQueueService {
    private(set) var isPolling = false
    private(set) var lastError: String?
    private var pollingTask: Task<Void, Never>?

    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func startPolling() {
        guard pollingTask == nil else { return }

        let redisURL = AppSettings.shared.redisURL
        let restURL = AppSettings.shared.restURL
        let restToken = AppSettings.shared.restToken

        guard !restURL.isEmpty, !restToken.isEmpty else {
            lastError = "Upstash REST API credentials not configured. Open Settings to enter them."
            return
        }

        lastError = nil
        isPolling = true

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll(restURL: restURL, restToken: restToken)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    private func poll(restURL: String, restToken: String) async {
        // Upstash REST API: GET /rpop/key
        guard let url = URL(string: "\(restURL)/rpop/timeline-events") else {
            await MainActor.run { [weak self] in
                self?.lastError = "Invalid REST URL"
                self?.isPolling = false
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(restToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run { [weak self] in
                    self?.lastError = "Invalid response type"
                }
                try? await Task.sleep(for: .seconds(AppSettings.shared.pollingInterval))
                return
            }

            guard httpResponse.statusCode == 200 else {
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        self?.lastError = "HTTP \(httpResponse.statusCode): \(String(data: data, encoding: .utf8) ?? "unknown error")"
                    }
                    try? await Task.sleep(for: .seconds(5))
                }
                return
            }

            // Upstash Redis RPOP returns {"result": <value>} or {"result": null}
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = jsonObject["result"] {

                // Check if result is null
                if result is NSNull {
                    // No messages available, wait before polling again
                    try? await Task.sleep(for: .seconds(AppSettings.shared.pollingInterval))
                    return
                }

                // Parse the result into event payloads
                do {
                    let payloads = try parseRedisResult(result)

                    // Process each event
                    for payload in payloads {
                        await processEvent(payload)
                    }

                    // Clear any previous errors
                    await MainActor.run { [weak self] in
                        self?.lastError = nil
                    }
                    // Got messages, poll immediately for next one
                    return
                } catch {
                    // Log the error but don't stop processing - skip this message and continue
                    await MainActor.run { [weak self] in
                        self?.lastError = "Skipped malformed message: \(error.localizedDescription)\nRaw: \(String(describing: result).prefix(100))..."
                    }
                    print("⚠️ Skipped malformed event: \(error)")
                    print("Raw message: \(result)")
                    // Got a message (even if malformed), poll immediately for next one
                    return
                }
            }

            // No messages available, wait before polling again
            try? await Task.sleep(for: .seconds(AppSettings.shared.pollingInterval))
        } catch {
            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.lastError = "Poll error: \(error.localizedDescription)"
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func parseRedisResult(_ result: Any) throws -> [EventPayload] {
        print("🔍 Result type: \(type(of: result))")

        // Handle different result types
        if let resultDict = result as? [String: Any] {
            // Result is a single JSON object
            print("📦 Result is a dictionary")
            let data = try JSONSerialization.data(withJSONObject: resultDict)
            let payload = try JSONDecoder().decode(EventPayload.self, from: data)
            return [payload]
        } else if let resultArray = result as? [Any] {
            // Result is an array - could contain objects or strings
            print("📦 Result is an array with \(resultArray.count) elements")

            var payloads: [EventPayload] = []
            for item in resultArray {
                if let itemDict = item as? [String: Any] {
                    // Array element is a dictionary
                    print("📦 Array element is a dictionary")
                    let data = try JSONSerialization.data(withJSONObject: itemDict)
                    let payload = try JSONDecoder().decode(EventPayload.self, from: data)
                    payloads.append(payload)
                } else if let itemString = item as? String {
                    // Array element is a string (JSON-encoded)
                    print("📦 Array element is a string: \(itemString.prefix(100))")
                    guard let data = itemString.data(using: .utf8) else {
                        throw NSError(domain: "UpstashQueueService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert string to UTF8"])
                    }
                    let payload = try JSONDecoder().decode(EventPayload.self, from: data)
                    payloads.append(payload)
                } else {
                    print("📦 Array element is: \(String(describing: item)) of type \(type(of: item))")
                    throw NSError(domain: "UpstashQueueService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown array element type"])
                }
            }
            return payloads
        } else if let resultString = result as? String {
            // Result is a string (could be JSON-encoded object or array)
            print("📦 Result is a string: \(resultString.prefix(100))")
            guard let data = resultString.data(using: .utf8) else {
                throw NSError(domain: "UpstashQueueService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert string to UTF8"])
            }

            // Parse the string as JSON to see if it's an object or array
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                // Recursively parse the result
                return try parseRedisResult(jsonObject)
            } else {
                // Not valid JSON, try decoding directly
                let payload = try JSONDecoder().decode(EventPayload.self, from: data)
                return [payload]
            }
        } else {
            throw NSError(domain: "UpstashQueueService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected result type: \(type(of: result))"])
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

private struct RedisResponse: Decodable {
    let result: String?
}
