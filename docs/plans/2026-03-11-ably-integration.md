# Ably Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Upstash Redis polling with Ably realtime messaging so agents publish events instantly to the iPad via WebSocket, with 24h persisted history for catch-up on reconnect.

**Architecture:** Agents publish JSON events to Ably channel `timeline-events` via REST API (curl). iPad subscribes via ably-cocoa SDK for instant delivery. On startup, iPad fetches channel history (up to 24h with persistence enabled) to catch up on missed events. Existing SwiftData upsert logic handles deduplication.

**Tech Stack:** ably-cocoa Swift SDK, Ably REST API, curl, SwiftData

---

### Task 1: Add ably-cocoa Swift Package to Xcode Project

**Files:**
- Modify: `ipad/LiveTimeline/LiveTimeline.xcodeproj/project.pbxproj`

**Step 1: Add the Swift Package dependency in Xcode**

Open `ipad/LiveTimeline/LiveTimeline.xcodeproj` in Xcode, then:
1. File → Add Package Dependencies
2. Enter URL: `https://github.com/ably/ably-cocoa`
3. Set version rule: "Up to Next Major" from `1.2.58`
4. Add `Ably` library to the `LiveTimeline` target

**Step 2: Verify it compiles**

Build the project in Xcode (Cmd+B). Expected: clean build with no errors.

**Step 3: Commit**

```bash
git add ipad/LiveTimeline/LiveTimeline.xcodeproj
git commit -m "feat: add ably-cocoa Swift package dependency"
```

---

### Task 2: Replace AppSettings for Ably

**Files:**
- Modify: `ipad/LiveTimeline/LiveTimeline/Services/AppSettings.swift`

**Step 1: Replace Upstash settings with Ably API key**

Replace the entire contents of `AppSettings.swift` with:

```swift
import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var ablyApiKey: String {
        get { UserDefaults.standard.string(forKey: "ablyApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ablyApiKey") }
    }

    var channelName: String {
        get { UserDefaults.standard.string(forKey: "channelName") ?? "timeline-events" }
        set { UserDefaults.standard.set(newValue, forKey: "channelName") }
    }

    var isConfigured: Bool {
        !ablyApiKey.isEmpty
    }

    private init() {}
}
```

**Step 2: Verify it compiles**

Build in Xcode. Expected: compile errors in files that reference old properties (SettingsView, UpstashQueueService). This is expected — we fix those next.

**Step 3: Commit**

```bash
git add ipad/LiveTimeline/LiveTimeline/Services/AppSettings.swift
git commit -m "feat: replace Upstash settings with Ably API key"
```

---

### Task 3: Create AblyService to replace UpstashQueueService

**Files:**
- Create: `ipad/LiveTimeline/LiveTimeline/Services/AblyService.swift`
- Delete: `ipad/LiveTimeline/LiveTimeline/Services/UpstashQueueService.swift`

**Step 1: Create AblyService.swift**

Create the file at `ipad/LiveTimeline/LiveTimeline/Services/AblyService.swift` with:

```swift
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

        // Disconnect existing connection if any
        disconnect()

        lastError = nil

        let options = ARTClientOptions(key: apiKey)
        options.clientId = "ipad-live-timeline"
        realtime = ARTRealtime(options: options)

        // Monitor connection state
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

        // Get channel and fetch history before subscribing
        channel = realtime?.channels.get(channelName)

        // Fetch persisted history (up to 24h on free tier)
        fetchHistory()

        // Subscribe to live messages
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
        // message.data can be a String, NSDictionary, or NSArray
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
```

**Step 2: Delete UpstashQueueService.swift**

Remove the old file:

```bash
git rm ipad/LiveTimeline/LiveTimeline/Services/UpstashQueueService.swift
```

**Step 3: Commit**

```bash
git add ipad/LiveTimeline/LiveTimeline/Services/AblyService.swift
git commit -m "feat: add AblyService with realtime subscription and history fetch"
```

---

### Task 4: Update LiveTimelineApp to use AblyService

**Files:**
- Modify: `ipad/LiveTimeline/LiveTimeline/LiveTimelineApp.swift`

**Step 1: Replace UpstashQueueService with AblyService**

Replace the entire contents with:

```swift
import SwiftUI
import SwiftData

@main
struct LiveTimelineApp: App {
    @State private var ablyService = AblyService()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    TimelineView(ablyService: ablyService)
                        .navigationTitle("Timeline")
                }
                .tabItem {
                    Label("Timeline", systemImage: "clock")
                }

                NavigationStack {
                    SettingsView(ablyService: ablyService)
                        .navigationTitle("Settings")
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .modelContainer(for: TimelineEvent.self)
    }
}
```

**Step 2: Verify it compiles (will fail until views are updated)**

Expected: compile errors in TimelineView and SettingsView referencing old types.

**Step 3: Commit**

```bash
git add ipad/LiveTimeline/LiveTimeline/LiveTimelineApp.swift
git commit -m "feat: wire up AblyService in app entry point"
```

