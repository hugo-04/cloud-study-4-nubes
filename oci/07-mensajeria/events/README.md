# Oracle OCI · Mensajería · Events (eventos de los servicios de OCI)

Cada vez que algo cambia en tu tenancy —se crea una instancia, se modifica una política, se sube un objeto, termina un respaldo— el servicio correspondiente emite un **evento**. Con **reglas** filtras los que te importan y los mandas a Notifications, Functions o Streaming. Es la forma de automatizar reacciones y vigilar cambios sin sondear.

## 1. Qué es

**Analogía:** el sistema de sensores de un edificio inteligente. Cada puerta, luz o ascensor reporta lo que pasa; tú configuras reglas («si se abre la puerta del cuarto de servidores fuera de horario, avisa a seguridad») y el edificio actúa.

```
 Servicios de OCI (Compute, IAM, Object Storage, Database…)
     │ eventos CloudEvents: eventType, source, data.compartmentId, data.resourceName…
     ▼
 Events: reglas por compartimento (condición JSON)
     ├─ "política modificada"      ──► Notifications (seguridad)
     ├─ "instancia terminada"      ──► Function (limpieza de DNS)
     └─ "todo lo de producción"    ──► Streaming (auditoría propia, análisis)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Evento** | Mensaje CloudEvents con `eventType` (`com.oraclecloud.<servicio>.<accion>`), `eventID`, `eventTime`, `data` |
| **Regla** | Condición JSON + lista de acciones + estado; vive en un compartimento y aplica a él y sus hijos |
| **Condición** | Coincidencia por `eventType` (lista) y atributos de `data` (`compartmentName`, `resourceName`, `freeformTags`…) |
| **Acción** | `ONS` (tema), `FAAS` (función), `OSS` (stream) |
| **Catálogo** | Cada servicio publica su lista de tipos de evento *(verifica en la documentación del servicio)* |

### Semántica
- Las listas dentro de un campo son **O**; los campos distintos son **Y**.
- Comodines limitados en valores de atributos *(verifica)*.
- Entrega **al menos una vez**, sin orden; la latencia típica es de segundos.
- Los eventos son de **plano de control** (cambios de recursos), no de tu aplicación: para eventos de negocio usa Queue, Notifications o Streaming directamente.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Avisar cuando alguien cambia una política IAM o una regla de red | Regla → Notifications |
| Limpiar DNS o inventario cuando se termina una instancia | Regla → Function |
| Copia propia de todos los cambios de producción para análisis | Regla → Streaming |
| Procesar archivos subidos | Regla de Object Storage → Function |
| Emitir eventos de negocio (pedido pagado) | **No**: Queue / Notifications / Streaming |
| Auditoría completa de llamadas a la API | Audit (Events cubre solo tipos publicados) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **`eventType`** | Qué pasó, con nombre de servicio y acción |
| **Condición** | Filtro JSON que decide si la regla actúa |
| **Plano de control** | Cambios de recursos, no datos de la app |
| **Automatización reactiva** | Responder a cambios en vez de revisar periódicamente |

## 5. Cómo se usa
1. Reglas de seguridad y de limpieza: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Construye condiciones válidas desde código y crea reglas: [uso en Java](uso-en-java.md).
3. Lista y prueba: [`ejemplos/cli/events.sh`](ejemplos/cli/events.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Seguridad/plataforma | `manage cloudevents-rules` | — |
| Servicio Events | — | `use ons-topics`, `use fn-invocation`, `use stream-push` (política de servicio) |
| Consumidores | — | Permisos sobre el destino |

- Las reglas son controles de seguridad: protégelas como código y vigila sus cambios (¡con otra regla!).
- No reacciones automáticamente con acciones destructivas sin validar el evento.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Reglas acotadas por tipo y compartimento | Una regla que lo manda todo a correo |
| Consumidores idempotentes por `eventID` | Asumir entrega única |
| Reglas como código | Reglas creadas a mano en la consola |
| Alertar cambios de IAM, red y llaves | Descubrirlos en la auditoría trimestral |
| Probar cada regla con un cambio real | Confiar en que «debería funcionar» |

## 8. Límites, costos y versiones
- **Costo:** sin cargo por Events; pagas los destinos *(verifica)*.
- **Límites** (verifica): reglas por tenancy, acciones por regla, tamaño de condición.
- **Terraform:** `oci_events_rule`.
- **SDK:** `EventsClient` (`oci-java-sdk-events`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
