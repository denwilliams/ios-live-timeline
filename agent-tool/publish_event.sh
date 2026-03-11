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
# name = event name (for filtering), data = the JSON payload
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
