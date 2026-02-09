import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimelineEvent.receivedAt, order: .reverse) private var events: [TimelineEvent]
    @State private var searchText = ""
    @State private var statusFilter: EventStatus?
    @Bindable var sqsService: SQSService

    private var filteredEvents: [TimelineEvent] {
        events.filter { event in
            let matchesSearch = searchText.isEmpty
                || event.title.localizedCaseInsensitiveContains(searchText)
                || event.body.localizedCaseInsensitiveContains(searchText)
                || event.agentId.localizedCaseInsensitiveContains(searchText)
                || event.category.localizedCaseInsensitiveContains(searchText)

            let matchesStatus = statusFilter == nil || event.status == statusFilter

            return matchesSearch && matchesStatus
        }
    }

    private var upcomingEvents: [TimelineEvent] {
        filteredEvents
            .filter { $0.isUpcoming }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var pastEvents: [TimelineEvent] {
        filteredEvents.filter { !$0.isUpcoming }
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            filterBar

            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Events Yet" : "No Results",
                    systemImage: searchText.isEmpty ? "clock" : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "Events from your agents will appear here."
                            : "Try a different search term or filter."
                    )
                )
            } else {
                List {
                    if !upcomingEvents.isEmpty {
                        Section {
                            ForEach(upcomingEvents) { event in
                                UpcomingEventRowView(event: event)
                            }
                        } header: {
                            Label("Upcoming", systemImage: "calendar")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .textCase(nil)
                        }
                    }

                    if !pastEvents.isEmpty {
                        Section {
                            ForEach(pastEvents) { event in
                                EventRowView(event: event)
                            }
                        } header: {
                            if !upcomingEvents.isEmpty {
                                Label("Timeline", systemImage: "clock")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .textCase(nil)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search events")
        .onAppear {
            sqsService.configure(modelContext: modelContext)
            if AppSettings.shared.isConfigured {
                sqsService.startPolling()
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(sqsService.isPolling ? .green : .red)
                .frame(width: 8, height: 8)
            Text(sqsService.isPolling ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = sqsService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(events.count) events")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: statusFilter == nil) {
                    statusFilter = nil
                }

                ForEach(EventStatus.allCases, id: \.self) { status in
                    FilterChip(
                        label: status.label,
                        systemImage: status.systemImage,
                        isSelected: statusFilter == status
                    ) {
                        statusFilter = status
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

struct FilterChip: View {
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                }
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
}
