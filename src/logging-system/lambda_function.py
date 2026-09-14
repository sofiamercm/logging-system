"""
Lambda que se dispara cuando se escribe un archivo en s3://logging/input/.
Descarga el archivo de log de OpenSSH, lo parsea, genera un CSV
y lo sube a s3://logging/output/.
"""

import csv
import io
import os
import re
from urllib.parse import unquote_plus

import boto3

s3 = boto3.client("s3")

OUTPUT_PREFIX = "output/"

# Patron tipico de una linea de log de OpenSSH, por ejemplo:
# Sep 14 16:30:12 myhost sshd[1234]: Failed password for invalid user admin from 10.0.0.5 port 4444 ssh2
LOG_PATTERN = re.compile(
    r"(?P<month>\w{3})\s+(?P<day>\d+)\s+(?P<time>\d{2}:\d{2}:\d{2})\s+"
    r"(?P<host>\S+)\s+sshd\[(?P<pid>\d+)\]:\s+(?P<message>.*)"
)

FIELDNAMES = [
    "month", "day", "time", "host", "pid",
    "status", "user", "ip", "port", "raw_message",
]


def parse_line(line):
    match = LOG_PATTERN.match(line.strip())
    if not match:
        return None

    data = match.groupdict()
    message = data["message"]

    user_match = re.search(r"user (\S+)", message)
    ip_match = re.search(r"from ([\d.]+)", message)
    port_match = re.search(r"port (\d+)", message)

    if "Failed" in message:
        status = "failed"
    elif "Accepted" in message:
        status = "accepted"
    else:
        status = "other"

    return {
        "month": data["month"],
        "day": data["day"],
        "time": data["time"],
        "host": data["host"],
        "pid": data["pid"],
        "status": status,
        "user": user_match.group(1) if user_match else "",
        "ip": ip_match.group(1) if ip_match else "",
        "port": port_match.group(1) if port_match else "",
        "raw_message": message,
    }


def lambda_handler(event, context):
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])

        print(f"Procesando s3://{bucket}/{key}")

        obj = s3.get_object(Bucket=bucket, Key=key)
        content = obj["Body"].read().decode("utf-8", errors="replace")

        rows = [parse_line(line) for line in content.splitlines()]
        rows = [r for r in rows if r is not None]

        csv_buffer = io.StringIO()
        writer = csv.DictWriter(csv_buffer, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(rows)

        base_name = os.path.splitext(os.path.basename(key))[0]
        output_key = f"{OUTPUT_PREFIX}{base_name}.csv"

        s3.put_object(
            Bucket=bucket,
            Key=output_key,
            Body=csv_buffer.getvalue().encode("utf-8"),
        )

        print(f"CSV generado: s3://{bucket}/{output_key} ({len(rows)} filas)")

    return {"statusCode": 200, "body": "OK"}
