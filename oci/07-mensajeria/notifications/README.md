# Oracle OCI · Mensajería · Notifications (publicar/suscribir)

Servicio de publicación/suscripción: publicas un mensaje en un **tema** y OCI lo entrega a todas sus **suscripciones**: correo, SMS, HTTPS (webhooks), Slack, PagerDuty, funciones *(verifica la lista vigente)*. Es el megáfono para avisos y para conectar alarmas y eventos con personas o sistemas.

## 1. Qué es

**Analogía:** un grupo de difusión. Escribes una vez en el grupo (tema) y le llega a todos los que se unieron (suscripciones), cada uno en su aplicación. Para unirse hay que aceptar la invitación (confirmación).

```
 Alarmas de Monitoring ─┐
 Reglas de Events ──────┼─► Tema "alertas-tienda" ──► correo a operaciones (confirmado)
 Tu app (SDK) ──────────┘                          ├─► HTTPS a tu webhook (confirmado)
                                                   ├─► Slack / PagerDuty
                                                   └─► Function (procesamiento)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Tema (topic)** | Canal con nombre único en el tenancy y un endpoint de API |
| **Suscripción** | Protocolo + endpoint; queda `PENDING` hasta confirmarse (excepto funciones) |
| **Mensaje** | Título + cuerpo de texto (tamaño máximo *(verifica)*) |
| **Política de entrega** | Reintentos con *backoff* durante un tiempo máximo a endpoints HTTPS |
| **Formato** | `RAW_TEXT`, `JSON`, `ONS_OPTIONAL_*` según el protocolo |

### Entrega
- Cada suscripción recibe su copia de forma independiente.
- Entrega **al menos una vez**; sin orden garantizado.
- Si el endpoint HTTPS falla, OCI reintenta un tiempo y luego descarta (no hay DLQ propia).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Alarma de CPU o errores → correo y PagerDuty | **Notifications** |
| Avisar a varios sistemas de un evento de OCI | Events → **Notifications** |
| Un evento de negocio a varios webhooks internos | **Notifications** (HTTPS) |
| Trabajo que debe procesarse sí o sí con reintentos largos | [Queue](../queue/README.md) |
| Historial o reprocesamiento | [Streaming](../streaming/README.md) |
| Correos de marketing o transaccionales a clientes | **No**: Email Delivery |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Fan-out** | Un mensaje, muchas copias |
| **Confirmación** | El dueño del endpoint acepta recibir |
| **Webhook** | Tu endpoint HTTPS que recibe POST |
| **Tormenta de alertas** | Cientos de avisos iguales en minutos |

## 5. Cómo se usa
1. Tema y suscripciones de correo y HTTPS: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Publica desde tu app con agrupación para evitar tormentas: [uso en Java](uso-en-java.md).
3. Publica y lista suscripciones: [`ejemplos/cli/notifications.sh`](ejemplos/cli/notifications.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage ons-topics`, `manage ons-subscriptions` | — |
| App que publica | — | `use ons-topics` |
| Monitoring / Events | — | Publican con política de servicio |

- Webhooks HTTPS con certificado válido; valida en tu endpoint el origen y que el mensaje tenga la forma esperada.
- No envíes datos personales ni secretos en alertas: van a correos y chats.
- Limita quién puede crear suscripciones (alguien podría suscribir un correo externo).

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Un tema por audiencia/severidad | Un tema para todo |
| Agrupar alertas repetidas | 500 correos iguales en 5 minutos |
| Títulos cortos y accionables | Volcar un *stack trace* en el título |
| Confirmar y revisar suscripciones periódicamente | Suscripciones `PENDING` olvidadas |
| Webhook idempotente | Suponer una sola entrega |

## 8. Límites, costos y versiones
- **Costo:** por entregas según protocolo (HTTPS, correo, SMS con tarifa propia), con cuota gratuita *(verifica)*.
- **Límites** (verifica): temas y suscripciones por tenancy, tamaño de mensaje, tasa de publicación.
- **Terraform:** `oci_ons_notification_topic`, `oci_ons_subscription`.
- **SDK:** `NotificationControlPlaneClient`, `NotificationDataPlaneClient` (`oci-java-sdk-ons`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
