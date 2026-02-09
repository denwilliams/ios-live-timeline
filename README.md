# iOS Live Timeline

An iPad app that displays a real-time timeline of events pushed by AI agents via Upstash Redis.

Background AI agents work on tasks and push status updates to an Upstash Redis list. The iPad app polls the REST API to consume messages.

## Architecture

```
AI Agent ──→ [publish_event.sh] ──→ Upstash Redis ──→ iPad App (RPOP polling)
                (LPUSH via REST)         (list)         (REST API, configurable interval)
                                                            │
                                                      SwiftData (local)
                                                            │
                                                      Timeline UI
```

- **No backend server.** Agents push directly to Upstash Redis REST API. iPad consumes via REST API.
- **Redis list as queue** - LPUSH to add, RPOP to consume (FIFO ordering)
- **Configurable polling** (5-60s interval) - balance responsiveness vs API usage
- **Local persistence** via SwiftData — events survive app restarts
- **Upsert behavior** — events with the same `task_id` replace older events

## Event Payload Format

Agents publish JSON messages to the Redis list:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "agent_id": "code-reviewer",
  "task_id": "pr-review-123",
  "title": "PR Review Complete",
  "body": "Reviewed PR #123 — found 2 issues that need attention.",
  "status": "success",
  "category": "code-review",
  "timestamp": "2026-02-07T10:30:00Z"
}
```

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string (UUID) | Yes | Unique event identifier |
| `agent_id` | string | Yes | Identifies which agent sent the event |
| `task_id` | string | Yes | Groups events by task — same `task_id` triggers upsert |
| `title` | string | Yes | Short summary shown in the timeline |
| `body` | string | No | Detailed message (can be empty) |
| `status` | string | Yes | One of: `info`, `in_progress`, `success`, `warning`, `error` |
| `category` | string | No | Free-text category for filtering (e.g. `code-review`, `email`, `deploy`) |
| `timestamp` | string (ISO 8601) | Yes | When the event occurred (or is scheduled to occur) |

### Status Values

| Status | Meaning | UI Treatment |
|--------|---------|--------------|
| `info` | General information | Blue |
| `in_progress` | Task is actively being worked on | Yellow |
| `success` | Task completed successfully | Green |
| `warning` | Completed with warnings or needs attention | Orange |
| `error` | Task failed | Red |

### Upcoming Events

Events with a future `timestamp` are treated as upcoming (e.g. calendar appointments, scheduled deploys). They appear in a compact section at the top of the timeline, sorted soonest-first. Once their timestamp passes, they move into the regular timeline automatically.

### Upsert Behavior

When the app receives an event whose `task_id` matches an existing event, the old event is **replaced** (not duplicated). The new event appears at the top of the timeline. This lets agents send progressive updates for long-running tasks without cluttering the timeline.

## Setup

### 1. Upstash Redis

1. Create a Redis database at [console.upstash.com](https://console.upstash.com/redis)
2. Go to the **REST API** tab
3. Copy the **REST URL** (e.g., `https://mutual-firefly-12345.upstash.io`)
4. Copy the **REST Token**

### 2. Agent Tool (Bash)

```bash
cd agent-tool

# Set environment variables (uses REST API)
export UPSTASH_REDIS_URL="https://mutual-firefly-12345.upstash.io"
export UPSTASH_REDIS_TOKEN="your-rest-token-here"

# Publish an event
./publish_event.sh --title "Deployment started" --status in_progress --agent-id deployer

# Publish with all options
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

### 3. iPad App (Xcode)

1. Open `ipad/LiveTimeline/LiveTimeline.xcodeproj` in Xcode
2. Build and run on your iPad (no external dependencies)
3. Enter your Upstash Redis credentials in the Settings tab:
   - **REST URL**: `https://mutual-firefly-12345.upstash.io`
   - **REST Token**: Your token from Upstash console
   - **Polling Interval**: 20s (default) - adjust based on your needs

**Polling Interval Trade-offs:**
- **20s**: ~130K requests/month, very responsive
- **30s**: ~86K requests/month, good balance
- **60s**: ~43K requests/month, minimal API usage

Upstash free tier: 300K requests/month

## Future Enhancements

- **Callback interactions** — buttons on events that call webhooks back to the agent (e.g. "Archive these emails? [Yes] [No]")
- **Agent chat** — a listing of agents you can interact with via text/voice messages
