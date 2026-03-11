# Ably Integration Design

## Summary

Replace Upstash Redis polling with Ably realtime messaging for the Live Timeline app. Agents publish events via Ably REST API, iPad receives them instantly via WebSocket subscription. Channel history with persistence provides catch-up on startup so no recent events are missed when the iPad is offline (up to 24h on free tier).

## Architecture

```
Agents (bash/n8n/any) --REST API--> Ably Channel ("timeline-events")
                                        |
                                        ├──realtime──> iPad (WebSocket subscription)
                                        |
                                        └──history (24h)──> iPad (fetched on startup)
```

- Agents publish JSON events to an Ably channel via REST API
- iPad subscribes to the channel via Ably's Swift SDK for instant delivery
- Persistence is enabled on the channel via a channel rule in the Ably dashboard
- On app launch, iPad fetches channel history first (up to 24h on free tier), then subscribes for realtime updates

## Why Ably

- True realtime push via WebSocket (no polling, no wasted requests)
- Free tier: 6M messages/month, 200 connections, 24h history
- Channel history with persistence: retrieve missed messages on startup (up to 24h on free tier)
- Simple REST API for publishing (curl from bash, n8n node, any language)
- Single backend service (no Redis + separate realtime service)
- n8n has built-in Ably integration

## Components to Change

| Component | Change |
|-----------|--------|
| `agent-tool/publish_event.sh` | Replace Upstash Redis LPUSH with Ably REST publish |
| `UpstashQueueService.swift` | Replace with `AblyService.swift` - realtime subscription + history fetch |
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
2. Fetch channel history (up to 24h of persisted messages missed while offline)
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
3. Enable persistence via channel rule in the Ably dashboard for the `timeline-events` channel
4. Copy the API key
5. Set `ABLY_API_KEY` env var for bash script
6. Enter API key in iPad app Settings tab

## Free Tier Limits

- 6M messages/month
- 200 concurrent connections
- 24h message history (with persistence enabled via channel rule)
