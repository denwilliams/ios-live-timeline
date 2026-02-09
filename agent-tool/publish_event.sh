#!/bin/bash

# publish_event.sh - Publish events to Upstash Redis queue for iOS Live Timeline
#
# Usage:
#   export UPSTASH_REDIS_URL="https://your-redis.upstash.io"
#   export UPSTASH_REDIS_TOKEN="your-token"
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

set -e

# Parse arguments
AGENT_ID=""
TASK_ID=""
TITLE=""
BODY=""
STATUS=""
CATEGORY=""
TIMESTAMP=""

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
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$UPSTASH_REDIS_URL" ]]; then
  echo "Error: UPSTASH_REDIS_URL environment variable not set"
  exit 1
fi

if [[ -z "$UPSTASH_REDIS_TOKEN" ]]; then
  echo "Error: UPSTASH_REDIS_TOKEN environment variable not set"
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
  # Generate UUID (works on macOS and Linux)
  if command -v uuidgen &> /dev/null; then
    TASK_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  else
    TASK_ID=$(cat /proc/sys/kernel/random/uuid)
  fi
fi

if [[ -z "$TIMESTAMP" ]]; then
  # ISO 8601 timestamp
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

# Generate event ID
if command -v uuidgen &> /dev/null; then
  EVENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
  EVENT_ID=$(cat /proc/sys/kernel/random/uuid)
fi

# Build JSON payload
# Use jq if available for proper JSON escaping, otherwise use basic escaping
if command -v jq &> /dev/null; then
  PAYLOAD=$(jq -n \
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
  # Basic JSON construction (assumes no special characters needing escaping)
  PAYLOAD="{\"id\":\"$EVENT_ID\",\"agent_id\":\"$AGENT_ID\",\"task_id\":\"$TASK_ID\",\"title\":\"$TITLE\""
  [[ -n "$BODY" ]] && PAYLOAD="$PAYLOAD,\"body\":\"$BODY\""
  PAYLOAD="$PAYLOAD,\"status\":\"$STATUS\""
  [[ -n "$CATEGORY" ]] && PAYLOAD="$PAYLOAD,\"category\":\"$CATEGORY\""
  PAYLOAD="$PAYLOAD,\"timestamp\":\"$TIMESTAMP\"}"
fi

# Publish to Upstash Redis using LPUSH
# Upstash Redis REST API expects: POST /lpush/key with body as JSON array
# Each element in the array becomes a list item
# Send the JSON object directly (not string-encoded)
COMPACT_PAYLOAD=$(echo "$PAYLOAD" | jq -c .)

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "$UPSTASH_REDIS_URL/lpush/timeline-events" \
  -H "Authorization: Bearer $UPSTASH_REDIS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "[$COMPACT_PAYLOAD]")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" =~ ^2 ]]; then
  echo "✓ Event published: $TITLE (task_id: $TASK_ID)"
else
  echo "✗ Failed to publish event (HTTP $HTTP_CODE)"
  echo "$RESPONSE_BODY"
  exit 1
fi
