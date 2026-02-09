# Future Ideas

Ideas for making the Live Timeline app awesome, roughly grouped by theme.

---

## Interaction & Control

### Action Buttons with Webhooks
Agents attach action buttons to events. The user taps a button, the app fires a webhook back to the agent with the user's decision. Transforms the timeline from read-only into a control surface.

```json
{
  "id": "...",
  "agent_id": "email-assistant",
  "task_id": "email-triage-42",
  "title": "Found 10 emails from X that seem unimportant",
  "status": "info",
  "actions": [
    { "label": "Archive them", "webhook": "https://agent.example.com/callback/archive" },
    { "label": "Leave them", "webhook": "https://agent.example.com/callback/skip" },
    { "label": "Show me", "webhook": "https://agent.example.com/callback/details" }
  ]
}
```

### Quick Replies
Free-text response field on an event. Agent asks a question ("What should I name this PR?"), user types an answer inline, answer is sent back via webhook. More natural than forcing everything into button choices.

### Snooze & Pin
- **Pin** important events to the top so they don't scroll away.
- **Snooze** noisy events — hide them for N minutes/hours, then resurface.

### Mute Per Agent/Category
"I don't need every `email-scan` info event, only warnings and errors." Configurable per agent or per category, with threshold (e.g. `warning` and above).

### Kill Switch
Tap an agent in the directory, hit "Cancel task", app sends a cancel webhook. For when an agent goes off the rails.

---

## Grouping & Organization

### Agent Grouping View
Instead of one flat timeline, optionally group by agent. Tap an agent to see its event stream. Like Slack channels but for agents.

### Task Threads
Tap an event to see the full history of that `task_id`, even though the timeline only shows the latest via upsert. "Deploy v1.4" expands to show: queued -> building -> deploying -> success, with timestamps for each step.

This means the app should **keep replaced events** in storage (marked as superseded) rather than deleting them, so the full thread is available on demand.

### Daily Digest
Auto-generated summary at the end of each day: "Your agents completed 14 tasks, 2 need attention, 3 upcoming tomorrow." Could be a special event inserted into the timeline, or a separate digest view.

### Event Grouping by Time
Collapse events into time-based groups ("This morning", "Yesterday", "Last week") when scrolling far back. Prevents the timeline from feeling like an endless undifferentiated list.

---

## Richer Content

### Markdown Body
Let agents send Markdown in the `body` field — formatted text, code blocks, links, bullet lists. Render it natively. Particularly useful for code review summaries, error stack traces, or structured reports.

### Attachments & Inline Media
Agents include a URL to an image, chart, diff preview, or log snippet. The app fetches and renders it inline. Could use a new `media_url` field or support Markdown image syntax in the body.

### Priority / Urgency
Separate from `status`. A `success` can still be urgent ("deal closed — sign the contract now"). Priority drives notification behavior, visual weight, and sort order within a time window.

```json
{
  "priority": "high"
}
```

Values: `low`, `normal`, `high`, `critical`. Default `normal`.

### Rich Timestamps
Support `started_at` and `completed_at` in addition to `timestamp`, so the app can show duration ("took 4m 32s") without the agent needing to calculate it.

---

## Scheduled & Time-Based

### Recurring Events
Agents register repeating events (daily standup, weekly deploy window) with a recurrence rule instead of re-publishing every occurrence. The app generates upcoming instances locally.

### Countdown Mode
Upcoming events within the next hour show a live countdown ("starts in 12 minutes") instead of a static timestamp. SwiftUI `Text(date, style: .timer)` makes this trivial.

### Auto-Expire Old Events
Events older than N days fade out or move to an archive. Keeps the active timeline focused. Configurable retention period per category (e.g. keep `deploy` events for 30 days, `email` events for 7 days).

---

## Intelligence Features

These features leverage Apple's native frameworks to make the app smarter without requiring a backend or cloud AI.

### Smart Notifications

**What:** The app is mostly silent — you glance at the iPad. But optionally push a real local notification for important events (e.g. `error` status, events from specific agents, `critical` priority).

**How — `UserNotifications` framework:**
When the SQS polling service receives an event matching notification rules, it immediately schedules a local `UNNotificationRequest`. No push infrastructure needed — the app is already running and polling.

Actionable notification categories let the user tap "View", "Retry", or "Dismiss" directly from the notification banner without opening the app. Register `UNNotificationCategory` with `UNNotificationAction` buttons.

Rules are configurable: per agent, per status, per category, per priority. Stored in UserDefaults or a lightweight rules model.

**Constraints:**
- Max 64 pending local notifications at a time (plenty for this use case).
- App must request notification permission on first launch.
- When the app is in the foreground, notifications are hidden by default — implement `UNUserNotificationCenterDelegate` and return `.banner` in `willPresent` to show them anyway.

