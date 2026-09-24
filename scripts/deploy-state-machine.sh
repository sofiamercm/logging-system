#!/bin/bash
# 1) Crea/actualiza la maquina de estados
# 2) Conecta S3 -> EventBridge -> Step Functions (reemplaza el trigger S3 -> Lambda)
# 3) Elimina la Lambda vieja de la clase anterior
# Uso: ./scripts/deploy-state-machine.sh
set -e
cd "$(dirname "$0")/.."
source scripts/config.env

for v in SFN_ROLE_ARN EVENTS_ROLE_ARN; do
  if [ -z "${!v}" ]; then
    echo "Falta $v. Revisa scripts/config.env y verifica que use LabRole."
    exit 1
  fi
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PARSE_BATCH_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${PARSE_FUNCTION}"

# ---------- 1) Maquina de estados ----------
mkdir -p build
sed -e "s|\${PARSE_BATCH_ARN}|${PARSE_BATCH_ARN}|g" \
    -e "s|\${LOGS_TABLE}|${LOGS_TABLE}|g" \
    -e "s|\${ALERTS_TABLE}|${ALERTS_TABLE}|g" \
    statemachine/definition.asl.json > build/definition.json

SM_ARN=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='${STATE_MACHINE_NAME}'].stateMachineArn | [0]" --output text)

if [ "$SM_ARN" == "None" ] || [ -z "$SM_ARN" ]; then
  echo "Creando la maquina de estados ${STATE_MACHINE_NAME}..."
  SM_ARN=$(aws stepfunctions create-state-machine \
    --name "$STATE_MACHINE_NAME" \
    --type STANDARD \
    --role-arn "$SFN_ROLE_ARN" \
    --definition file://build/definition.json \
    --query stateMachineArn --output text)
else
  echo "La maquina de estados ya existe, actualizando definicion..."
  aws stepfunctions update-state-machine \
    --state-machine-arn "$SM_ARN" \
    --role-arn "$SFN_ROLE_ARN" \
    --definition file://build/definition.json > /dev/null
fi
echo "State machine: $SM_ARN"

# ---------- 2) EventBridge ----------
echo "Creando la regla de EventBridge ${RULE_NAME}..."
aws events put-rule --name "$RULE_NAME" --state ENABLED \
  --event-pattern "{\"source\":[\"aws.s3\"],\"detail-type\":[\"Object Created\"],\"detail\":{\"bucket\":{\"name\":[\"${BUCKET}\"]},\"object\":{\"key\":[{\"prefix\":\"input/openssh-\"}]}}}" > /dev/null

cat > build/targets.json <<JSON
[{
  "Id": "start-log-processing",
  "Arn": "${SM_ARN}",
  "RoleArn": "${EVENTS_ROLE_ARN}",
  "InputTransformer": {
    "InputPathsMap": {"bucket": "\$.detail.bucket.name", "key": "\$.detail.object.key"},
    "InputTemplate": "{\"bucket\": <bucket>, \"key\": <key>}"
  }
}]
JSON
aws events put-targets --rule "$RULE_NAME" --targets file://build/targets.json > /dev/null

echo "Activando notificaciones de EventBridge en el bucket (quita el trigger a la Lambda vieja)..."
aws s3api put-bucket-notification-configuration --bucket "$BUCKET" \
  --notification-configuration '{"EventBridgeConfiguration":{}}'

# ---------- 3) Lambda vieja ----------
if aws lambda get-function --function-name "$OLD_FUNCTION" > /dev/null 2>&1; then
  echo "Eliminando la Lambda vieja ${OLD_FUNCTION}..."
  aws lambda delete-function --function-name "$OLD_FUNCTION"
fi

echo "Listo. Cada archivo nuevo en s3://${BUCKET}/input/ inicia una ejecucion."