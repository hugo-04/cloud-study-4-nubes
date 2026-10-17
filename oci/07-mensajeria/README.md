# Oracle OCI · 07 Mensajería

¿Cómo se hablan mis servicios sin esperarse unos a otros? Cuatro piezas con garantías distintas: tareas, avisos, cambios de la nube y flujos de eventos.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Queue](queue/README.md) | ¿Cómo reparto trabajo que debe hacerse sí o sí? | La ventanilla de tickets de la cocina | Tareas con reintento y DLQ |
| [Notifications](notifications/README.md) | ¿Cómo aviso a muchos a la vez? | Un grupo de difusión | Alertas, webhooks, *fan-out* |
| [Events](events/README.md) | ¿Cómo reacciono a cambios en mis recursos de OCI? | Los sensores del edificio inteligente | Seguridad, limpieza, automatización |
| [Streaming](streaming/README.md) | ¿Cómo muevo flujos grandes que varios leen y releen? | La grabación de las cámaras | Clickstream, telemetría, Kafka |

## Árbol de decisión: «quiero…»

```
¿Es una tarea que un solo consumidor debe completar, con reintentos?
   └─ Queue (visibilidad, borrar al terminar, DLQ)

¿Varios destinos (personas o sistemas) deben enterarse del mismo hecho?
   ├─ ¿Personas, chat, PagerDuty, webhooks?      → Notifications
   └─ ¿Sistemas que leen a su ritmo y rebobinan? → Streaming

¿El hecho es un cambio de un recurso de OCI (política, instancia, objeto)?
   └─ Events → (Notifications | Functions | Streaming)

¿Ya uso clientes Kafka?
   └─ Streaming con el protocolo Kafka

¿El mensaje pesa más que el máximo?
   └─ Claim check con Object Storage
```

## Comparativa

| Característica | Queue | Notifications | Events | Streaming |
|---|---|---|---|---|
| **Modelo** | Cola (un consumidor por mensaje) | Pub/sub *push* | Reglas sobre eventos de OCI | Registro particionado *pull* |
| **Quién produce** | Tu app | Tu app, alarmas, Events | Servicios de OCI | Tu app |
| **Releer** | No | No | No | Sí (dentro de la retención) |
| **Orden** | No estricto | No | No | Por partición |
| **Reintentos** | Visibilidad + DLQ | Reintento de entrega | Al menos una vez | Desde el offset |
| **Error típico** | Borrar al recibir | Suscripción `PENDING` | Regla en otro compartimento | Clave constante |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Facturar cada pedido pagado | Queue con DLQ | Debe hacerse una vez, con reintentos |
| Avisar a despacho y a la guardia | Notifications (HTTPS + correo) | *Fan-out* simple |
| Vigilar cambios de IAM y red | Events → Notifications | Seguridad reactiva |
| Clickstream para analítica y recomendaciones | Streaming con 2 grupos | Alto volumen, varios lectores |
| Pedidos mayoristas grandes | Claim check + Queue | Tamaño |

## Orden recomendado de adopción
1. Queue para desacoplar el primer proceso lento (correos, facturación).
2. Notifications para alertas (con agrupación) y webhooks internos.
3. Events para seguridad y limpieza automática.
4. Streaming cuando aparezca alto volumen o varios lectores.
5. Exportar streams a Object Storage para historial.

## Reglas transversales
- **Al menos una vez** en todo: consumidores idempotentes.
- Endpoints privados o puerta de servicios; nada por Internet si no hace falta.
- Mensajes con identificadores, no con datos personales completos.
- Alarmas sobre DLQ, lag y suscripciones pendientes.
- Todo como código.

## Java en mensajería: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Queue | Consumidor idempotente con *backoff* por visibilidad | Borrar al terminar |
| Notifications | Publicador de alertas con agrupación por ventana | Reloj inyectable |
| Events | Constructor validado de condiciones + `createRule` | Validar antes de enviar |
| Streaming | Productor por lotes con reintento de fallidos | Fallos parciales |

## Cómo se relaciona con otros capítulos
- [Compute](../04-compute/README.md): funciones como destino de reglas y consumidores en OKE.
- [Storage](../06-storage/README.md): eventos de buckets y claim check.
- [Gobierno](../09-gobierno/README.md): alarmas y auditoría.
- [Casos integrados](../11-casos-integrados/README.md): clickstream y tienda en línea.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
