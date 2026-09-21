"""
Lambda que se dispara cuando se escribe un archivo en s3://logging/input/.
Descarga el archivo de log de OpenSSH, lo parsea y guarda cada linea
como un item en DynamoDB (ya no genera CSV).
"""

import os
import uuid
from urllib.parse import unquote_plus

import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

# Nombre configurable via variable de entorno, con default por si no se define
TABLE_NAME = os.environ.get("TABLE_NAME", "logging-system-logs")
table = dynamodb.Table(TABLE_NAME)


def parse_line(line):
    """Convierte una linea cruda de syslog en un dict con los campos del log."""
    line = line.strip()
    if not line:
        return None

    parts = line.split(" ", 5)  # separa solo lo necesario, el resto queda intacto
    if len(parts) < 6:
        return None  # linea que no matchea el formato esperado, se ignora

    month, day, time, hostname, proc_pid, log_message = parts

    # "sshd[24200]:" -> program="sshd", pid="24200"
    proc_pid = proc_pid.rstrip(":")
    if "[" in proc_pid and proc_pid.endswith("]"):
        program, pid = proc_pid.split("[")
        pid = pid.rstrip("]")
    else:
        program, pid = proc_pid, ""  # por si algun log no trae pid

    return {
        "timestamp": f"{month} {day} {time}",
        "hostname": hostname,
        "program": program,
        "pid": pid,
        "log": log_message,
    }


def lambda_handler(event, context):
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])

        print(f"Procesando s3://{bucket}/{key}")

        # Descarga el batch de logs
        obj = s3.get_object(Bucket=bucket, Key=key)
        content = obj["Body"].read().decode("utf-8", errors="replace")

        # Parsea linea por linea, descartando las que no matcheen
        rows = [parse_line(line) for line in content.splitlines()]
        rows = [r for r in rows if r is not None]

        source_file = os.path.basename(key)

        # batch_writer agrupa los puts en lotes de 25 automaticamente
        with table.batch_writer() as batch:
            for row in rows:
                item = {
                    "log_id": str(uuid.uuid4()),  # partition key unica por linea
                    "source_file": source_file,   # trazabilidad al batch original
                    **row,
                }
                batch.put_item(Item=item)

        print(f"{len(rows)} items escritos en DynamoDB (tabla: {TABLE_NAME})")

    return {"statusCode": 200, "body": "OK"}