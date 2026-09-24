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