---

### Task 5: Update SettingsView for Ably

**Files:**
- Modify: `ipad/LiveTimeline/LiveTimeline/Views/SettingsView.swift`

**Step 1: Replace settings UI**

Replace the entire contents with:

```swift
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
```

**Step 2: Commit**

```bash
git add ipad/LiveTimeline/LiveTimeline/Views/SettingsView.swift
git commit -m "feat: update SettingsView for Ably API key"
```

---

### Task 6: Update TimelineView to use AblyService

**Files:**
- Modify: `ipad/LiveTimeline/LiveTimeline/Views/TimelineView.swift`

**Step 1: Replace all references to UpstashQueueService/queueService**

In `TimelineView.swift`, make these changes:

1. Change `@Bindable var queueService: UpstashQueueService` → `@Bindable var ablyService: AblyService`
2. In `.onAppear`, change `queueService.configure(...)` → `ablyService.configure(...)` and `queueService.startPolling()` → `ablyService.connect()`
3. In `statusBar`, change `queueService.isPolling` → `ablyService.isConnected` and `queueService.lastError` → `ablyService.lastError`

Full replacement for the affected properties and methods:

Change the property:
```swift
@Bindable var ablyService: AblyService
```

Change `.onAppear`:
```swift
.onAppear {
    ablyService.configure(modelContext: modelContext)
    if AppSettings.shared.isConfigured {
        ablyService.connect()
    }
}
```

Change `statusBar`:
```swift
private var statusBar: some View {
    HStack {
        Circle()
            .fill(ablyService.isConnected ? .green : .red)
            .frame(width: 8, height: 8)
        Text(ablyService.isConnected ? "Connected" : "Disconnected")
            .font(.caption)
            .foregroundStyle(.secondary)

        if let error = ablyService.lastError {
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
```

**Step 2: Build and verify**

Build in Xcode (Cmd+B). Expected: clean build, no errors.

**Step 3: Commit**

```bash
git add ipad/LiveTimeline/LiveTimeline/Views/TimelineView.swift
git commit -m "feat: update TimelineView to use AblyService"
```

---

### Task 7: Update publish_event.sh for Ably REST API

**Files:**
- Modify: `agent-tool/publish_event.sh`

**Step 1: Replace the script**

Replace the entire contents of `publish_event.sh` with:

```bash
#!/bin/bash

# publish_event.sh - Publish events to Ably channel for iOS Live Timeline
#
# Usage:
#   export ABLY_API_KEY="appId.keyId:keySecret"
#   ./publish_event.sh --title "Event Title" --status info --agent-id my-agent
#
# Options:
#   --agent-id      Agent identifier (required)
#   --task-id       Task identifier (default: random UUID)
#   --title         Event title (required)
#   --body          Event body text (optional)
#   --status        Status: info|in_progress|success|warning|error (required)
#   --category      Category label (optional)
#   --timestamp     ISO 8601 timestamp (default: now)
#   --channel       Ably channel name (default: timeline-events)

set -e

# Parse arguments
AGENT_ID=""
TASK_ID=""
TITLE=""
BODY=""
STATUS=""
CATEGORY=""
TIMESTAMP=""
CHANNEL="timeline-events"

while [[ $# -gt 0 ]]; do
  case $1 in
    --agent-id)
      AGENT_ID="$2"
      shift 2
      ;;
    --task-id)
      TASK_ID="$2"
      shift 2
      ;;
    --title)
      TITLE="$2"
      shift 2
      ;;
    --body)
      BODY="$2"
      shift 2
      ;;
    --status)
      STATUS="$2"
      shift 2
      ;;
    --category)
      CATEGORY="$2"
      shift 2
      ;;
    --timestamp)
      TIMESTAMP="$2"
      shift 2
      ;;
    --channel)
      CHANNEL="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$ABLY_API_KEY" ]]; then
  echo "Error: ABLY_API_KEY environment variable not set"
  exit 1
fi

if [[ -z "$AGENT_ID" ]]; then
  echo "Error: --agent-id is required"
  exit 1
fi

if [[ -z "$TITLE" ]]; then
  echo "Error: --title is required"
  exit 1
fi

if [[ -z "$STATUS" ]]; then
  echo "Error: --status is required"
  exit 1
fi

# Set defaults
if [[ -z "$TASK_ID" ]]; then
  if command -v uuidgen &> /dev/null; then
    TASK_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  else
    TASK_ID=$(cat /proc/sys/kernel/random/uuid)
  fi
fi

if [[ -z "$TIMESTAMP" ]]; then
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

# Generate event ID
if command -v uuidgen &> /dev/null; then
  EVENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
  EVENT_ID=$(cat /proc/sys/kernel/random/uuid)
fi

# Build JSON payload
if command -v jq &> /dev/null; then
  EVENT_DATA=$(jq -n \
    --arg id "$EVENT_ID" \
    --arg agent_id "$AGENT_ID" \
    --arg task_id "$TASK_ID" \
    --arg title "$TITLE" \
    --arg body "$BODY" \
    --arg status "$STATUS" \
    --arg category "$CATEGORY" \
    --arg timestamp "$TIMESTAMP" \
    '{
      id: $id,
      agent_id: $agent_id,
      task_id: $task_id,
      title: $title,
      body: $body,
      status: $status,
      category: $category,
      timestamp: $timestamp
    } | with_entries(select(.value != ""))')
else
  EVENT_DATA="{\"id\":\"$EVENT_ID\",\"agent_id\":\"$AGENT_ID\",\"task_id\":\"$TASK_ID\",\"title\":\"$TITLE\""
  [[ -n "$BODY" ]] && EVENT_DATA="$EVENT_DATA,\"body\":\"$BODY\""
  EVENT_DATA="$EVENT_DATA,\"status\":\"$STATUS\""
  [[ -n "$CATEGORY" ]] && EVENT_DATA="$EVENT_DATA,\"category\":\"$CATEGORY\""
  EVENT_DATA="$EVENT_DATA,\"timestamp\":\"$TIMESTAMP\"}"
fi

# Build Ably publish request body
# name = event name (used for filtering), data = the JSON payload
REQUEST_BODY=$(jq -n --arg name "event" --argjson data "$EVENT_DATA" '{name: $name, data: $data}')

# Publish to Ably REST API
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "https://rest.ably.io/channels/$CHANNEL/messages" \
  -u "$ABLY_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_BODY")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" =~ ^2 ]]; then
  echo "✓ Event published: $TITLE (task_id: $TASK_ID)"
else
  echo "✗ Failed to publish event (HTTP $HTTP_CODE)"
  echo "$RESPONSE_BODY"
  exit 1
fi
```

