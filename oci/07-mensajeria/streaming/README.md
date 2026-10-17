# Oracle OCI · Mensajería · Streaming (compatible con Kafka)

Registro de eventos particionado, durable y de alto volumen: los productores escriben al final, los consumidores leen a su ritmo desde un **offset**, y los mensajes se conservan días aunque ya se hayan leído. Habla su propia API **y** el protocolo de Kafka, así que los clientes Kafka se conectan sin cambios de código.

## 1. Qué es

**Analogía:** la grabación de las cámaras de una tienda. Todo queda grabado en orden por cámara (partición); cada guardia (grupo de consumidores) mira desde donde se quedó, puede rebobinar, y la grabación se borra sola a los días.

```
 Stream pool "eventos-tienda" (endpoint privado, compatible con Kafka)
   └─ Stream "clickstream" (6 particiones, retención 24 h–7 días)
        P0: e1 e4 e7 …   ← clave = idSesion (misma sesión ⇒ misma partición ⇒ en orden)
        P1: e2 e5 …
   Productores ── PutMessages / KafkaProducer
   Grupo "analitica"  ── lee con su offset
   Grupo "recomendaciones" ── lee lo mismo, con otro offset
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Stream pool** | Agrupa streams; define endpoint (público o privado), cifrado y **configuración Kafka** |
| **Stream** | El tema: número de particiones (fijo al crear) y retención (24 h a 7 días *(verifica)*) |
| **Partición** | Secuencia ordenada; la clave del mensaje decide a cuál va |
| **Offset** | Posición de un mensaje dentro de su partición |
| **Cursor** | Cómo empiezas a leer: `TRIM_HORIZON`, `LATEST`, `AT_OFFSET`, `AT_TIME`, o de grupo |
| **Grupo de consumidores** | Reparte particiones entre instancias y guarda el offset confirmado |
| **Kafka compatible** | `bootstrap.servers` del pool, SASL_SSL PLAIN con usuario `<tenancy>/<usuario>/<ocid del pool>` y un *auth token* |

### Capacidad
- Cada partición tiene un rendimiento máximo de escritura y lectura *(verifica: del orden de 1 MB/s de escritura)*: el número de particiones define la capacidad.
- Tamaño máximo de mensaje del orden de 1 MB *(verifica)*.
- Orden garantizado **solo dentro de una partición**.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Clickstream, telemetría, registros de alto volumen | **Streaming** |
| Varios sistemas leen el mismo flujo, cada uno a su ritmo | **Streaming** con grupos |
| Reprocesar los últimos días tras un bug | **Streaming** (rebobinar) |
| Migrar apps que ya usan Kafka | **Streaming** vía protocolo Kafka |
| Trabajo por tareas con reintentos por mensaje y DLQ | [Queue](../queue/README.md) |
| Avisos a personas | [Notifications](../notifications/README.md) |
| Historial permanente | Exporta a Object Storage (Connector Hub) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Clave de partición** | Lo que decide el orden relativo (por sesión, por pedido) |
| **Partición caliente** | Una clave muy frecuente satura una partición |
| **Lag** | Cuánto atrasado va un grupo |
| **Commit de offset** | «Hasta aquí ya procesé» |
| **Al menos una vez** | Tras un fallo se reprocesa desde el último commit |

## 5. Cómo se usa
1. Pool privado + stream: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Productor con el SDK, lotes y reintento de fallidos: [uso en Java](uso-en-java.md).
3. Con clientes Kafka: [`ejemplos/kafka/application.yml`](ejemplos/kafka/application.yml) (Spring Kafka). Conceptos de Kafka en [el módulo transversal](../../../transversal/kafka/README.md).
4. CLI: [`ejemplos/cli/streaming.sh`](ejemplos/cli/streaming.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage stream-family` | — |
| Productor | — | `use stream-push` |
| Consumidor | — | `use stream-pull` |
| Cliente Kafka | — | Usuario + *auth token* (guárdalo en Vault) con las mismas políticas |

- Pool con **endpoint privado** en la subred de las apps.
- Cifrado con llave propia si los datos son sensibles.
- Nada de datos personales en claro en eventos de analítica: seudonimiza.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Elegir clave por entidad que necesita orden | Clave constante (todo a una partición) |
| Calcular particiones con margen | Quedarse corto: no se cambian después |
| Productor por lotes y con reintento de fallidos | Ignorar `failures` de `PutMessages` |
| Consumidor idempotente, commit tras procesar | Commit antes de procesar |
| Vigilar el lag de cada grupo | Descubrir el retraso cuando ya venció la retención |

## 8. Límites, costos y versiones
- **Costo:** por GB escrito, por hora de partición y por almacenamiento retenido *(verifica)*.
- **Límites** (verifica): particiones por stream y por tenancy, MB/s por partición, tamaño de mensaje, retención máxima.
- **Terraform:** `oci_streaming_stream_pool`, `oci_streaming_stream`.
- **SDK:** `StreamAdminClient` (gestión), `StreamClient` (mensajes, con el endpoint del pool).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
