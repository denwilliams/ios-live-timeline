# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iOS Live Timeline is an iPad app that displays real-time events from AI agents via Upstash Redis. Agents push status updates to a Redis list via REST API, and the iPad app polls the REST API to consume messages.

**Key Architecture Points:**
- No backend server - agents publish directly to Upstash Redis REST API, iPad consumes via REST API
- Redis list as queue (LPUSH to add, RPOP to consume)
- Configurable polling interval (5-60 seconds) with adaptive behavior
- Immediate retry when message received, wait interval when queue empty
- Local persistence via SwiftData
- Upsert behavior: events with the same `task_id` replace older events
- Events with future timestamps are treated as "upcoming" and displayed separately

## Project Structure

```
agent-tool/                  # Bash script for agents to publish events
  publish_event.sh          # Main script for publishing events to Upstash Redis (uses REST API)

ipad/LiveTimeline/          # Xcode project
  LiveTimeline/
    LiveTimelineApp.swift   # App entry point, tabs for Timeline and Settings
    Models/
      TimelineEvent.swift   # SwiftData model + EventStatus enum + EventPayload
    Services/
      UpstashQueueService.swift  # Upstash Redis REST API polling service
      AppSettings.swift     # User defaults for Upstash credentials & polling interval
    Views/
      TimelineView.swift    # Main timeline UI
      EventRowView.swift    # Regular event row
      UpcomingEventRowView.swift  # Compact upcoming event row
      SettingsView.swift    # Upstash credentials & polling interval configuration
```

## Development Commands

### Agent Tool (Bash)

Set up and publish test events:

```bash
cd agent-tool

# Set environment variables (REST API)
export UPSTASH_REDIS_URL="https://mutual-firefly-12345.upstash.io"
export UPSTASH_REDIS_TOKEN="your-rest-token-here"

# Publish an event
./publish_event.sh --title "Test Event" --status info --agent-id test-agent

# Publish with full options
./publish_event.sh \
  --agent-id deployer \
  --task-id deploy-42 \
  --title "Deploying v1.3" \
  --body "Build #42 deploying to production" \
  --status in_progress \
  --category deployment
```

**Optional dependencies:**
- `jq` - For proper JSON escaping (recommended but not required)
- `uuidgen` - For generating UUIDs (available on macOS by default)

### iPad App (Xcode)

The iPad app is a standard Xcode project with no special build commands. Open `ipad/LiveTimeline/LiveTimeline.xcodeproj` in Xcode and build normally.

**Dependencies:** None - uses URLSession for REST API calls

**No testing infrastructure exists yet.**

## Event Payload Schema

Agents publish JSON to Upstash Redis with this structure:

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

### UpstashQueueService Polling Logic

[UpstashQueueService.swift](ipad/LiveTimeline/LiveTimeline/Services/UpstashQueueService.swift) implements:
- REST API polling using RPOP command
- Continuous polling loop that runs until cancelled
- Adaptive polling: immediate retry when message received, configurable wait when queue empty
- Configurable polling interval (5-60s, default 20s)
- Upsert logic in `processEvent`: queries SwiftData for existing event by `task_id`, updates if found, inserts if new
- Simple REST API using URLSession (no external dependencies)
- Error handling with 5-second backoff on failures

### SwiftData Model

[TimelineEvent.swift](ipad/LiveTimeline/LiveTimeline/Models/TimelineEvent.swift):
- `id` is marked `@Attribute(.unique)` but upsert is done via `task_id` query
- `isUpcoming` computed property: `timestamp > Date()`
- `EventStatus` enum maps to UI colors and system icons
- `EventPayload` is the decodable struct with snake_case JSON keys

### Upstash Redis Credentials

Stored in [AppSettings.swift](ipad/LiveTimeline/LiveTimeline/Services/AppSettings.swift) using `@AppStorage` (UserDefaults):
- REST URL (e.g., `https://mutual-firefly-12345.upstash.io`)
- REST Token (bearer token)
- Polling Interval (5-60 seconds, default 20)

User enters these in the Settings tab. No validation beyond "not empty".

## API Usage Calculations

**Polling Interval Estimates:**
- 20s: 3 req/min × 60 × 24 × 30 = ~130K requests/month
- 30s: 2 req/min × 60 × 24 × 30 = ~86K requests/month
- 60s: 1 req/min × 60 × 24 × 30 = ~43K requests/month

Upstash free tier: 300K requests/month (10K/day)

## Future Enhancements

See [FUTURE_IDEAS.md](FUTURE_IDEAS.md) for a detailed roadmap including:
- Action buttons with webhooks for bidirectional agent interaction
- Apple Intelligence features (on-device LLM summarization, semantic search via Core Spotlight)
- Widgets (home screen, lock screen, Live Activities)
- Siri integration via App Intents
- Rich content (Markdown bodies, attachments, priority levels)
- Agent health monitoring and anomaly detection

## Upstash Setup

1. Create a Redis database at [console.upstash.com](https://console.upstash.com/redis)
2. Go to the **REST API** tab
3. Copy the REST URL (e.g., `https://mutual-firefly-12345.upstash.io`)
4. Copy the REST token
5. Set environment variables for the agent tool:
   ```bash
   export UPSTASH_REDIS_URL="https://mutual-firefly-12345.upstash.io"
   export UPSTASH_REDIS_TOKEN="your-rest-token-here"
   ```
6. Enter the same credentials in the iPad app Settings tab
7. Optionally adjust polling interval (default 20s)
