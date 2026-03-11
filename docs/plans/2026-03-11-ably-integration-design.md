# Ably Integration Design

## Summary

Replace Upstash Redis polling with Ably realtime messaging for the Live Timeline app. Agents publish events via Ably REST API, iPad receives them instantly via WebSocket subscription. Ably Queues provide persistence so no events are lost when the iPad is offline.

## Architecture

```
Agents (bash/n8n/any) --REST API--> Ably Channel ("timeline-events")
                                        |
                                        ├──realtime──> iPad (WebSocket subscription)
                                        |
                                        └──queue rule──> Ably Queue ("timeline-queue")
                                                            |
                                                            └──drain on startup──> iPad
```

- Agents publish JSON events to an Ably channel via REST API
- iPad subscribes to the channel via Ably's Swift SDK for instant delivery
- A queue rule copies all messages to an Ably Queue for persistence
- On app launch, iPad drains the queue first (catches up on missed events), then switches to realtime

## Why Ably

- True realtime push via WebSocket (no polling, no wasted requests)
- Free tier: 6M messages/month, 200 connections, 24h history
- Ably Queues (free tier): persistent message queue, messages stay until consumed
- Simple REST API for publishing (curl from bash, n8n node, any language)
- Single backend service (no Redis + separate realtime service)
- n8n has built-in Ably integration

## Components to Change

| Component | Change |
|-----------|--------|
| `agent-tool/publish_event.sh` | Replace Upstash Redis LPUSH with Ably REST publish |
| `UpstashQueueService.swift` | Replace with `AblyService.swift` - realtime subscription + queue drain |
| `AppSettings.swift` | Replace Upstash credentials with Ably API key, remove polling interval |
| `SettingsView.swift` | Update fields for Ably API key, remove polling interval slider |
| `LiveTimelineApp.swift` | No change |
| `TimelineEvent.swift` | No change |
| `EventPayload` (in `TimelineEvent.swift`) | No change |
| `CLAUDE.md` | Update architecture, setup instructions, commands |

## Credentials

Single credential: Ably API key (format: `appId.keyId:keySecret`)

- Bash script: environment variable `ABLY_API_KEY`
- iPad app: entered in Settings tab, stored in UserDefaults

## iPad Startup Flow

1. Connect to Ably realtime using API key
2. Drain the queue (process all persisted messages missed while offline)
3. Subscribe to the channel for live updates
4. Process each message through existing `processEvent` (upsert via `task_id`)

## Event Payload

No change from current schema:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "agent_id": "code-reviewer",
  "task_id": "pr-review-123",
  "title": "PR Review Complete",
  "body": "Reviewed PR #123 - found 2 issues.",
  "status": "success",
  "category": "code-review",
  "timestamp": "2026-03-11T10:30:00Z"
}
```

Required fields: `id`, `agent_id`, `task_id`, `title`, `status`, `timestamp`
Status values: `info`, `in_progress`, `success`, `warning`, `error`
Upsert: events with matching `task_id` replace existing events.

## Dependencies

- iPad: [ably-cocoa](https://github.com/ably/ably-cocoa) Swift package
- Bash script: curl only (no new dependencies)

## Ably Setup (one-time, manual)

1. Create Ably account at ably.com
2. Create a new app
3. Create a queue called `timeline-queue`
4. Create a queue rule: channel `timeline-events` -> queue `timeline-queue`
5. Copy the API key
6. Set `ABLY_API_KEY` env var for bash script
7. Enter API key in iPad app Settings tab

## Free Tier Limits

- 6M messages/month
- 200 concurrent connections
- 24h message history (with persistence enabled)
- Ably Queues: messages persist until consumed (no time limit)
