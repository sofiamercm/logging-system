"""GET /alerts: read every DynamoDB page (small classroom dataset)."""
import json
import os
import boto3

table = boto3.resource("dynamodb").Table(os.environ.get("ALERTS_TABLE", "SecurityAlerts"))


def lambda_handler(event, context):
    alerts, params = [], {}
    while True:
        page = table.scan(**params)
        alerts.extend({
            "id": row["log_id"], "timestamp": row.get("timestamp", "unknown"),
            "host": row.get("host", "unknown"),
            "log": row.get("log", row.get("message", "")),
            "severity": row.get("severity", "HIGH"),
        } for row in page.get("Items", []))
        if not page.get("LastEvaluatedKey"):
            break
        params["ExclusiveStartKey"] = page["LastEvaluatedKey"]
    return {"statusCode": 200, "headers": {"content-type": "application/json"},
            "body": json.dumps(alerts, ensure_ascii=False)}
