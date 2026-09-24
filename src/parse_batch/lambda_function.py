"""
parse_batch: descarga un batch de logs desde S3 y lo separa en lineas.
NO escribe en DynamoDB; eso lo hace la maquina de estados.

Entrada (la manda EventBridge / Step Functions):
    {"bucket": "logging", "key": "input/openssh-123.log"}

Salida:
    {"bucket": ..., "key": ..., "total_lines": N,
     "lines": [{"log_id": "...", "batch_key": "...", "line_number": 1, "message": "..."}]}
"""

import boto3

s3 = boto3.client("s3")


def lambda_handler(event, context):
    bucket = event["bucket"]
    key = event["key"]

    print(f"Descargando s3://{bucket}/{key}")
    obj = s3.get_object(Bucket=bucket, Key=key)
    content = obj["Body"].read().decode("utf-8", errors="replace")

    lines = []
    for number, raw_line in enumerate(content.splitlines(), start=1):
        message = raw_line.strip()
        if not message:  # ignora lineas vacias
            continue
        lines.append({
            # log_id = llave unica de la fila en DynamoDB: "<archivo>#<numero de linea>"
            "log_id": f"{key}#{number}",
            "batch_key": key,
            "line_number": number,
            "message": message,
        })

    print(f"{len(lines)} lineas encontradas")
    return {"bucket": bucket, "key": key, "total_lines": len(lines), "lines": lines}