**Step 2: Test the script (requires valid ABLY_API_KEY)**

```bash
export ABLY_API_KEY="your-key-here"
./agent-tool/publish_event.sh --title "Test Event" --status info --agent-id test-agent
```

Expected: `✓ Event published: Test Event (task_id: ...)`

**Step 3: Commit**

```bash
git add agent-tool/publish_event.sh
git commit -m "feat: update publish_event.sh for Ably REST API"
```

---

### Task 8: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update all sections**

Replace the full contents of `CLAUDE.md` to reflect:
- Architecture: Ably realtime (not Upstash Redis polling)
- Project structure: `AblyService.swift` (not `UpstashQueueService.swift`)
- Agent tool: `ABLY_API_KEY` env var, Ably REST API
- Credentials: single Ably API key (not REST URL + token + polling interval)
- Setup instructions: Ably account, channel rule for persistence
- Remove API usage calculations section (no polling)
- Dependencies: ably-cocoa Swift package

Key sections to update:
- **Project Overview**: "via Ably realtime" not "via Upstash Redis"
- **Key Architecture Points**: realtime WebSocket, 24h persisted history, no polling
- **Project Structure**: `AblyService.swift` not `UpstashQueueService.swift`
- **Development Commands / Agent Tool**: `ABLY_API_KEY` env var, same CLI usage
- **Dependencies**: `ably-cocoa` Swift package
- **Key Implementation Details**: replace UpstashQueueService section with AblyService section
- **Credentials**: single API key, stored in UserDefaults
- **Setup**: Ably account, enable persistence channel rule, copy API key
- **Remove**: API Usage Calculations section, Upstash Setup section

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for Ably integration"
```

---

### Task 9: Update design doc

**Files:**
- Modify: `docs/plans/2026-03-11-ably-integration-design.md`

**Step 1: Update design doc**

Update the design doc to reflect the final approach:
- Remove references to Ably Queues / AMQP
- Document that we use channel history with persistence (24h on free tier) instead
- Note the one-time Ably dashboard setup: enable persistence via channel rule

**Step 2: Commit**

```bash
git add docs/plans/2026-03-11-ably-integration-design.md
git commit -m "docs: update design doc to reflect history-based approach"
```

---

### Task 10: End-to-end test

**Step 1: Configure Ably in iPad app**

1. Open the app in Xcode, build and run on iPad/simulator
2. Go to Settings tab
3. Enter your Ably API key
4. Tap "Save & Connect"
5. Verify status shows "Connected" with green dot

**Step 2: Publish a test event**

```bash
export ABLY_API_KEY="your-key-here"
./agent-tool/publish_event.sh --title "Hello from Ably" --status success --agent-id test-agent
```

Expected: event appears on iPad instantly.

**Step 3: Test history catch-up**

1. Publish a few events while iPad app is closed
2. Reopen iPad app
3. Verify the events appear (fetched from 24h history)

**Step 4: Test upsert**

```bash
./agent-tool/publish_event.sh --title "Deploy started" --status in_progress --agent-id deployer --task-id deploy-1
./agent-tool/publish_event.sh --title "Deploy complete" --status success --agent-id deployer --task-id deploy-1
```

Expected: single event on timeline showing "Deploy complete" with success status.

**Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: adjustments from end-to-end testing"
```
