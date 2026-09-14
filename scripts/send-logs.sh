#!/bin/bash
# Sube todos los batches generados por split-log.sh a s3://logging/input/,
# esperando N segundos entre cada subida.
#
# Uso: ./send-logs.sh <segundos_entre_cada_subida>
# Ejemplo: ./send-logs.sh 30
#
# Nota: en el enunciado el ejemplo de uso lo llama "start_logging.sh".
# Puedes renombrar este archivo o crear un symlink si quieres que coincida
# exactamente:  ln -s send-logs.sh start_logging.sh

set -e

BATCH_DIR="${BATCH_DIR:-./batches}"
BUCKET="logging"
PREFIX="input"
WAIT_SECONDS="$1"

if [ -z "$WAIT_SECONDS" ]; then
  echo "Uso: $0 <segundos_entre_cada_subida>"
  echo "Ejemplo: $0 30"
  exit 1
fi

shopt -s nullglob
files=("$BATCH_DIR"/openssh-*.log)

if [ ${#files[@]} -eq 0 ]; then
  echo "No se encontraron archivos openssh-*.log en ${BATCH_DIR}/"
  echo "Corre primero split-log.sh para generarlos."
  exit 1
fi

echo "Se encontraron ${#files[@]} batches. Subiendo con espera de ${WAIT_SECONDS}s entre cada uno..."

for file in "${files[@]}"; do
  filename=$(basename "$file")
  echo "-> Subiendo ${filename} a s3://${BUCKET}/${PREFIX}/"
  aws s3 cp "$file" "s3://${BUCKET}/${PREFIX}/${filename}"
  sleep "$WAIT_SECONDS"
done

echo "Todos los batches fueron subidos a s3://${BUCKET}/${PREFIX}/"
