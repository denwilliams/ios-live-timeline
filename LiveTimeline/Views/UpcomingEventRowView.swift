import SwiftUI

struct UpcomingEventRowView: View {
    let event: TimelineEvent

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E d MMM"
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.status.systemImage)
                .font(.caption)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 0) {
                Text(formattedTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Spacer()

            Text(event.agentId)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if !event.category.isEmpty {
                Text(event.category)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private var formattedTime: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(event.timestamp) {
            return "Today \(Self.timeFormatter.string(from: event.timestamp))"
        } else if calendar.isDateInTomorrow(event.timestamp) {
            return "Tomorrow \(Self.timeFormatter.string(from: event.timestamp))"
        } else {
            return "\(Self.dateFormatter.string(from: event.timestamp)) \(Self.timeFormatter.string(from: event.timestamp))"
        }
    }

    private var statusColor: Color {
        switch event.status {
        case .info: .blue
        case .inProgress: .yellow
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
