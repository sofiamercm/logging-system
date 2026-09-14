#!/bin/bash
# Crea el bucket S3 "logging" usado por todo el sistema.
# Uso: ./create-s3-bucket.sh [region]

set -e

BUCKET_NAME="logging"
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

# Creamos ya las "carpetas" input/ y output/ (en S3 son solo prefijos)
aws s3api put-object --bucket "$BUCKET_NAME" --key "input/"
aws s3api put-object --bucket "$BUCKET_NAME" --key "output/"

echo "Bucket '${BUCKET_NAME}' creado con prefijos input/ y output/."
