# Logging System

Sistema que simula el envio de logs de OpenSSH a S3 en batches, y los
procesa automaticamente con una Lambda para generar CSVs.

## Estructura

```
├── README.md
├── scripts
│   ├── package-lambda.sh     # Empaqueta y despliega la Lambda + trigger de S3
│   ├── split-log.sh          # Divide un log en batches de ~1KB
│   ├── send-logs.sh          # Sube los batches a S3 con espera entre cada uno
│   ├── create-s3-bucket.sh   # Crea el bucket "logging" con sus prefijos
│   └── teardown.sh           # Elimina todos los recursos creados
└── src
    └── logging-system
        ├── lambda_function.py
        └── requirements.txt
```

## Requisitos previos

- AWS CLI configurado (`aws configure`) con credenciales validas.
- Un rol IAM para la Lambda con permisos de `s3:GetObject` / `s3:PutObject`
  sobre el bucket `logging`, y la politica administrada
  `AWSLambdaBasicExecutionRole`.
- `zip`, `pip` y `python3` instalados localmente para empaquetar la Lambda.

## Orden de ejecucion

1. **Crear el bucket**
   ```
   chmod +x scripts/*.sh
   ./scripts/create-s3-bucket.sh us-east-1
   ```
   > Los nombres de bucket en S3 son globales. Si "logging" ya esta
   > tomado, cambia `BUCKET_NAME` en `create-s3-bucket.sh` (y en los
   > demas scripts) por algo unico, ej. `logging-tuequipo-2026`.

2. **Desplegar la Lambda**
   ```
   ./scripts/package-lambda.sh arn:aws:iam::<TU_CUENTA>:role/<TU_ROL>
   ```

3. **Generar los batches de log**
   ```
   ./scripts/split-log.sh /ruta/a/tu/openssh.log ./batches
   ```

4. **Subir los batches a S3** (espera N segundos entre cada uno)
   ```
   ./scripts/send-logs.sh 30
   ```
   Cada subida dispara la Lambda automaticamente, que genera un CSV en
   `s3://logging/output/`.

5. **Verificar resultados**
   ```
   aws s3 ls s3://logging/output/
   ```

6. **Limpiar todo al terminar**
   ```
   ./scripts/teardown.sh
   ```

## Notas

- El enunciado menciona el comando `./start_logging.sh 30`; el script
  equivalente aqui se llama `send-logs.sh` para respetar la estructura
  de carpetas pedida. Si necesitas el nombre exacto, crea un symlink:
  `ln -s send-logs.sh start_logging.sh`.
- El parser de `lambda_function.py` asume el formato estandar de
  syslog de OpenSSH (`Mon DD HH:MM:SS host sshd[pid]: mensaje`).
  Ajusta la expresion regular `LOG_PATTERN` si tus logs tienen otro
  formato.
