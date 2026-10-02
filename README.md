# Logging System

Sistema de procesamiento de logs de OpenSSH en AWS. Divide un archivo en lotes de aproximadamente 1 KB, los envía a S3 y procesa cada lote automáticamente mediante EventBridge, Step Functions y Lambda. Los registros y las alertas se almacenan en DynamoDB y se consultan mediante una API HTTP.

## Arquitectura

| Servicio | Función |
| --- | --- |
| Amazon S3 | Recibe archivos con el prefijo `input/openssh-`. |
| Amazon EventBridge | Detecta la creación de esos archivos e inicia la máquina de estados. |
| AWS Step Functions | Coordina la lectura, clasificación y almacenamiento de cada registro. |
| Lambda `parse_batch` | Lee el archivo de S3, separa sus líneas y extrae sus campos. |
| Amazon DynamoDB | Almacena los resultados en `Logs` o `SecurityAlerts`. |
| Lambdas `get_logs` y `get_alerts` | Consultan los resultados para responder las peticiones HTTP. |
| Amazon API Gateway | Publica `GET /logs` y `GET /alerts`. |
| Amazon CloudWatch Logs | Recibe los logs de ejecución de las funciones Lambda. |

El procesamiento es asíncrono: después de subir un archivo, la ejecución continúa en AWS y los resultados pueden tardar en aparecer en la API.

### Clasificación

Step Functions utiliza un estado `Map`, con hasta diez iteraciones concurrentes, para procesar las líneas. Un estado `Choice` identifica mensajes que contengan:

- `Invalid user`
- `POSSIBLE BREAK-IN ATTEMPT`

Los mensajes que coinciden se guardan en `SecurityAlerts` con severidad `HIGH`. Los demás se guardan en `Logs`. Esta clasificación depende exclusivamente de esas reglas; por ejemplo, `Failed password` puede quedar en `Logs` si no contiene las cadenas anteriores.

`parse_batch` no escribe en DynamoDB: las escrituras las realiza Step Functions mediante su integración con el servicio. El flujo incluye reintentos para determinados errores de Lambda y DynamoDB.

## Estructura principal

| Archivo o carpeta | Descripción |
| --- | --- |
| `scripts/config.env` | Región, nombres de recursos y roles IAM. |
| `scripts/create-s3-bucket.sh` | Crea el bucket y la tabla heredada `logging-system-logs`. |
| `scripts/create-dynamodb-tables.sh` | Crea `Logs`, `SecurityAlerts` y el índice `LogsByArrival`. |
| `scripts/deploy-parse-batch.sh` | Empaqueta y despliega la Lambda de lectura. |
| `scripts/deploy-state-machine.sh` | Despliega Step Functions y conecta S3 mediante EventBridge. |
| `scripts/deploy-api.sh` | Despliega las Lambdas de consulta y la API HTTP. |
| `scripts/split-log.sh` | Divide el archivo original en lotes. |
| `scripts/send-logs.sh` | Envía los lotes con una pausa configurable. |
| `scripts/teardown.sh` | Elimina parte de los recursos; consultar la sección de limpieza. |
| `src/parse_batch/lambda_function.py` | Lectura y extracción de campos de cada lote. |
| `src/get_logs/lambda_function.py` | Consulta ordenada de registros. |
| `src/get_alerts/lambda_function.py` | Consulta de alertas. |
| `statemachine/definition.asl.json` | Definición del flujo de procesamiento. |

`scripts/package-lambda.sh` y `src/logging-system/` corresponden a la versión anterior y no se utilizan en este despliegue. El flujo actual guarda los resultados en DynamoDB; no genera CSV en `output/`.

## Requisitos

- Bash en Linux, WSL o un entorno compatible, con `zip` y las herramientas habituales de shell.
- AWS CLI configurada con credenciales vigentes. En AWS Learner Lab se requiere también el token de sesión.
- Python 3 para visualizar y verificar las respuestas JSON desde la terminal.
- Un archivo de logs de OpenSSH en formato syslog.
- Permisos para crear y administrar los recursos del proyecto y pasar los roles IAM utilizados.

Las funciones Lambda se despliegan con Python 3.12. Los scripts actuales empaquetan el código sin instalar dependencias adicionales.

### Roles IAM

