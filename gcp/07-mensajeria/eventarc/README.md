# Google Cloud · Mensajería · Eventarc

Enrutador de **eventos** en formato **CloudEvents**: recoge eventos de servicios de Google (directos como Cloud Storage o Pub/Sub, o cualquier operación registrada en **Cloud Audit Logs**), de tus propias aplicaciones (canales) y de terceros, y los entrega por **disparadores** a Cloud Run, Cloud Run functions, GKE, Workflows o endpoints HTTP internos.

## 1. Qué es

**Analogía:** la central de alarmas de un edificio inteligente. Cada sensor (servicio) reporta; la central (Eventarc) mira el tipo de alarma y el lugar (filtros) y avisa al equipo correcto (destino) con un formato común.

```
 Fuentes:  Cloud Storage (object.v1.finalized) · Pub/Sub (messagePublished) · Audit Logs (SetIamPolicy…) · canales propios
               │ CloudEvents (ce-id, ce-type, ce-source, ce-subject, ce-time)
               ▼
 Disparador "iam-cambiado"  filtros: type=google.cloud.audit.log.v1.written, serviceName=…, methodName=SetIamPolicy
               │ transporte Pub/Sub (reintentos)  · SA del disparador (run.invoker)
               ▼
 Destino: Cloud Run "seguridad-alertas" (privado)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Proveedor/fuente** | Servicio que emite (Storage, Pub/Sub, Audit Logs, Firestore, terceros) |
| **Tipo de evento** | `google.cloud.storage.object.v1.finalized`, `google.cloud.audit.log.v1.written`… |
| **Disparador** | Filtros + destino + cuenta de servicio + transporte |
| **Filtros** | Atributos exactos (y patrones en algunos *(verifica)*) |
| **Transporte** | Normalmente un tema de Pub/Sub administrado (reintentos, retención) |
| **Destino** | Cloud Run, Cloud Run functions, GKE, Workflows, HTTP interno |
| **Canales** | Para eventos propios o de terceros |
| **Modo binario** | Atributos en cabeceras `ce-*` y datos en el cuerpo |

### Garantías
Al menos una vez; el destino debe responder 2xx; deduplica por `ce-id` + `ce-source`.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Reaccionar a cambios de IAM, red o buckets en todo el proyecto | Eventarc + Audit Logs |
| Procesar archivos subidos | Eventarc (Storage directo) o notificación a Pub/Sub |
| Orquestar pasos con estado tras un evento | Eventarc → Workflows |
| Eventos de negocio entre tus servicios con mucho volumen | [Pub/Sub](../pubsub/README.md) directo |
| Tareas con tasa y agenda | [Cloud Tasks](../cloud-tasks/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **CloudEvents** | Estándar de formato de eventos |
| **`ce-id` / `ce-source`** | Identidad única del evento |
| **Audit Logs como fuente** | Cualquier operación registrada puede disparar |
| **Transporte** | El tema interno que da reintentos |
| **SA del disparador** | Identidad con la que se invoca el destino |

## 5. Cómo se usa
1. Disparador de Audit Logs hacia Cloud Run con su cuenta y permisos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Receptor que lee cabeceras `ce-*`, deduplica y filtra; auditoría de disparadores desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/eventarc.sh`](ejemplos/cli/eventarc.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/eventarc.admin` | — |
| SA del disparador | `roles/eventarc.eventReceiver` | `roles/run.invoker` sobre el destino |
| Agente de Pub/Sub | Crear tokens para la SA (`serviceAccountTokenCreator`) *(verifica)* | — |

- Destino privado; la SA del disparador es la única con `run.invoker`.
- Los eventos de Audit Logs pueden contener datos sensibles: limita quién los recibe.
- Activa los Data Access logs necesarios para que existan esos eventos.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Filtros precisos (servicio + método) | Disparar con todo Audit Logs |
| Deduplicar por `ce-id` + `ce-source` | Suponer entrega única |
| SA propia por disparador | La cuenta por defecto de Compute |
| Responder 2xx cuando el evento ya se decidió | Errores que provocan reintentos eternos |
| Disparadores como código | Crearlos en la consola |

## 8. Límites, costos y versiones
- **Costo:** eventos de Google sin cargo para varias fuentes; eventos de canales y de terceros por millón; Pub/Sub del transporte *(verifica)*.
- **Límites** (verifica): disparadores por región, tamaño del evento, latencia de los eventos de Audit Logs.
- **Terraform:** `google_eventarc_trigger`, `google_eventarc_channel`.
- **Java:** `EventarcClient` (`google-cloud-eventarc`); el receptor es un endpoint HTTP normal.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
