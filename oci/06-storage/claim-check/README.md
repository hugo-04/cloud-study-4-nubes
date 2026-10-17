# Oracle OCI · Storage · Patrón claim check (mensajes grandes)

Las colas y los streams tienen un tamaño máximo de mensaje pequeño. El patrón **claim check** guarda la carga pesada en Object Storage y envía por la cola solo un **ticket** con la referencia (bucket, objeto, huella SHA-256, tamaño). El consumidor canjea el ticket por el contenido.

## 1. Qué es

**Analogía:** el guardarropa de un teatro. No entras a la sala con el abrigo (la carga grande): lo dejas en el guardarropa (Object Storage) y te dan un ticket pequeño (el mensaje). Al salir, presentas el ticket y recuperas exactamente tu abrigo.

```
 Productor ──(1) PUT carga 3 MB──► Object Storage  bucket "cargas"  cargas/2026/10/17/<id>.json
     │
     └─(2) mensaje 300 bytes {tipo:REFERENCIA, objeto, sha256, bytes}──► OCI Queue
                                                                        │
 Consumidor ◄─(3) recibe ticket ───────────────────────────────────────┘
     └─(4) GET objeto, verifica sha256 ─► procesa ─► (5) borra mensaje (el objeto lo limpia el ciclo de vida)
```

## 2. Cómo funciona por dentro

### Piezas en OCI
| Pieza | Papel |
|---|---|
| **Object Storage** | Guarda la carga con nombre determinista y ciclo de vida que la borra tras N días |
| **OCI Queue / Streaming** | Transporta el ticket (tamaño máximo de mensaje pequeño *(verifica)*) |
| **Sobre (envelope)** | `INLINE` (la carga cabe) o `REFERENCIA` (ticket) |
| **Huella SHA-256** | El consumidor verifica que recuperó exactamente lo que se envió |
| **Ciclo de vida** | Borra cargas viejas: el consumidor no necesita borrar |

### Orden de las operaciones
1. **Primero** se escribe el objeto; **después** se envía el ticket (si se invierte, el consumidor puede no encontrar nada).
2. Si el envío del ticket falla, el objeto queda huérfano: el ciclo de vida lo limpia.
3. El consumidor procesa de forma idempotente (el ticket puede repetirse).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Pedido con 400 líneas y adjuntos (MB) por una cola | **Claim check** |
| Imagen o PDF que varios servicios procesan | Claim check o evento del bucket |
| Mensajes que casi siempre caben | Sobre híbrido: `INLINE` si cabe, `REFERENCIA` si no |
| Mensajes de 1 KB | **No**: complejidad innecesaria |
| Datos que deben borrarse a pedido del cliente | Cuidado: hay que borrar también el objeto |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Ticket** | Mensaje pequeño que apunta a la carga |
| **Sobre híbrido** | Decide por tamaño si va dentro o por referencia |
| **Huella** | SHA-256 para verificar integridad |
| **Huérfano** | Objeto cuyo ticket nunca se envió |

## 5. Cómo se usa
1. Bucket `cargas` privado con ciclo de vida de 7 días y una cola: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Productor y consumidor en Java: [uso en Java](uso-en-java.md).
3. Inspección: [`ejemplos/cli/claim-check.sh`](ejemplos/cli/claim-check.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Productor | — | `manage objects` (crear) en `cargas` + `use queues` (enviar) |
| Consumidor | — | `read objects` en `cargas` + `use queues` (recibir/borrar) |
| Plataforma | `manage buckets`, `manage queues` | — |

- El ticket **no** debe ser una PAR: el consumidor usa su propia identidad.
- La carga puede tener datos personales: bucket cifrado, retención mínima, sin registrar contenido.
- Verifica la huella: protege contra objetos sustituidos.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Escribir el objeto antes de enviar el ticket | Enviar el ticket primero |
| Huella SHA-256 en el ticket | Confiar en que el objeto no cambió |
| Ciclo de vida para limpiar | Borrar desde el consumidor (rompe reintentos) |
| Sobre híbrido con umbral claro | Siempre por referencia |
| Nombre determinista por id de mensaje | Nombres aleatorios difíciles de rastrear |

## 8. Límites, costos y versiones
- **Costo:** almacenamiento (pocos días) + peticiones PUT/GET + mensajes *(verifica)*.
- **Límites** (verifica): tamaño máximo de mensaje de la cola/stream; tamaño de objeto.
- **Terraform:** `oci_objectstorage_bucket`, `oci_objectstorage_object_lifecycle_policy`, `oci_queue_queue`.
- **SDK:** `ObjectStorageClient` y `QueueClient` (`oci-java-sdk-queue`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