`config.env` obtiene el identificador de la cuenta mediante AWS CLI y utiliza `LabRole` para Lambda, Step Functions y EventBridge. Cada rol debe permitir que el servicio correspondiente lo asuma y contar con permisos para sus operaciones:

- Lambda de procesamiento: leer objetos de S3 y escribir logs en CloudWatch.
- Lambdas de consulta: consultar `Logs` y su índice, o leer `SecurityAlerts`, y escribir logs en CloudWatch.
- Step Functions: invocar `parse_batch` y escribir en DynamoDB.
- EventBridge: iniciar ejecuciones de la máquina de estados.

Para utilizar otros roles, se pueden definir `LAMBDA_ROLE_ARN`, `SFN_ROLE_ARN` y `EVENTS_ROLE_ARN` en `scripts/roles.env`, que se carga al final de la configuración. Los scripts no crean los roles.

## Configuración

Ejecutar todos los comandos desde la raíz del repositorio, en la rama `serguito`.

```bash
aws sts get-caller-identity
```

Elegir un nombre de bucket único y colocar exactamente el mismo valor en estos tres archivos:

| Archivo | Variable que se debe modificar |
| --- | --- |
| `scripts/config.env` | `export BUCKET="logging"` |
| `scripts/create-s3-bucket.sh` | `BUCKET_NAME="logging"` |
| `scripts/send-logs.sh` | `BUCKET="logging"` |

Por ejemplo, sustituir `logging` por `logging-<identificador-del-equipo>`. Los dos últimos scripts tienen el nombre escrito directamente: cambiar únicamente `config.env` no es suficiente.

La región predeterminada es `us-east-1`. Cargar la configuración en la terminal para aplicarla también a los comandos posteriores:

```bash
source scripts/config.env
```

Si los archivos provienen de Windows y presentan errores por saltos de línea, normalizarlos en Linux:

```bash
sed -i 's/\r$//' scripts/*.sh scripts/*.env
```

## Despliegue

Ejecutar cada comando después de que el anterior termine correctamente:

```bash
# 1. Crear el bucket y la tabla heredada.
bash scripts/create-s3-bucket.sh "$REGION"

# 2. Crear las tablas del flujo actual y esperar a que el índice esté activo.
bash scripts/create-dynamodb-tables.sh

# 3. Desplegar la Lambda que lee los lotes.
bash scripts/deploy-parse-batch.sh

# 4. Desplegar el flujo y conectar los eventos de S3.
bash scripts/deploy-state-machine.sh

# 5. Desplegar las funciones de consulta y la API.
bash scripts/deploy-api.sh
```

La creación del índice puede tardar varios minutos. Los mensajes `Esperando al indice LogsByArrival (CREATING)` indican que sigue en proceso.

El despliegue de la máquina de estados sustituye la configuración de notificaciones del bucket y elimina la función anterior `logging-system-processor` si existe. Utilizar un bucket dedicado al proyecto.

El script de S3 está pensado para la creación inicial. Si el bucket o la tabla heredada ya existen, revisar su estado antes de repetir ese paso. `logging-system-logs` no participa en el flujo actual, que utiliza `Logs` y `SecurityAlerts`.

## Generar y enviar lotes

Sustituir la ruta de ejemplo por la del archivo original:

```bash
bash scripts/split-log.sh /ruta/al/openssh.log ./batches
bash scripts/send-logs.sh 30
```

El primer comando genera archivos `openssh-<timestamp>.log`. Cada lote acumula aproximadamente 1 KB; puede superar ese tamaño porque se conservan las líneas completas. El último puede ser menor.

El segundo comando envía los lotes con treinta segundos de espera entre subidas. Se puede detener con `Ctrl+C`; las ejecuciones ya iniciadas en AWS continúan. La cantidad de lotes depende del archivo original: en la prueba documentada se generaron 213 y se envió una parte.

## API HTTP

El despliegue imprime la URL de la API y la guarda en `build/api-url.txt`:

```bash
API_URL=$(cat build/api-url.txt)
```

| Endpoint | Comportamiento |
| --- | --- |
| `GET /logs?top=N` | Devuelve hasta N registros de `Logs`, ordenados por `LastModified` de forma descendente. |
| `GET /alerts` | Devuelve las alertas de `SecurityAlerts`, sin un orden garantizado. |

