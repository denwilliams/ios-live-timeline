"""
Publish timeline events to SQS for the iOS Live Timeline app.

Usage as CLI:
    python publish_event.py --title "PR Review Complete" --body "Found 2 issues" --status success
    python publish_event.py --agent-id deployer --task-id deploy-42 --title "Deploying v1.3" --status in_progress

Usage as library:
    from publish_event import publish_event
    publish_event(title="Build passed", status="success", agent_id="ci")

Environment:
    TIMELINE_QUEUE_URL  - SQS queue URL (required if not passed as argument)
    AWS_REGION          - AWS region (default: us-east-1)
"""

import argparse
import json
import os
import uuid
from datetime import datetime, timezone

import boto3


def publish_event(
    title: str,
    body: str = "",
    status: str = "info",
    agent_id: str = "default",
    task_id: str | None = None,
    category: str = "",
    queue_url: str | None = None,
    region: str | None = None,
) -> dict:
    """Publish a timeline event to SQS.

    Returns dict with message_id and the event payload.
    """
    queue_url = queue_url or os.environ.get("TIMELINE_QUEUE_URL")
    if not queue_url:
        raise ValueError(
            "queue_url must be provided or TIMELINE_QUEUE_URL env var must be set"
        )

    region = region or os.environ.get("AWS_REGION", "us-east-1")
    sqs = boto3.client("sqs", region_name=region)

    event = {
        "id": str(uuid.uuid4()),
        "agent_id": agent_id,
        "task_id": task_id or str(uuid.uuid4()),
        "title": title,
        "body": body,
        "status": status,
        "category": category,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    response = sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(event),
    )

    return {
        "message_id": response["MessageId"],
        "event": event,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Publish a timeline event to SQS"
    )
    parser.add_argument("--title", required=True, help="Event title")
    parser.add_argument("--body", default="", help="Event body/details")
    parser.add_argument(
        "--status",
        default="info",
        choices=["info", "in_progress", "success", "warning", "error"],
        help="Event status (default: info)",
    )
    parser.add_argument(
        "--agent-id", default="default", help="Agent identifier"
    )
    parser.add_argument(
        "--task-id",
        default=None,
        help="Task ID for upsert grouping (auto-generated if omitted)",
    )
    parser.add_argument(
        "--category", default="", help="Category for filtering"
    )
    parser.add_argument(
        "--queue-url",
        default=None,
        help="SQS queue URL (or set TIMELINE_QUEUE_URL env var)",
    )
    parser.add_argument("--region", default=None, help="AWS region")
    args = parser.parse_args()

    result = publish_event(
        title=args.title,
        body=args.body,
        status=args.status,
        agent_id=args.agent_id,
        task_id=args.task_id,
        category=args.category,
        queue_url=args.queue_url,
        region=args.region,
    )

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
