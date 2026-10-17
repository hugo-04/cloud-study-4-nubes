# Google Cloud · Storage · Eventos de Cloud Storage

Cuando se crea, borra, archiva o cambia la metadata de un objeto, Cloud Storage puede avisar por dos caminos: **notificaciones a Pub/Sub** (configuradas en el bucket) o **Eventarc** (disparadores con tipos CloudEvents hacia Cloud Run, funciones o flujos). Es la base de todo «subo un archivo y algo pasa».

## 1. Qué es

**Analogía:** el timbre con cámara de la casa. Cada paquete que llega hace sonar el timbre con una foto (evento con bucket, objeto y generación); tú decides a quién avisar.

```
 Bucket "fotos" ─ notificación OBJECT_FINALIZE (prefijo fotos/) ─► tema Pub/Sub "fotos-subidas"
                                                                     ├─ suscripción push → Cloud Run "miniaturas" (DLQ)
                                                                     └─ suscripción pull → indexador
 o bien
 Bucket "fotos" ─ Eventarc (google.cloud.storage.object.v1.finalized) ─► Cloud Run "miniaturas"
```

## 2. Cómo funciona por dentro

### Caminos
| Camino | Cómo se configura | Formato | Filtros |
|---|---|---|---|
| **Notificaciones a Pub/Sub** | En el bucket: tema, tipos de evento, prefijo | Atributos (`bucketId`, `objectId`, `objectGeneration`, `eventType`) + JSON del objeto | Tipos y prefijo |
| **Eventarc** | Disparador con tipo `google.cloud.storage.object.v1.*` y bucket | CloudEvent | Bucket (y otros atributos) |

### Tipos de evento
`OBJECT_FINALIZE` (creado o reemplazado), `OBJECT_DELETE`, `OBJECT_ARCHIVE`, `OBJECT_METADATA_UPDATE`.

### Garantías
- **Al menos una vez** y sin orden garantizado.
- La **generación** identifica la versión exacta: deduplica por `bucket/objeto#generación`.
- El evento puede llegar cuando el objeto ya cambió o no existe: verifícalo.
- El agente de servicio de Cloud Storage necesita `pubsub.publisher` en el tema.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Miniaturas al subir fotos | Evento → Cloud Run/función |
| Varios consumidores del mismo evento | Notificación a un tema con varias suscripciones |
| Procesar los objetos ya existentes | **No**: lote que lista el bucket |
| Orden estricto | **No**: diseña sin depender del orden |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Generación** | Versión exacta del objeto |
| **Deduplicar** | Ignorar el evento ya procesado |
| **Ciclo de eventos** | Escribir en el mismo bucket/prefijo vuelve a disparar |
| **DLQ** | Destino de los mensajes que siempre fallan |

## 5. Cómo se usa
1. Notificación del bucket a Pub/Sub con prefijo, permisos y suscripción push con DLQ: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Consumidor que deduplica por generación y verifica el objeto: [uso en Java](uso-en-java.md).
3. Prueba: [`ejemplos/cli/eventos.sh`](ejemplos/cli/eventos.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/storage.admin` (notificaciones), `roles/pubsub.admin` | — |
| Agente de Cloud Storage | — | `roles/pubsub.publisher` en el tema |
| Consumidor | — | `roles/storage.objectViewer` en el bucket de origen |

- La notificación lleva metadatos, no el contenido: el consumidor lee con su identidad.
- Suscripción push autenticada (OIDC) hacia Cloud Run privado.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Deduplicar por generación | Suponer entrega única |
| Filtrar por prefijo en la notificación | Notificar todo el bucket |
| Salida en otro bucket/prefijo | Ciclos de eventos |
| DLQ en la suscripción | Reintentos infinitos |
| Verificar el objeto antes de procesar | Asumir que sigue igual |

## 8. Límites, costos y versiones
- **Costo:** Pub/Sub por volumen; Eventarc según el tipo de evento *(verifica)*.
- **Límites** (verifica): notificaciones por bucket, tamaño del mensaje.
- **Terraform:** `google_storage_notification`, `google_pubsub_topic`, `google_pubsub_subscription`, `google_eventarc_trigger`.
- **Java:** consumidor HTTP (push) o `Subscriber` de Pub/Sub; verificación con `Storage.get`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