### Anomaly Detection

**What:** "Agent X usually completes in 5 minutes, it's been 30 minutes with no update" — surface a warning automatically.

**How — simple statistics first, Core ML if needed:**

**Option A (recommended starting point):** No ML required. Track mean and standard deviation of completion times per agent/task pattern locally. When current duration exceeds mean + 2σ, generate a synthetic warning event and optionally a local notification. This is a few dozen lines of Swift code and handles 90% of the use case.

**Option B:** Use `CreateMLComponents` with `LinearTimeSeriesForecasterConfiguration` to train a time-series model on historical agent timing data. The model learns patterns like "deploys are slower on Mondays" and flags truly anomalous deviations. Can train incrementally on-device as new data arrives.

**Option C:** Train an Isolation Forest or autoencoder in Python, convert to `.mlmodel` with `coremltools`, bundle in the app. Core ML dispatches to Neural Engine/GPU automatically.

### Natural Language Search

**What:** Search the timeline with natural language — "what did the deploy agent do yesterday?" or "show me errors from last week" instead of keyword matching.

**How — two tiers:**

**Tier 1 — Core Spotlight semantic search (`CoreSpotlight` framework):**
Index every event into Core Spotlight using `CSSearchableItem`. On iOS 18+, `CSUserQuery` supports semantic search — "failed jobs" matches an event titled "Agent error: pipeline timeout". This works on-device using Apple's built-in embeddings. Events also become searchable from the iPad's system Spotlight.

**Tier 2 — Foundation Models framework (iPadOS 26+, M1+ required):**
For true natural language queries, use `LanguageModelSession` from the `FoundationModels` framework. The on-device ~3B parameter LLM can interpret a question, use tool calling to query your SwiftData store, and return a natural language answer.

```swift
let session = LanguageModelSession()
let response = try await session.respond(
    to: "What did the deploy agent do yesterday?",
    // with tools that can query SwiftData
)
```

The `@Generable` macro lets you constrain the LLM output to a Swift struct, so you get structured results (e.g. a list of matching event IDs) rather than freeform text.

**Constraints:**
- Foundation Models requires A17 Pro or M1+ hardware and iPadOS 26.
- 4,096 token combined input+output limit — enough for queries but not for summarizing hundreds of events at once.
- Core Spotlight semantic search is available on iOS 18+ but has had reliability reports — test thoroughly.

### On-Device Summarization

**What:** "Summarize what happened today" — the app generates a natural language digest from the day's events.

**How — `FoundationModels` framework (iPadOS 26+):**
Feed the day's events (titles, statuses, timestamps) into `LanguageModelSession` and ask for a summary. Use `@Generable` to constrain output to a structured digest format:

```swift
@Generable
struct DailyDigest {
    @Guide(description: "One-sentence overall summary")
    var summary: String

    @Guide(description: "Number of tasks completed successfully")
    var completedCount: Int

    @Guide(description: "Number of errors or issues needing attention")
    var issueCount: Int

    @Guide(description: "Most important thing the user should know")
    var highlight: String
}
```

Runs entirely on-device, offline, no API costs.

### Event Classification

**What:** Automatically tag or categorize events that agents didn't categorize well. Or detect sentiment/urgency from the body text.

**How — `NaturalLanguage` framework + custom Core ML model:**
Train a text classifier with Create ML on a small labeled dataset of event bodies -> categories. Load it via `NLModel` and run inference on each incoming event. Entirely on-device, fast (< 1ms per event).

The `NLTagger` can also extract named entities (people, places, organizations) from event bodies for richer filtering.

---

## Widgets & Ambient Display

### Home Screen Widget

**What:** A medium or large widget showing agent status at a glance without opening the app.

**How — `WidgetKit`:**
A `.systemMedium` widget could show 3-4 recent events with status icons. A `.systemLarge` could show a fuller timeline. Interactive buttons (iOS 17+) let users tap "Retry" or "Dismiss" directly from the widget via App Intents.

Update the widget from the app using `WidgetCenter.shared.reloadTimelines(ofKind:)` whenever new events arrive. Budget is ~40-70 refreshes/day — more than enough since you'd only reload when the polling service receives new messages.

### Lock Screen Widgets

**What:** Glanceable status on the iPad Lock Screen — "3 agents running / 1 error".

**How — `WidgetKit` with `.accessoryCircular` or `.accessoryRectangular` families:**
Available on iPadOS 16+. Show a compact count or status summary. Tapping opens the app.

### Live Activities

**What:** Real-time agent status on the iPad Lock Screen as a persistent banner — elapsed time, current step, progress.

