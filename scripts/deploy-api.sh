#!/bin/bash
# Despliega las dos Lambdas de consulta y una HTTP API con GET /alerts y GET /logs.
# Uso: ./scripts/deploy-api.sh
set -e
cd "$(dirname "$0")/.."
source scripts/config.env

# Se usa el mismo empaquetado que deploy-parse-batch.sh, sin dependencias nuevas.
deploy_query_lambda() {
  local folder="$1" name="$2" environment="$3"
  mkdir -p "build/${folder}"
  cp "src/${folder}/lambda_function.py" "build/${folder}/"
  (cd "build/${folder}" && zip -q "../${folder}.zip" lambda_function.py)

  if aws lambda get-function --function-name "$name" > /dev/null 2>&1; then
    aws lambda update-function-code --function-name "$name" \
      --zip-file "fileb://build/${folder}.zip" > /dev/null
    aws lambda wait function-updated --function-name "$name"
    aws lambda update-function-configuration --function-name "$name" \
      --environment "$environment" --timeout 30 > /dev/null
    aws lambda wait function-updated --function-name "$name"
  else
    aws lambda create-function --function-name "$name" \
      --runtime python3.12 --role "$LAMBDA_ROLE_ARN" \
      --handler lambda_function.lambda_handler \
      --zip-file "fileb://build/${folder}.zip" \
      --environment "$environment" --timeout 30 --memory-size 256 > /dev/null
    aws lambda wait function-active --function-name "$name"
  fi
  echo "Lambda ${name} lista."
}

deploy_query_lambda get_alerts "$ALERTS_FUNCTION" "Variables={ALERTS_TABLE=${ALERTS_TABLE}}"
deploy_query_lambda get_logs "$LOGS_FUNCTION" "Variables={LOGS_TABLE=${LOGS_TABLE},LOGS_INDEX=${LOGS_INDEX}}"

API_ID=$(aws apigatewayv2 get-apis \
  --query "Items[?Name=='${API_NAME}'].ApiId | [0]" --output text)
if [ "$API_ID" = "None" ] || [ -z "$API_ID" ]; then
  API_ID=$(aws apigatewayv2 create-api --name "$API_NAME" --protocol-type HTTP \
    --query ApiId --output text)
fi

configure_route() {
  local path="$1" function_name="$2"
  local function_arn="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${function_name}"
  local route_id integration_id target
  route_id=$(aws apigatewayv2 get-routes --api-id "$API_ID" \
    --query "Items[?RouteKey=='GET /${path}'].RouteId | [0]" --output text)

  # Reutiliza la integracion de una ruta existente al volver a ejecutar el script.
  target=""
  if [ "$route_id" != "None" ] && [ -n "$route_id" ]; then
    target=$(aws apigatewayv2 get-route --api-id "$API_ID" --route-id "$route_id" \
      --query Target --output text)
  fi
  if [[ "$target" == integrations/* ]]; then
    integration_id="${target#integrations/}"
    aws apigatewayv2 update-integration --api-id "$API_ID" --integration-id "$integration_id" \
      --integration-type AWS_PROXY --integration-uri "$function_arn" \
      --payload-format-version 2.0 > /dev/null
  else
    integration_id=$(aws apigatewayv2 create-integration --api-id "$API_ID" \
      --integration-type AWS_PROXY --integration-uri "$function_arn" \
      --payload-format-version 2.0 --query IntegrationId --output text)
  fi

  if [ "$route_id" = "None" ] || [ -z "$route_id" ]; then
    aws apigatewayv2 create-route --api-id "$API_ID" --route-key "GET /${path}" \
      --target "integrations/${integration_id}" > /dev/null
  else
    aws apigatewayv2 update-route --api-id "$API_ID" --route-id "$route_id" \
      --target "integrations/${integration_id}" > /dev/null
  fi

  # Renueva solo el permiso de esta API, sin acumular statements en cada despliegue.
  aws lambda remove-permission --function-name "$function_name" \
    --statement-id "http-${API_ID}-${path}" > /dev/null 2>&1 || true
  aws lambda add-permission --function-name "$function_name" \
    --statement-id "http-${API_ID}-${path}" --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/GET/${path}" > /dev/null
}

configure_route alerts "$ALERTS_FUNCTION"
configure_route logs "$LOGS_FUNCTION"

if aws apigatewayv2 get-stage --api-id "$API_ID" --stage-name '$default' > /dev/null 2>&1; then
  aws apigatewayv2 update-stage --api-id "$API_ID" --stage-name '$default' --auto-deploy > /dev/null
else
  aws apigatewayv2 create-stage --api-id "$API_ID" --stage-name '$default' --auto-deploy > /dev/null
fi

API_URL=$(aws apigatewayv2 get-api --api-id "$API_ID" --query ApiEndpoint --output text)
printf '%s\n' "$API_URL" > build/api-url.txt
echo "HTTP API lista: ${API_URL}"
echo "curl '${API_URL}/alerts'"
echo "curl '${API_URL}/logs?top=5'"
