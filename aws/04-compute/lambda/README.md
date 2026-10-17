# AWS · Compute · AWS Lambda

**AWS Lambda** ejecuta tu código **en respuesta a eventos**, sin servidores que administrar: subes una función, defines qué la dispara y pagas por invocación y por milisegundo de ejecución. Si no hay eventos, no hay costo ni capacidad ociosa.

## 1. Qué es

**Analogía:** un **taxi por viaje**. No compras un auto ni pagas al conductor mientras espera; cuando llega un pasajero (evento), aparece un taxi, hace el viaje y se va. Si llegan mil pasajeros a la vez, aparecen mil taxis. El primer viaje de un taxi «nuevo» tarda un poco más (arranque en frío).

```
 Evento ──► [ Lambda: entorno de ejecución (microVM) ]
 (API, SQS, S3, EventBridge, Kinesis, cron…)   ├ Init: carga JVM + clases + tus clientes SDK  (solo la 1.ª vez: "cold start")
                                              ├ Invoke: ejecuta handler(evento)   ← se repite, el entorno se reutiliza
                                              └ Shutdown
```

## 2. Cómo funciona por dentro

### Ciclo de vida
1. **Init** (arranque en frío): se crea el entorno, se descarga el código, arranca la JVM y se ejecuta código estático/constructores.
2. **Invoke**: se llama al *handler*. Un entorno atiende **una invocación a la vez**; si llegan varias simultáneas, Lambda crea más entornos (concurrencia).
3. Entre invocaciones el entorno puede **congelarse y reutilizarse** (*warm*): lo que inicializas fuera del handler (clientes, conexiones) se reutiliza; también puede ser destruido en cualquier momento.

### Formas de invocación
| Tipo | Quién espera | Ejemplos | Reintentos |
|---|---|---|---|
| **Síncrona** | El llamante espera la respuesta | API Gateway, ALB, Function URL, SDK `RequestResponse` | Los decide el llamante |
| **Asíncrona** | Nadie: Lambda encola el evento | S3, EventBridge, SNS | 2 reintentos automáticos, luego **destino de fallo** o DLQ |
| **Event source mapping (sondeo)** | Lambda lee del origen y entrega **lotes** | SQS, Kinesis, DynamoDB Streams, MSK/Kafka | Según el origen: el lote vuelve a la cola o se reintenta |

### Configuración principal
| Pieza | Qué es |
|---|---|
| **Runtime** | `java21` (y otros; verifica los vigentes). También imágenes de contenedor de hasta 10 GB |
| **Memoria** | 128 MB a 10 GB; **la CPU es proporcional a la memoria** (más memoria = más CPU) |
| **Timeout** | Hasta 15 minutos |
| **Concurrencia** | Límite por cuenta/región; *reserved* (techo y garantía por función) y *provisioned* (entornos precalentados, con costo) |
| **Versiones y alias** | `$LATEST` mutable; versiones inmutables; alias (`prod`) con reparto de tráfico entre versiones |
| **Capas (layers)** | Código/librerías compartidas |
| **VPC** | Para llegar a recursos privados; la salida a Internet requiere NAT o endpoints |
| **Variables de entorno** | Cifradas con KMS en reposo |
| **Function URL** | Endpoint HTTPS directo (con IAM o público) |
| **/tmp** | 512 MB a 10 GB efímeros |

### Arranque en frío en Java y cómo mitigarlo
| Técnica | Idea |
|---|---|
| **SnapStart** | Lambda toma una *instantánea* del entorno ya inicializado y la **restaura** en lugar de arrancar desde cero (grandes mejoras en Java; verifica compatibilidad y costo) |
| Menos clases, menos reflexión | Menos carga en Init (evita Spring completo si no lo necesitas) |
| Clientes SDK ligeros | Cliente HTTP `url-connection`/CRT en lugar de Apache |
| Más memoria | Más CPU = Init más rápido; se mide, no se adivina |
| Imagen nativa (Quarkus/GraalVM) | Arranque en milisegundos, a cambio de complejidad de compilación |
| Provisioned concurrency | Entornos siempre calientes (costo fijo) |

> Con **SnapStart**, lo que se captura en la instantánea es compartido: **no guardes** valores únicos (semillas aleatorias, identificadores, conexiones abiertas) creados en Init; revísalos tras la restauración.