**How — `ActivityKit`:**
Start a Live Activity when the user kicks off a long-running agent task. Update it from the app as new SQS messages arrive. The Lock Screen shows "data-pipeline: Running 4m 32s — Processing batch 3/5" without opening the app.

On iPad, Live Activities appear as a Lock Screen banner (no Dynamic Island since iPads don't have one).

**Constraints:**
- Max 8 hours active, then auto-ended.
- Max 5 concurrent Live Activities per app.
- Must be started from the foreground (user-initiated).
- Combined data must be under 4 KB.

---

## Siri & Shortcuts

### Voice Queries

**What:** "Hey Siri, what are my agents doing in Live Timeline?"

**How — `AppIntents` framework:**
Define `AppIntent` structs for common queries and register them as `AppShortcut` with trigger phrases. Siri speaks the result and optionally shows a SwiftUI snippet.

Useful intents:
- "Check agent status" — spoken summary of running/errored agents
- "Are there any errors?" — list recent error events
- "What's coming up?" — read upcoming events

### Shortcuts Automation

**What:** Build Shortcuts workflows that include timeline events. e.g. "When I arrive at the office, show me agent errors from overnight."

**How:** App Intents automatically appear in the Shortcuts app. Users can combine them with location triggers, time triggers, or other app actions.

---

## Multi-Device

### Apple Watch Companion

**What:** Glanceable agent status on your wrist. Tap to see recent events.

**How:** Two approaches depending on primary device:

**If you also have an iPhone companion app:** Use `WatchConnectivity` (`WCSession`) to sync agent state from iPhone to Watch. `updateApplicationContext` sends latest state; Watch receives it and updates the UI.

**If iPad-only (more likely):** Build the Watch app as independent — it makes its own SQS long-poll requests over WiFi/cellular using `URLSession`. No iPhone dependency.

watchOS widgets (via WidgetKit, watchOS 9+) can show agent summary in the Smart Stack. Live Activities from iOS 17+ automatically mirror to the Watch Smart Stack in watchOS 11.

**Constraints:**
- `WatchConnectivity` only works with iPhone, not iPad. If iPad is the primary device, the Watch app must be independent.
- Watch screen is tiny — design for "3 OK / 1 Error" with tap to expand.
- Complication updates limited to ~50/day.

### Multi-User / Shared Dashboard

Multiple people subscribe to the same SQS queue to see the same agent updates. Useful for a team ops dashboard. Would need SQS fan-out (SNS -> multiple SQS queues, one per user) since SQS is single-consumer.

### Mac Companion

A lightweight macOS menu bar app showing agent status. Same codebase via SwiftUI multiplatform. Click to expand into a timeline popover.

---

## Agent Management

### Agent Directory

A dedicated tab showing all known agents (discovered from `agent_id` values seen in events). Each agent shows: name, last activity time, event count, current status, health indicator (healthy / stale / erroring).

### Agent Health Monitoring

Track per-agent patterns: when did we last hear from it? Is it overdue? Has its error rate spiked? Surface synthetic warning events when something looks off. Uses the anomaly detection approach described above.

### Agent Chat

Bi-directional messaging with agents. The iPad becomes a conversational interface. User sends a text (or voice via iOS keyboard dictation) to an agent, message is delivered via a webhook or a dedicated SQS response queue. Agent replies appear as events in the timeline or in a chat thread.

---

## Data & History

### Task Thread History

Keep superseded events (from upserts) in storage rather than deleting them. Tap an event to see the full progression of that `task_id` over time. "Deploy v1.4" thread shows: queued -> building -> tests passing -> deploying -> health checks -> success.

### Export & Search

Export timeline data as JSON or CSV. Full-text search across all historical events. Integration with Core Spotlight means events are also searchable from system Spotlight.

### Analytics Dashboard

Simple charts: events per day, error rate over time, average task duration per agent, busiest agents. Built with Swift Charts. Helps spot trends and problem agents.

### Sync & Backup

Periodic backup of the local SwiftData store to iCloud (via CloudKit) or a file export. Protects against data loss if the iPad is reset.

---

## Visual & UX Polish

### Dark Mode Optimized

Dark mode by default (this is a dashboard that sits on a desk). Status colors tuned for dark backgrounds. Optional always-on display mode that dims but never sleeps.

### Sound & Haptic Alerts

Optional subtle sounds for different status types — a gentle chime for success, a warning tone for errors. Haptic feedback when new events arrive (if holding the iPad).

### Customizable Timeline Density

Toggle between compact mode (more events visible, less detail) and expanded mode (full body text, larger status icons). User picks their preference.

### Event Animations

New events slide in from the top. Status changes animate the icon/color transition. Upcoming events crossing into "now" animate their move from the upcoming section to the timeline. Subtle but makes the app feel alive.
