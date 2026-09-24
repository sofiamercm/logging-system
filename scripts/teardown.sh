#!/bin/bash
# Elimina TODOS los recursos del proyecto.
# Uso: ./scripts/teardown.sh

cd "$(dirname "$0")/.."
source scripts/config.env

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Eliminando regla de EventBridge..."
aws events remove-targets --rule "$RULE_NAME" --ids start-log-processing || true
aws events delete-rule --name "$RULE_NAME" || true

echo "Eliminando la maquina de estados..."
aws stepfunctions delete-state-machine \
  --state-machine-arn "arn:aws:states:${REGION}:${ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" || true

echo "Eliminando Lambdas..."
aws lambda delete-function --function-name "$PARSE_FUNCTION" || true
aws lambda delete-function --function-name "$OLD_FUNCTION" || true

echo "Eliminando tablas de DynamoDB..."
aws dynamodb delete-table --table-name "$LOGS_TABLE" > /dev/null || true
aws dynamodb delete-table --table-name "$ALERTS_TABLE" > /dev/null || true

echo "Quitando notificaciones del bucket, vaciandolo y eliminandolo..."
aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --notification-configuration '{}' || true

aws s3 rm "s3://${BUCKET}" --recursive || true
aws s3api delete-bucket --bucket "$BUCKET" || true

rm -rf build parse_batch.zip

echo "Teardown completo."