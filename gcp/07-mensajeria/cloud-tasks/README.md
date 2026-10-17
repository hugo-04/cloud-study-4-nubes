# Google Cloud · Mensajería · Cloud Tasks

Cola de **tareas dirigidas**: cada tarea es una petición HTTP (o a App Engine) que Cloud Tasks entregará a **un** destino concreto, con **tasa controlada**, **reintentos** con backoff, **agenda** (ejecutar a una hora) y **deduplicación por nombre**. A diferencia de Pub/Sub, el productor decide a quién va y cuándo.

## 1. Qué es

**Analogía:** la agenda de un mensajero. Anotas «llevar este sobre a esta oficina mañana a las 9»; el mensajero sale a esa hora, no lleva más de N sobres por minuto para no saturar la oficina y, si la oficina está cerrada, vuelve a intentar más tarde.

```
 Servicio de pedidos ── createTask(nombre = recordatorio-P-100, scheduleTime = +24h) ──► Cola "recordatorios"
                                                                        (máx. 50/s, 20 en paralelo, 10 intentos, backoff 10s..5min)
 Cloud Tasks ── POST https://correos-xyz.a.run.app/recordatorio  (OIDC de la SA de tareas) ──► Cloud Run privado
              └─ 2xx = hecha · otro código = reintento
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Cola** | Configuración de tasa (`maxDispatchesPerSecond`, `maxConcurrentDispatches`) y reintentos |
| **Tarea** | Destino HTTP (URL, método, cabeceras, cuerpo), hora programada, nombre opcional |
| **Nombre de tarea** | Si lo das, se **deduplica**: crear otra con el mismo nombre falla durante un tiempo *(verifica ventana)* |
| **Autenticación** | OIDC (Cloud Run/servicios propios) u OAuth (APIs de Google) con una cuenta de servicio |
| **Reintentos** | Máximo de intentos, duración máxima, backoff mínimo/máximo |
| **Plazo de entrega** | Tiempo que espera la respuesta del destino |

### Comparación rápida
| | Cloud Tasks | Pub/Sub |
|---|---|---|
| Destino | Uno, elegido por el productor | Todas las suscripciones |
| Tasa | Controlada por la cola | Según los consumidores |
| Agenda | Sí (`scheduleTime`) | No |
| Deduplicación | Por nombre de tarea | Por idempotencia del consumidor (o exactly-once) |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Recordatorio de carrito abandonado en 24 h | **Cloud Tasks** con agenda |
| Llamar a una API externa con límite de tasa | **Cloud Tasks** con `maxDispatchesPerSecond` |
| Trabajo pesado que no debe bloquear la petición del usuario | **Cloud Tasks** hacia un Cloud Run |
| Avisar a muchos sistemas del mismo hecho | [Pub/Sub](../pubsub/README.md) |
| Flujos de varios pasos con estado | Workflows |
| Tareas periódicas | Cloud Scheduler |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Despacho** | Cuando Cloud Tasks llama al destino |
| **Tasa de despacho** | Llamadas por segundo máximas |
| **Nombre determinista** | Mismo hecho ⇒ mismo nombre ⇒ sin duplicados |
| **OIDC** | Token de identidad para el destino privado |
| **Backoff** | Esperar más en cada reintento |

## 5. Cómo se usa
1. Cola con tasa y reintentos, cuenta de servicio de despacho y permiso de invocar: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Crear tareas con nombre determinista, agenda y OIDC desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/tasks.sh`](ejemplos/cli/tasks.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/cloudtasks.admin` | — |
| Productor | `roles/cloudtasks.enqueuer` + `iam.serviceAccountUser` sobre la SA de despacho | — |
| SA de despacho | — | `roles/run.invoker` sobre el destino |

- El destino es privado y acepta solo la SA de despacho.
- No pongas secretos en el cuerpo ni en cabeceras de la tarea.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Nombre determinista por hecho de negocio | Tareas anónimas que se duplican al reintentar |
| Tasa acorde al destino | Saturar una API externa |
| Destino idempotente | Suponer una sola entrega |
| Reintentos con tope | Reintentar para siempre |
| OIDC hacia Cloud Run | Destino público |

## 8. Límites, costos y versiones
- **Costo:** por millón de operaciones con nivel gratuito *(verifica)*.
- **Límites** (verifica): tamaño de la tarea (1 MB), programación máxima a futuro (30 días), tasa por cola.
- **Terraform:** `google_cloud_tasks_queue`, `google_cloud_tasks_queue_iam_member`.
- **Java:** `CloudTasksClient` (`google-cloud-tasks`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
