# Google Cloud · 07 Mensajería

¿Cómo se comunican mis servicios sin esperarse, y cómo reacciono a lo que pasa en la nube?

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Pub/Sub](pubsub/README.md) | ¿Cómo difundo eventos a varios consumidores? | Megafonía con buzones por equipo | Eventos de negocio, desacoplar |
| [Cloud Tasks](cloud-tasks/README.md) | ¿Cómo encargo trabajo a un endpoint con tasa y agenda? | Agenda de recados con mensajero | Recordatorios, llamadas limitadas |
| [Eventarc](eventarc/README.md) | ¿Cómo reacciono a eventos de Google y de Audit Logs? | Central de alarmas del edificio | Cambios de IAM, archivos, auditoría |
| [Managed Kafka](managed-kafka/README.md) | ¿Y si necesito Kafka (orden, relectura, ecosistema)? | Centro de distribución con estantes | Clickstream, Kafka Streams/Connect |

## Árbol de decisión: «quiero…»

```
¿Un evento lo consumen varios sistemas?                  → Pub/Sub (un tema, una suscripción por consumidor)
   ├─ ¿Necesito orden por clave, compactación, offsets?   → Managed Kafka
   └─ ¿Reaccionar a algo que hizo Google (IAM, bucket)?    → Eventarc
¿Un trabajo va a un único endpoint, con tasa o a una hora? → Cloud Tasks (nombre determinista)
```

## Comparativa

| Característica | Pub/Sub | Cloud Tasks | Eventarc | Managed Kafka |
|---|---|---|---|---|
| **Modelo** | Pub/sub | Cola de tareas HTTP | Enrutado de CloudEvents | Log particionado |
| **Destinatarios** | Muchos | Uno | Uno por disparador | Muchos grupos |
| **Orden** | Por clave (opcional) | No | No | Por partición |
| **Relectura** | Seek por tiempo/snapshot | No | No | Por offset |
| **Operación** | Ninguna | Ninguna | Ninguna | Capacidad y particiones |
| **Error típico** | Sin DLQ ni dedupe | Tareas sin nombre | Filtro amplio | Sin clave |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| `pedido-creado` a pagos, correo y analítica | Pub/Sub con DLQ y dedupe | Difusión desacoplada |
| Recordatorio de carrito a las 24 h | Cloud Tasks con OIDC | Agenda e idempotencia |
| Alerta por cambios de IAM | Eventarc + Audit Logs → Cloud Run | Reacción en minutos |
| Clickstream con agregados por sesión | Managed Kafka (clave = sesión) | Orden y relectura |

## Orden recomendado de adopción
1. Pub/Sub con DLQ y consumidores idempotentes.
2. Cloud Tasks para trabajo dirigido.
3. Eventarc para seguridad y automatización.
4. Managed Kafka solo cuando el ecosistema Kafka se justifique.

## Reglas transversales
- Al menos una vez en todo: deduplica.
- Responde 2xx a lo ya decidido; reintenta solo lo transitorio.
- Identidad propia por productor, consumidor y disparador.
- Temas, colas y disparadores como código.
- Vigila backlog/lag y la cola de mensajes muertos.

## Java en mensajería: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Pub/Sub | Publicador con atributos y consumidor con dedupe | Lógica pura + adaptador |
| Cloud Tasks | Programador con nombre determinista y OIDC | `ALREADY_EXISTS` = éxito |
| Eventarc | Receptor de CloudEvents y auditor de disparadores | Cabeceras `ce-*` |
| Managed Kafka | Propiedades OAUTHBEARER, dimensionado y Admin | Cliente Kafka estándar |

## Cómo se relaciona con otros capítulos
- [IAM](../02-iam/README.md): cuentas por productor/consumidor.
- [Compute](../04-compute/README.md): consumidores en Cloud Run y GKE.
- [Storage](../06-storage/README.md): notificaciones y claim check.
- [Datos](../08-datos/README.md): destino de los eventos.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
