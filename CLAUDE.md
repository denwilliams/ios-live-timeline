# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iOS Live Timeline is an iPad app that displays real-time events from AI agents via Ably realtime. Agents push status updates to an Ably channel via REST API, and the iPad app subscribes via WebSocket for instant delivery.

**Key Architecture Points:**
- No backend server - agents publish directly to Ably REST API, iPad subscribes via WebSocket using ably-cocoa SDK
- Realtime WebSocket subscription for instant event delivery (no polling)
- 24h persisted channel history for catch-up on connect
- Local persistence via SwiftData
- Upsert behavior: events with the same `task_id` replace older events
- Events with future timestamps are treated as "upcoming" and displayed separately

## Project Structure

```
agent-tool/                  # Bash script for agents to publish events
  publish_event.sh          # Main script for publishing events to Ably channel (uses REST API)

ipad/LiveTimeline/          # Xcode project
  LiveTimeline/
    LiveTimelineApp.swift   # App entry point, tabs for Timeline and Settings
    Models/
      TimelineEvent.swift   # SwiftData model + EventStatus enum + EventPayload
    Services/
      AblyService.swift     # Ably realtime subscription + history fetch service
      AppSettings.swift     # User defaults for Ably API key & channel name
    Views/
      TimelineView.swift    # Main timeline UI
      EventRowView.swift    # Regular event row
      UpcomingEventRowView.swift  # Compact upcoming event row
      SettingsView.swift    # Ably credentials & channel configuration
```

## Development Commands

### Agent Tool (Bash)

Set up and publish test events:

```bash
cd agent-tool

# Set environment variable
export ABLY_API_KEY="appId.keyId:keySecret"

# Publish an event
./publish_event.sh --title "Test Event" --status info --agent-id test-agent

# Publish with full options
./publish_event.sh \
  --agent-id deployer \
  --task-id deploy-42 \
  --title "Deploying v1.3" \
  --body "Build #42 deploying to production" \
  --status in_progress \
  --category deployment \
  --channel my-channel
```

**Optional dependencies:**
- `jq` - For proper JSON escaping (recommended but not required)
- `uuidgen` - For generating UUIDs (available on macOS by default)

### iPad App (Xcode)

The iPad app is a standard Xcode project with no special build commands. Open `ipad/LiveTimeline/LiveTimeline.xcodeproj` in Xcode and build normally.

**Dependencies:** ably-cocoa Swift package (SPM)

**No testing infrastructure exists yet.**

## Event Payload Schema

Agents publish JSON to an Ably channel with this structure:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "agent_id": "code-reviewer",
  "task_id": "pr-review-123",
  "title": "PR Review Complete",
  "body": "Reviewed PR #123 — found 2 issues.",
  "status": "success",
  "category": "code-review",
  "timestamp": "2026-02-07T10:30:00Z"
}
```

**Required fields:** `id`, `agent_id`, `task_id`, `title`, `status`, `timestamp`

**Status values:** `info`, `in_progress`, `success`, `warning`, `error`

**Upsert behavior:** Events with matching `task_id` replace existing events. The iPad app finds the existing event by `task_id` and updates all fields, then sets `receivedAt` to the current time. This allows agents to send progressive updates without duplicating timeline entries.

**Upcoming events:** Events with `timestamp` in the future are displayed in a compact "Upcoming" section at the top of the timeline. They automatically move to the main timeline once their timestamp passes.

## Key Implementation Details

### AblyService Realtime Subscription

[AblyService.swift](ipad/LiveTimeline/LiveTimeline/Services/AblyService.swift) implements:
- WebSocket connection via `ARTRealtime` with connection state monitoring
- Channel subscription for live messages via `channel.subscribe`
- History fetch on connect: retrieves up to 100 persisted messages for catch-up
- Message processing: handles both `NSDictionary` and `String` data formats from Ably
- Upsert logic in `processEvent`: queries SwiftData for existing event by `task_id`, updates if found, inserts if new
- ISO 8601 timestamp parsing with fractional seconds fallback
- Connection state tracking (`isConnected`, `lastError`) for UI status display
- Automatic reconnection handled by ably-cocoa SDK

### SwiftData Model

[TimelineEvent.swift](ipad/LiveTimeline/LiveTimeline/Models/TimelineEvent.swift):
- `id` is marked `@Attribute(.unique)` but upsert is done via `task_id` query
- `isUpcoming` computed property: `timestamp > Date()`
- `EventStatus` enum maps to UI colors and system icons
- `EventPayload` is the decodable struct with snake_case JSON keys

### Ably Credentials

Stored in [AppSettings.swift](ipad/LiveTimeline/LiveTimeline/Services/AppSettings.swift) using UserDefaults:
- Ably API key (format: `appId.keyId:keySecret`)
- Channel name (default: `timeline-events`)

User enters these in the Settings tab. The app is considered configured when the API key is not empty.

## Future Enhancements

See [FUTURE_IDEAS.md](FUTURE_IDEAS.md) for a detailed roadmap including:
- Action buttons with webhooks for bidirectional agent interaction
- Apple Intelligence features (on-device LLM summarization, semantic search via Core Spotlight)
- Widgets (home screen, lock screen, Live Activities)
- Siri integration via App Intents
- Rich content (Markdown bodies, attachments, priority levels)
- Agent health monitoring and anomaly detection

## Ably Setup

1. Create an account at [ably.com](https://ably.com) and create a new app
2. Go to the app's **API Keys** tab and copy the API key (format: `appId.keyId:keySecret`)
3. Enable message persistence via a **channel rule**:
   - Go to **Settings > Channel rules**
   - Add a rule matching your channel (e.g., `timeline-events`)
   - Enable **Persist last message** or **Persist all messages** (24h retention)
4. Set environment variable for the agent tool:
   ```bash
   export ABLY_API_KEY="appId.keyId:keySecret"
   ```
5. Enter the same API key in the iPad app Settings tab
6. Optionally change the channel name (default: `timeline-events`) in both the agent tool (`--channel`) and iPad app Settings
