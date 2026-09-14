#!/bin/bash
# Empaqueta lambda_function.py + dependencias, y crea/actualiza la funcion
# Lambda, dejandola conectada al bucket S3 (evento en input/).
#
# Uso: ./package-lambda.sh <arn-del-rol-iam-para-lambda>

set -e

LAMBDA_SRC_DIR="src/logging-system"
BUILD_DIR="build/lambda-package"
ZIP_FILE="lambda_function.zip"
FUNCTION_NAME="logging-system-processor"
BUCKET="logging"
ROLE_ARN="$1"

if [ -z "$ROLE_ARN" ]; then
  echo "Uso: $0 <arn-del-rol-iam>"
  echo "El rol debe tener permisos de s3:GetObject/s3:PutObject sobre el bucket '${BUCKET}'"
  echo "y el permiso basico de logs de Lambda (AWSLambdaBasicExecutionRole)."
  exit 1
fi

rm -rf "$BUILD_DIR" "$ZIP_FILE"
mkdir -p "$BUILD_DIR"

echo "Instalando dependencias..."
pip install -r "${LAMBDA_SRC_DIR}/requirements.txt" -t "$BUILD_DIR" --quiet

echo "Copiando codigo fuente..."
cp "${LAMBDA_SRC_DIR}/lambda_function.py" "$BUILD_DIR"

echo "Empaquetando en ${ZIP_FILE}..."
(cd "$BUILD_DIR" && zip -r "../../${ZIP_FILE}" . -x '*.pyc' > /dev/null)

if aws lambda get-function --function-name "$FUNCTION_NAME" > /dev/null 2>&1; then
  echo "La funcion ya existe, actualizando codigo..."
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://${ZIP_FILE}"
else
  echo "Creando la funcion Lambda..."
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime python3.12 \
    --role "$ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file "fileb://${ZIP_FILE}" \
    --timeout 30 \
    --memory-size 256

  echo "Dando permiso a S3 para invocar la funcion..."
  aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --statement-id s3invoke \
    --action "lambda:InvokeFunction" \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::${BUCKET}"

  FUNCTION_ARN=$(aws lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --query 'Configuration.FunctionArn' --output text)

  echo "Configurando el trigger de S3 (input/ -> Lambda)..."
  aws s3api put-bucket-notification-configuration \
    --bucket "$BUCKET" \
    --notification-configuration '{
      "LambdaFunctionConfigurations": [
        {
          "LambdaFunctionArn": "'"$FUNCTION_ARN"'",
          "Events": ["s3:ObjectCreated:*"],
          "Filter": {
            "Key": {
              "FilterRules": [
                {"Name": "prefix", "Value": "input/"}
              ]
            }
          }
        }
      ]
    }'
fi

echo "Listo. La funcion '${FUNCTION_NAME}' esta desplegada y conectada a s3://${BUCKET}/input/"
