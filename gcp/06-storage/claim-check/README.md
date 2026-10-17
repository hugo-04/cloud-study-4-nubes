# Google Cloud · Storage · Patrón claim check (mensajes grandes)

Pub/Sub acepta mensajes de hasta 10 MB *(verifica)*, pero mensajes grandes son caros, lentos y difíciles de reprocesar. El **claim check** guarda la carga en **Cloud Storage** y publica en Pub/Sub solo un **ticket** pequeño (objeto, generación, SHA-256, tamaño). El consumidor canjea el ticket por el contenido.

## 1. Qué es

**Analogía:** el guardarropa de un teatro: dejas el abrigo, te dan un ticket, y al salir canjeas el ticket por exactamente tu abrigo.

```
 Productor ─(1) create(doesNotExist) cargas/<id>.json ─► Cloud Storage (generación G)
     └─(2) publish {tipo:REF, objeto, generación G, sha256, bytes}  (300 bytes) ─► Pub/Sub "pedidos-mayoristas"
 Consumidor ◄─(3) mensaje ─ (4) get(objeto, G), verifica sha256 ─ procesa ─ ack
 Ciclo de vida: borrar cargas/ a los 7 días
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Papel |
|---|---|
| **Cloud Storage** | Guarda la carga; la **generación** fija la versión exacta |
| **Pub/Sub** | Transporta el ticket con atributos (`tipo`, `objeto`) |
| **Sobre híbrido** | En línea si cabe bajo un umbral, por referencia si no |
| **SHA-256** | Verificación de integridad al canjear |
| **Ciclo de vida** | Limpia cargas viejas (y huérfanas) |

### Orden
1. Escribir el objeto (con `doesNotExist`) y obtener su generación.
2. Publicar el ticket.
3. Si la publicación falla, el objeto queda huérfano: el ciclo de vida lo borra.
4. El consumidor es idempotente; no borra la carga (para permitir reintentos).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Pedidos mayoristas de varios MB | **Claim check** |
| Mensajes que casi siempre caben | Sobre híbrido |
| Mensajes de pocos KB | **No** |
| Datos que deben borrarse a pedido del cliente | Diseña el borrado de la carga también |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Ticket** | Mensaje pequeño que apunta a la carga |
| **Generación** | Versión exacta del objeto |
| **Huella** | SHA-256 para verificar |
| **Huérfano** | Carga sin ticket |

## 5. Cómo se usa
1. Bucket de cargas con ciclo de vida, tema y suscripción con DLQ: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Productor y consumidor en [Java](uso-en-java.md).
3. Inspección: [`ejemplos/cli/claim-check.sh`](ejemplos/cli/claim-check.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Productor | — | `storage.objectCreator` en el bucket + `pubsub.publisher` en el tema |
| Consumidor | — | `storage.objectViewer` + `pubsub.subscriber` |

- El ticket no es una URL firmada: el consumidor usa su identidad.
- Carga con datos personales: bucket con CMEK, retención mínima, sin registrar contenido.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Objeto antes que ticket | Publicar antes de escribir |
| Generación y SHA-256 en el ticket | Leer «la última versión» |
| Ciclo de vida | Borrar desde el consumidor |
| Umbral para el sobre híbrido | Siempre por referencia |

## 8. Límites, costos y versiones
- **Costo:** almacenamiento corto + operaciones + mensajes *(verifica)*.
- **Límites** (verifica): tamaño de mensaje de Pub/Sub, tamaño de objeto.
- **Terraform:** `google_storage_bucket`, `google_pubsub_topic`, `google_pubsub_subscription`.
- **Java:** `Storage` y `Publisher` (`google-cloud-pubsub`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
