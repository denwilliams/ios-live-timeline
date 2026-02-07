# iOS Live Timeline

An iPad app that displays a real-time timeline of events pushed by AI agents via AWS SQS.

Background AI agents work on tasks and push status updates to an SQS queue. The iPad app long-polls the queue and displays events in a scrollable, searchable timeline — newest first.

## Architecture

```
AI Agent ──→ [publish_event.py] ──→ AWS SQS Queue ──→ iPad App (long-poll)
                                                            │
                                                      SwiftData (local)
                                                            │
                                                      Timeline UI
```

- **No backend server.** Agents publish directly to SQS. The iPad consumes directly from SQS.
- **SQS long polling** (20s wait) gives near-real-time delivery with no throttling.
- **Local persistence** via SwiftData — events survive app restarts.
- **Upsert behavior** — if an agent sends a new event with the same `task_id`, the app replaces the old event and moves it to the top.
- **Message durability** — if the app is offline, messages wait in the queue (up to 4 days by default).

## Event Payload Format

Agents publish JSON messages to the SQS queue:

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
| `timestamp` | string (ISO 8601) | Yes | When the event occurred |

### Status Values

| Status | Meaning | UI Treatment |
|--------|---------|--------------|
| `info` | General information | Blue |
| `in_progress` | Task is actively being worked on | Yellow |
| `success` | Task completed successfully | Green |
| `warning` | Completed with warnings or needs attention | Orange |
| `error` | Task failed | Red |

### Upsert Behavior

When the app receives an event whose `task_id` matches an existing event, the old event is **replaced** (not duplicated). The new event appears at the top of the timeline. This lets agents send progressive updates for long-running tasks without cluttering the timeline.

## Setup

### 1. AWS SQS Queue

Create a standard SQS queue:

```bash
aws sqs create-queue --queue-name live-timeline
```

Create an IAM user (or role) with permissions to send and receive:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["sqs:SendMessage"],
      "Resource": "arn:aws:sqs:*:*:live-timeline"
    },
    {
      "Effect": "Allow",
      "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage"],
      "Resource": "arn:aws:sqs:*:*:live-timeline"
    }
  ]
}
```

Ideally, use separate credentials: one for agents (send-only) and one for the iPad app (receive + delete).

### 2. Agent Tool (Python)

```bash
cd agent-tool
pip install -r requirements.txt
export TIMELINE_QUEUE_URL="https://sqs.us-east-1.amazonaws.com/123456789/live-timeline"
python publish_event.py --title "Deployment started" --status in_progress --agent-id deployer
```

### 3. iPad App (Xcode)

1. Open Xcode and create a new iPad app project named `LiveTimeline`
2. Add the Swift package dependency: `https://github.com/awslabs/aws-sdk-swift` (add `AWSSQS` product)
3. Copy the source files from `LiveTimeline/` into the project
4. Build and run on your iPad
5. Enter your AWS credentials and queue URL in the Settings tab

## Future Enhancements

- **Callback interactions** — buttons on events that call webhooks back to the agent (e.g. "Archive these emails? [Yes] [No]")
- **Agent chat** — a listing of agents you can interact with via text/voice messages
