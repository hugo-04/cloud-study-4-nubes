# Oracle OCI · Storage · Eventos de Object Storage

Cuando se crea, actualiza o borra un objeto, Object Storage puede emitir un **evento**; una **regla** del servicio Events lo filtra y lo entrega a una función, un tema de Notifications o un stream. Es la base de todo flujo «subo un archivo y algo pasa».

## 1. Qué es

**Analogía:** el timbre con cámara de la casa. Cada vez que alguien deja un paquete (objeto), suena y te manda una foto con los datos (evento); tú decides con reglas si te importa (solo paquetes en la puerta principal) y a quién avisar.

```
 Bucket "fotos" (object_events_enabled = true)
    │ com.oraclecloud.objectstorage.createobject
    ▼
 Events: regla (condición JSON: tipo de evento + bucket)
    ├─► Function "miniaturas"     (procesa la imagen)
    ├─► Notifications topic       (correo/Slack/HTTP)
    └─► Streaming                 (otros consumidores)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Eventos del bucket** | Se activan por bucket (`object_events_enabled`); sin eso no se emite nada |
| **Tipos** | `createobject`, `updateobject`, `deleteobject` (prefijo `com.oraclecloud.objectstorage.`) |
| **Regla** | Condición JSON sobre `eventType` y `data` (bucket, compartimento, nombre) + acciones |
| **Acciones** | `FAAS` (función), `ONS` (Notifications), `OSS` (Streaming) |
| **Formato** | CloudEvents: `eventType`, `eventID`, `eventTime`, `source`, `data.resourceName`, `data.additionalDetails.bucketName` |

### Garantías
- Entrega **al menos una vez**: puede repetirse un evento (mismo `eventID`).
- **Sin orden** garantizado entre eventos.
- Puede llegar segundos después del cambio; para cuando lo procesas, el objeto quizá ya no existe o cambió (compara ETag).
- El filtro de la regla es por coincidencia de atributos; filtros por prefijo o sufijo se hacen en el consumidor *(verifica soporte de comodines)*.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Generar miniaturas al subir una foto | Evento → Function |
| Avisar a operaciones cuando llega el archivo de un socio | Evento → Notifications |
| Varios sistemas reaccionan al mismo archivo | Evento → Streaming (o tema con varias suscripciones) |
| Procesar archivos ya existentes | **No**: un proceso por lotes que lista el bucket |
| Exigir orden estricto | **No**: añade un número de secuencia propio |
| Disparar con cada cambio de millones de objetos por minuto | Diseña con cuidado límites y costos |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **`eventID`** | Identificador único del evento: úsalo para deduplicar |
| **Al menos una vez** | Puede llegar repetido, nunca debería perderse |
| **Idempotencia** | Procesar dos veces no cambia el resultado |
| **Ciclo de eventos** | Escribir el resultado en el mismo bucket/prefijo vuelve a disparar la regla |

## 5. Cómo se usa
1. Activa eventos en el bucket y crea la regla con acción a función: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. En el consumidor: filtra, deduplica por `eventID`, verifica el objeto con `HEAD`: [uso en Java](uso-en-java.md).
3. Escribe resultados en **otro** prefijo o bucket.
4. Prueba: [`ejemplos/cli/eventos.sh`](ejemplos/cli/eventos.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage cloudevents-rules` | — |
| Events (servicio) | — | `use fn-invocation` / `use ons-topics` / `use stream-push` (política de servicio) |
| Consumidor | — | `read objects` del bucket de origen; `manage objects` en el destino |

- El evento no lleva el contenido del archivo: el consumidor lo lee con su propia identidad.
- No confíes en el nombre del objeto: valídalo (puede venir de un usuario).

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Deduplicar por `eventID` | Suponer «exactamente una vez» |
| Resultado en otro prefijo/bucket | Escribir donde dispara la regla (ciclo) |
| `HEAD` del objeto antes de procesar | Asumir que sigue existiendo |
| Reglas acotadas por bucket | Una regla para todo el tenancy |
| Registrar `eventID` y nombre | Registrar contenido |

## 8. Límites, costos y versiones
- **Costo:** Events sin cargo propio; pagas el destino (funciones, notificaciones, streaming) *(verifica)*.
- **Límites** (verifica): reglas por tenancy, acciones por regla, tamaño de la condición.
- **Terraform:** `oci_objectstorage_bucket` (`object_events_enabled`), `oci_events_rule`.
- **SDK:** el consumidor usa `ObjectStorageClient`; reglas con `EventsClient` (`oci-java-sdk-events`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
