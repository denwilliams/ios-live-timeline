import Foundation
import SwiftData

@Model
final class TimelineEvent {
    @Attribute(.unique) var id: String
    var agentId: String
    var taskId: String
    var title: String
    var body: String
    var status: EventStatus
    var category: String
    var timestamp: Date
    var receivedAt: Date

    init(
        id: String,
        agentId: String,
        taskId: String,
        title: String,
        body: String,
        status: EventStatus,
        category: String,
        timestamp: Date
    ) {
        self.id = id
        self.agentId = agentId
        self.taskId = taskId
        self.title = title
        self.body = body
        self.status = status
        self.category = category
        self.timestamp = timestamp
        self.receivedAt = Date()
    }
}

enum EventStatus: String, Codable, CaseIterable {
    case info
    case inProgress = "in_progress"
    case success
    case warning
    case error

    var label: String {
        switch self {
        case .info: "Info"
        case .inProgress: "In Progress"
        case .success: "Success"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .info: "info.circle.fill"
        case .inProgress: "arrow.trianglehead.2.clockwise"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .info: "blue"
        case .inProgress: "yellow"
        case .success: "green"
        case .warning: "orange"
        case .error: "red"
        }
    }
}

struct EventPayload: Decodable {
    let id: String
    let agentId: String
    let taskId: String
    let title: String
    let body: String?
    let status: EventStatus
    let category: String?
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case id
        case agentId = "agent_id"
        case taskId = "task_id"
        case title, body, status, category, timestamp
    }
}
