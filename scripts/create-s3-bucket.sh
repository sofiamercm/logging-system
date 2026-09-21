#!/bin/bash
# Crea la infraestructura del sistema: el bucket S3 "logging" y la tabla
# DynamoDB donde ahora se guardan los logs procesados.
# Uso: ./create-s3-bucket.sh [region]

set -e

BUCKET_NAME="logging"
TABLE_NAME="logging-system-logs"
REGION="${1:-us-east-1}"

echo "Creando bucket '${BUCKET_NAME}' en la region ${REGION}..."

if [ "$REGION" == "us-east-1" ]; then
  # us-east-1 no acepta LocationConstraint
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"
else
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi

# Creamos ya la "carpeta" input/ (en S3 es solo un prefijo)
# output/ ya no es necesario: los resultados ahora van a DynamoDB
aws s3api put-object --bucket "$BUCKET_NAME" --key "input/"

echo "Bucket '${BUCKET_NAME}' creado con prefijo input/."

echo "Creando tabla DynamoDB '${TABLE_NAME}'..."

aws dynamodb create-table \
  --table-name "$TABLE_NAME" \
  --attribute-definitions AttributeName=log_id,AttributeType=S \
  --key-schema AttributeName=log_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo "Esperando a que la tabla '${TABLE_NAME}' este activa..."
aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$REGION"

echo "Tabla '${TABLE_NAME}' lista (partition key: log_id)."