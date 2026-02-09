import SwiftUI

struct EventRowView: View {
    let event: TimelineEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.status.systemImage)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.headline)

                    Spacer()

                    Text(event.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !event.body.isEmpty {
                    Text(event.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    Label(event.agentId, systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if !event.category.isEmpty {
                        Text(event.category)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }

                    if event.status == .inProgress {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
