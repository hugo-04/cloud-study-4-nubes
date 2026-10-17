# Google Cloud · Compute · Cloud Run functions (antes Cloud Functions)

Escribes **una función** (Java con el Functions Framework) y Google la empaqueta, la despliega sobre Cloud Run y la invoca por **HTTP** o por **eventos** (Pub/Sub, Cloud Storage, Eventarc). Es lo más simple para reaccionar a algo que pasó.

## 1. Qué es

**Analogía:** un empleado por horas que llega cuando suena el timbre. Hace una tarea concreta y se va; si suenan muchos timbres, llegan más empleados.

```
 Evento (objeto subido, mensaje Pub/Sub, cambio en Firestore…) ─► Eventarc ─► función "miniaturas"
 Petición HTTP ──────────────────────────────────────────────────► función "webhook-pagos"
 Por dentro: código → Cloud Build → imagen → servicio de Cloud Run (revisiones, escalado, SA, VPC)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Función HTTP** | Implementa `HttpFunction`; URL HTTPS (privada o pública) |
| **Función de eventos** | Implementa `CloudEventsFunction`; recibe un **CloudEvent** |
| **Disparador (Eventarc)** | Tipo de evento + filtros + cuenta de servicio del disparador |
| **Runtime** | `java21` y otros; política de actualización del runtime |
| **Configuración del servicio** | Memoria, CPU, tiempo máximo, mínimo/máximo de instancias, concurrencia, VPC, ingress |
| **Reintentos** | En funciones de eventos, reintentar si la función falla (opcional) |
| **Cuenta de servicio** | Identidad de la función (y otra para el disparador) |

### Garantías de los eventos
- Al menos una vez: la función debe ser **idempotente** (usa el `id` del CloudEvent).
- Con reintentos activados, un error lanza un reintento con espera; sin ellos, el evento se pierde.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Reaccionar a un archivo subido o a un mensaje | **Función de eventos** |
| Webhook pequeño | **Función HTTP** |
| API con muchas rutas | [Cloud Run](../cloud-run/README.md) con Spring/Quarkus |
| Trabajo de más de unos minutos | Cloud Run jobs |
| Funciones que se llaman en cadena | **No**: coreografía con Pub/Sub o Workflows |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **CloudEvent** | Formato estándar del evento (id, fuente, tipo, datos) |
| **Functions Framework** | Biblioteca que conecta tu clase con HTTP/eventos |
| **Idempotencia** | Procesar dos veces no duplica el efecto |
| **Reintentos** | Volver a entregar el evento si falla |
| **Arranque en frío** | Primera invocación lenta |

## 5. Cómo se usa
1. Función de eventos de Pub/Sub con disparador, SA propia, reintentos y límites: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Código de la función con el Functions Framework: [`ejemplos/funcion/MiniaturaFuncion.java`](ejemplos/funcion/MiniaturaFuncion.java) (requiere la dependencia `functions-framework-api`).
3. Lógica pura del manejador y auditoría de funciones desde [Java](uso-en-java.md).
4. CLI: [`ejemplos/cli/funciones.sh`](ejemplos/cli/funciones.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline | `roles/cloudfunctions.developer` + `serviceAccountUser` | — |
| Disparador (Eventarc) | — | `roles/run.invoker` sobre la función |
| Llamadores HTTP | — | `roles/run.invoker` |
| La función | SA propia con roles mínimos | — |

- Ingress interno salvo webhooks que deben ser públicos (y entonces valida firma del remitente).
- Secretos montados desde Secret Manager.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Idempotencia por id del evento | Suponer entrega única |
| Reintentos + DLQ en la suscripción | Errores que se pierden en silencio |
| Máximo de instancias | Escalado sin tope hacia la base |
| Funciones pequeñas de un propósito | Monolitos dentro de una función |
| `java21` y actualizaciones de runtime | Runtimes sin soporte |

## 8. Límites, costos y versiones
- **Costo:** igual que Cloud Run (vCPU-s, GiB-s, invocaciones) más compilación *(verifica)*.
- **Límites** (verifica): tiempo máximo (HTTP hasta 60 min, eventos hasta 9 min), memoria, tamaño del código.
- **Terraform:** `google_cloudfunctions2_function` (con `event_trigger` o HTTP).
- **Java:** función con `com.google.cloud.functions.*` (Functions Framework); gestión con `FunctionServiceClient` (`google-cloud-functions`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
