#!/bin/bash
# Elimina los recursos creados por este proyecto: trigger de S3,
# funcion Lambda, tabla DynamoDB y el bucket (con su contenido).
#
# Uso: ./teardown.sh

set -e

FUNCTION_NAME="logging-system-processor"
BUCKET="logging"
TABLE_NAME="logging-system-logs"

echo "Quitando la notificacion de eventos del bucket..."
aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --notification-configuration '{}' || true

echo "Eliminando la funcion Lambda..."
aws lambda delete-function --function-name "$FUNCTION_NAME" || true

echo "Eliminando la tabla DynamoDB ${TABLE_NAME}..."
aws dynamodb delete-table --table-name "$TABLE_NAME" || true

echo "Vaciando el bucket ${BUCKET}..."
aws s3 rm "s3://${BUCKET}" --recursive || true

echo "Eliminando el bucket ${BUCKET}..."
aws s3api delete-bucket --bucket "$BUCKET" || true

echo "Teardown completo."