En `/logs`, `top` vale 10 si se omite. Acepta enteros entre 1 y 1000; los valores inválidos producen HTTP 400. La consulta utiliza el índice `LogsByArrival`, con `all_logs` como clave de partición y `LastModified` como clave de ordenamiento.

`timestamp` es la fecha del mensaje original. `LastModified` es la fecha de última modificación del archivo en S3 y se utiliza como referencia de llegada del lote. Las líneas del mismo lote comparten ese valor; no se garantiza su orden relativo cuando hay empate.

`/alerts` recorre las páginas de DynamoDB mediante `Scan` y reúne los resultados en una respuesta. Está pensado para el volumen pequeño de la práctica. El script de despliegue no configura autenticación para la API.

### Consultas de prueba

```bash
curl -i "${API_URL}/alerts"
curl -i "${API_URL}/logs?top=5"

# Mostrar el JSON con formato legible.
curl -sS "${API_URL}/logs?top=5" | python3 -m json.tool
curl -sS "${API_URL}/alerts" | python3 -m json.tool
```

Antes de cargar datos, los endpoints pueden devolver HTTP 200 con `[]`. Después del procesamiento, `/logs` devuelve objetos con `id`, `timestamp`, `host`, `log` y `LastModified`. Las alertas incluyen `id`, `timestamp`, `host`, `log` y `severity`.

## Verificar el procesamiento

Consultar las últimas diez ejecuciones:

```bash
source scripts/config.env

aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:${REGION}:${ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
  --region "$REGION" \
  --max-results 10 \
  --no-paginate \
  --query 'executions[].{Ejecucion:name,Estado:status}' \
  --output table \
  --no-cli-pager
```

`SUCCEEDED` indica que la ejecución terminó correctamente. Confirmar también que la API devuelve los registros y alertas esperados.

Para verificar el orden de hasta veinte registros:

```bash
curl -sS "${API_URL}/logs?top=20" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
times = [row["LastModified"] for row in rows]
print("Registros:", len(rows))
print("Orden descendente:", times == sorted(times, reverse=True))
print("Fechas distintas:", len(set(times)))
'
```

Realizar esta prueba después de cargar datos. Si no hay registros, la comparación del orden por sí sola no demuestra el procesamiento.

## Limpieza

Estos comandos eliminan recursos y datos del proyecto. Ejecutarlos después de terminar las pruebas y guardar las evidencias.

```bash
bash scripts/teardown.sh
```

La versión actual del script elimina la regla de EventBridge, la máquina de estados, `parse_batch`, la función anterior si existe, las tablas `Logs` y `SecurityAlerts`, y el bucket con sus objetos. También borra archivos locales de empaquetado.

El script todavía no incluye la API HTTP, las Lambdas de consulta, la tabla heredada ni los grupos de logs de CloudWatch. Completar la limpieza de esos recursos con:

```bash
source scripts/config.env

API_ID=$(aws apigatewayv2 get-apis \
  --query "Items[?Name=='${API_NAME}'].ApiId | [0]" \
  --output text)

if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
  aws apigatewayv2 delete-api --api-id "$API_ID"
fi

aws lambda delete-function --function-name "$LOGS_FUNCTION"
aws lambda delete-function --function-name "$ALERTS_FUNCTION"
aws dynamodb delete-table --table-name logging-system-logs

for function_name in "$PARSE_FUNCTION" "$LOGS_FUNCTION" "$ALERTS_FUNCTION" "$OLD_FUNCTION"; do
  aws logs delete-log-group --log-group-name "/aws/lambda/${function_name}"
done
```

Si un recurso ya fue eliminado o nunca se creó, puede aparecer `ResourceNotFoundException`. Revisar cualquier otro error: el mensaje `Teardown completo` por sí solo no garantiza que todas las eliminaciones hayan tenido éxito.

Una vez que terminen las eliminaciones, comprobar las tablas y la máquina de estados:

```bash
aws dynamodb list-tables \
  --query "TableNames[?@=='${LOGS_TABLE}' || @=='${ALERTS_TABLE}' || @=='logging-system-logs']" \
  --no-cli-pager

aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='${STATE_MACHINE_NAME}'].name" \
  --no-cli-pager
```

Ambas consultas deben devolver `[]`. Estas dos comprobaciones verifican únicamente las tablas indicadas y la máquina de estados.
