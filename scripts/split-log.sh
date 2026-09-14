#!/bin/bash
# Lee un archivo de log linea por linea, junta lineas hasta acumular ~1KB
# y escribe cada batch en un archivo openssh-<timestamp>.log
#
# Uso: ./split-log.sh <archivo_log_origen> [directorio_salida]

set -e

INPUT_FILE="$1"
OUTPUT_DIR="${2:-./batches}"
MAX_SIZE=1024  # ~1KB

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "Uso: $0 <archivo_log_origen> [directorio_salida]"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

current_batch=""
current_size=0
batch_count=0

flush_batch() {
  if [ -n "$current_batch" ]; then
    # timestamp con nanosegundos para que no se repita entre batches
    ts=$(date +%s%N)
    filename="${OUTPUT_DIR}/openssh-${ts}.log"
    printf '%s' "$current_batch" > "$filename"
    batch_count=$((batch_count + 1))
    echo "Batch #${batch_count} escrito: $filename (${current_size} bytes)"
    current_batch=""
    current_size=0
  fi
}

while IFS= read -r line || [ -n "$line" ]; do
  line_size=${#line}
  current_batch+="${line}"$'\n'
  current_size=$((current_size + line_size + 1))

  if [ "$current_size" -ge "$MAX_SIZE" ]; then
    flush_batch
  fi
done < "$INPUT_FILE"

# Escribe lo que haya quedado pendiente (ultimo batch, aunque no llegue a 1KB)
flush_batch

echo "Listo. ${batch_count} batches generados en ${OUTPUT_DIR}/"