### Lotes y fallos parciales (SQS)
Con SQS, Lambda entrega un **lote**. Si el handler falla, **todo el lote** vuelve a la cola, incluyendo los mensajes ya procesados (duplicados). La solución: habilitar `ReportBatchItemFailures` y devolver **solo los identificadores fallidos**. Es obligatorio diseñar el procesamiento **idempotente**.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Procesar mensajes de colas/streams, reaccionar a archivos subidos, tareas programadas | **Lambda** |
| APIs con tráfico irregular o bajo | **Lambda** (con API Gateway/ALB/Function URL) |
| Glue entre servicios de AWS | **Lambda** |
| Servicio HTTP con tráfico constante y latencia estable | [ECS Fargate](../ecs-fargate/README.md) o [EKS](../eks/README.md) |
| Procesos de más de 15 minutos | Fargate / Step Functions |
| Conexiones persistentes (WebSocket largo, gRPC en flujo) | Contenedores |
| Latencia de arranque inaceptable y sin SnapStart/provisioned | Contenedores |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Handler** | El método que Lambda llama por cada evento |
| **Cold start / warm** | Primera ejecución con arranque / reutilización del entorno |
| **Concurrencia** | Cuántos entornos corren a la vez |
| **Event source mapping** | Lambda sondea una cola/stream y te entrega lotes |
| **ReportBatchItemFailures** | Devolver solo los mensajes fallidos del lote |
| **DLQ / destino de fallo** | Dónde van los eventos que se agotaron |
| **Execution role** | Permisos de la función |
| **Resource policy** | Quién puede invocar la función |
| **SnapStart** | Arranque desde una instantánea |
| **Idempotencia** | Procesar dos veces = el mismo resultado |

## 5. Cómo se usa
1. Empaqueta el JAR (o imagen) y súbelo a S3/ECR.
2. Crea función, rol, log group, alias y origen de eventos con Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Conecta una cola SQS con **fallos parciales** y una **cola de mensajes muertos** (DLQ) en la cola.
4. Despliega con versiones y alias (`prod`) y cambio gradual de tráfico.
5. Operación: [`ejemplos/cli/lambda.sh`](ejemplos/cli/lambda.sh). Evento y respuesta de ejemplo: [`ejemplos/json/`](ejemplos/json/evento-sqs.json).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Pipeline** | `lambda:UpdateFunctionCode`, `PublishVersion`, `UpdateAlias`, `iam:PassRole` (solo el rol de la función) | — |
| **Execution role** | — | Lo que el código llama (SQS, DynamoDB, S3…) + escribir logs |
| **Quien invoca** | — | `lambda:InvokeFunction` (política de recurso o IAM) |
| **Origen de eventos** | — | El rol de la función necesita `sqs:ReceiveMessage/DeleteMessage/GetQueueAttributes` |

- **Mínimo privilegio** por función (un rol por función).
- **Resource policy** con `SourceArn`/`SourceAccount` cuando otro servicio invoca (evita el «confused deputy»).
- Variables de entorno con **CMK**; los secretos se leen de Secrets Manager con caché, no se guardan en variables.
- En VPC, grupos de seguridad mínimos y endpoints para los servicios de AWS.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Inicializar clientes SDK **fuera** del handler | Crear un cliente en cada invocación |
| `ReportBatchItemFailures` + idempotencia | Fallar todo el lote por un mensaje |
| Timeout de la función **menor** que el *visibility timeout* de la cola (con margen 6×) | Timeout igual o mayor que la visibilidad |
| DLQ en la cola y alarma de profundidad | Reintentar para siempre |
| Medir memoria vs costo (más memoria puede ser más barata) | Dejar los 512 MB «por defecto» |
| SnapStart y/o menos dependencias en Java | Cargar un framework completo para una función de 20 líneas |
| Concurrencia máxima en el origen (`maximum_concurrency`) | Dejar que una cola enorme agote la concurrencia de la cuenta |
| Alias con tráfico gradual | Desplegar directamente `$LATEST` en producción |

## 8. Límites, costos y versiones
- **Costo:** peticiones + GB-segundo (granularidad de 1 ms); provisioned concurrency y SnapStart tienen cargos propios; VPC con NAT suma costo. *Verifica precios, nivel gratuito y cuotas.*
- **Límites** (verifica): payload síncrono ~6 MB, asíncrono 256 KB, 15 min de ejecución, tamaño del paquete, concurrencia por cuenta.
- **Terraform:** `aws_lambda_function`, `aws_lambda_alias`, `aws_lambda_event_source_mapping`, `aws_lambda_permission`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
