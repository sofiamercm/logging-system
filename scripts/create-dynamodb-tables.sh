#!/bin/bash
# Crea las tablas Logs y SecurityAlerts en DynamoDB.
# Uso: ./scripts/create-dynamodb-tables.sh
set -e
cd "$(dirname "$0")/.."
source scripts/config.env

create_table() {
  local name="$1"
  if aws dynamodb describe-table --table-name "$name" > /dev/null 2>&1; then
    echo "La tabla '$name' ya existe, se deja como esta."
    return
  fi
  echo "Creando tabla '$name'..."
  aws dynamodb create-table \
    --table-name "$name" \
    --attribute-definitions AttributeName=log_id,AttributeType=S \
    --key-schema AttributeName=log_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST > /dev/null
  aws dynamodb wait table-exists --table-name "$name"
  echo "Tabla '$name' lista."
}

create_table "$LOGS_TABLE"
create_table "$ALERTS_TABLE"
echo "Listo: tablas ${LOGS_TABLE} y ${ALERTS_TABLE} creadas en ${REGION}."

# Agrega el indice a Logs sin borrar ni recrear las tablas existentes.
INDEX_EXISTS=$(aws dynamodb describe-table --table-name "$LOGS_TABLE" \
  --query "Table.GlobalSecondaryIndexes[?IndexName=='${LOGS_INDEX}'].IndexName | [0]" --output text)
if [ "$INDEX_EXISTS" = "None" ] || [ -z "$INDEX_EXISTS" ]; then
  echo "Agregando GSI ${LOGS_INDEX} a ${LOGS_TABLE}..."
  aws dynamodb update-table --table-name "$LOGS_TABLE" \
    --attribute-definitions AttributeName=all_logs,AttributeType=S AttributeName=LastModified,AttributeType=S \
    --global-secondary-index-updates "[{\"Create\":{\"IndexName\":\"${LOGS_INDEX}\",\"KeySchema\":[{\"AttributeName\":\"all_logs\",\"KeyType\":\"HASH\"},{\"AttributeName\":\"LastModified\",\"KeyType\":\"RANGE\"}],\"Projection\":{\"ProjectionType\":\"ALL\"}}}]" > /dev/null
fi

# table-exists no espera que un GSI termine de crearse.
INDEX_STATUS=""
for ((attempt=1; attempt<=180; attempt++)); do
  INDEX_STATUS=$(aws dynamodb describe-table --table-name "$LOGS_TABLE" \
    --query "Table.GlobalSecondaryIndexes[?IndexName=='${LOGS_INDEX}'].IndexStatus | [0]" --output text)
  if [ "$INDEX_STATUS" = "ACTIVE" ]; then break; fi
  echo "Esperando al indice ${LOGS_INDEX} (${INDEX_STATUS})..."
  sleep 10
done
if [ "$INDEX_STATUS" != "ACTIVE" ]; then
  echo "El GSI aun no esta activo; revisa DynamoDB y vuelve a ejecutar este script." >&2
  exit 1
fi
echo "GSI ${LOGS_INDEX} listo (all_logs / LastModified)."
