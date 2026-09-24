#!/bin/bash
# Empaqueta y despliega la Lambda parse_batch.
# Uso: ./scripts/deploy-parse-batch.sh
set -e
cd "$(dirname "$0")/.."
source scripts/config.env

if [ -z "$LAMBDA_ROLE_ARN" ]; then
  echo "Falta LAMBDA_ROLE_ARN. Revisa scripts/config.env y verifica que use LabRole."
  exit 1
fi

rm -rf build/parse_batch parse_batch.zip
mkdir -p build/parse_batch
cp src/parse_batch/lambda_function.py build/parse_batch/
(cd build/parse_batch && zip -q ../../parse_batch.zip lambda_function.py)
echo "Empaquetado: parse_batch.zip"

if aws lambda get-function --function-name "$PARSE_FUNCTION" > /dev/null 2>&1; then
  echo "La funcion ya existe, actualizando codigo..."
  aws lambda update-function-code --function-name "$PARSE_FUNCTION" \
    --zip-file fileb://parse_batch.zip > /dev/null
  aws lambda wait function-updated --function-name "$PARSE_FUNCTION"
else
  echo "Creando la funcion Lambda ${PARSE_FUNCTION}..."
  aws lambda create-function \
    --function-name "$PARSE_FUNCTION" \
    --runtime python3.12 \
    --role "$LAMBDA_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://parse_batch.zip \
    --timeout 30 \
    --memory-size 256 > /dev/null
  aws lambda wait function-active --function-name "$PARSE_FUNCTION"
fi

echo "Listo: Lambda ${PARSE_FUNCTION} desplegada."