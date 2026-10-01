"""GET /logs?top=N: descending Query on S3 LastModified, never Scan."""
import json
import os
import re
import boto3
from boto3.dynamodb.conditions import Key

table = boto3.resource("dynamodb").Table(os.environ.get("LOGS_TABLE", "Logs"))


def response(status, body):
    return {"statusCode": status, "headers": {"content-type": "application/json"},
            "body": json.dumps(body, ensure_ascii=False)}


def lambda_handler(event, context):
    raw = (event.get("queryStringParameters") or {}).get("top", "10")
    if not isinstance(raw, str) or not re.fullmatch(r"[0-9]{1,4}", raw) or not 1 <= int(raw) <= 1000:
        return response(400, {"error": "top debe ser un entero entre 1 y 1000"})
    count = int(raw)
    rows = []
    params = {"IndexName": os.environ.get("LOGS_INDEX", "LogsByArrival"),
              "KeyConditionExpression": Key("all_logs").eq("ALL"),
              "ScanIndexForward": False}
    while len(rows) < count:
        page = table.query(**params, Limit=count - len(rows))
        rows.extend(page.get("Items", []))
        if not page.get("LastEvaluatedKey"):
            break
        params["ExclusiveStartKey"] = page["LastEvaluatedKey"]
    return response(200, [{"id": row["log_id"], "timestamp": row.get("timestamp", "unknown"),
                           "host": row.get("host", "unknown"),
                           "log": row.get("log", row.get("message", "")),
                           "LastModified": row["LastModified"]} for row in rows])
