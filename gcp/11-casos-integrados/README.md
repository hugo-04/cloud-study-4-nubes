# Google Cloud · 11 Casos integrados

Los capítulos anteriores explican **piezas**; aquí se arman **sistemas**. Cada caso resuelve un problema real de ModaLima o Café Andino combinando varios servicios, con Terraform validado, código Java compilado (Spring MVC/WebFlux y Quarkus imperativo/reactivo) y pruebas del núcleo.

| Caso | El problema | Piezas principales | Lo que enseña |
|---|---|---|---|
| [Tienda online](tienda-online/README.md) | Crear un pedido sin perder eventos ni duplicar facturas | Cloud Armor, LB, Cloud Run, Cloud SQL, Pub/Sub, Firestore, Secret Manager | Outbox, relay, inbox idempotente |
| [Subida con claim check](subida-claim-check/README.md) | Subir archivos sin pasarlos por la API | URL firmada, Cloud Storage, notificaciones, Cloud Run, Pub/Sub | Cuarentena, firma de archivo, precondiciones de generación |
| [Clickstream](clickstream/README.md) | Medir clics con orden por sesión y relectura | Managed Kafka, GKE, Memorystore, BigQuery | Ventanas por hora del evento, marca de agua, commit seguro |
| [Landing zone](landing-zone/README.md) | Abrir una unidad nueva con base segura | Carpetas, proyectos, VPC compartida, tags, grupos, presupuestos | Planificación de CIDR, verificación posterior |
| [Runbook de diagnóstico](runbook-diagnostico/README.md) | Atender un incidente con método | Cloud Monitoring, Logging, LB, Cloud Run, Audit Logs | Cadena de capas, triage automático |

## Árbol de decisión: «quiero…»

```
¿Publicar un hecho de negocio sin perderlo si falla la mensajería?
   └─ Tienda online (outbox + Pub/Sub + inbox)

¿Que usuarios suban archivos y procesarlos después?
   └─ Subida con claim check (URL firmada + notificación + estado condicional)

¿Analizar un flujo continuo con orden por clave?
   └─ Clickstream (Managed Kafka + ventanas + historial en BigQuery)

¿Abrir una unidad o producto nuevo con barandas?
   └─ Landing zone (planificador + Terraform + verificador)

¿Estar listo para el próximo incidente?
   └─ Runbook (alertas por síntoma + triage + postmortem)
```

## Comparativa

| Característica | Tienda | Subida | Clickstream | Landing zone | Runbook |
|---|---|---|---|---|---|
| **Patrón central** | Outbox/inbox | Claim check + máquina de estados | Ventanas + marca de agua | IaC + verificación | Triage por capas |
| **Garantía clave** | Ni pérdida ni duplicado | Nada sin validar | Orden por sesión | Sin solapes | Lo desconocido es hallazgo |
| **Error típico** | Publicar después del commit | Validar por extensión | Contar por hora de llegada | Olvidar rangos secundarios | Alertar por CPU |

## La receta ModaLima
| Momento | Caso |
|---|---|
| Lanzar la tienda | Landing zone → tienda online |
| Cargar el catálogo de la temporada | Subida con claim check |
| Cyber | Clickstream para el tablero + runbook listo |
| Después de cada incidente | Postmortem y mejora de alertas |

## Orden recomendado de adopción
1. Landing zone.
2. Tienda online (outbox desde el primer evento).
3. Runbook y alertas por síntoma antes de abrir al público.
4. Subida con claim check para el catálogo.
5. Clickstream cuando el tráfico lo justifique.

## Reglas transversales
- Al menos una vez en todas partes: idempotencia.
- Todo privado salvo el borde (Cloud Armor + LB).
- Identidad sin llaves (SA adjunta, Workload Identity, federación).
- Como código y verificado.
- Lo que no se puede comprobar se reporta.

## Java en los casos: qué construye cada `uso-en-java.md`
| Caso | Qué construyes | Patrón común |
|---|---|---|
| Tienda online | Relay del outbox + inbox, publicador con clave de orden | Repositorio y publicador como interfaces |
| Subida | Validación por firma + copia con `generationMatch` | Máquina de estados pura |
| Clickstream | Agregador con marca de agua + `KafkaConsumer` con commit manual | Commit tras escribir |
| Landing zone | Planificador de CIDR con rangos secundarios | Lectura agregada de subredes |
| Runbook | Triage por capas con `listTimeSeries` | DESCONOCIDO ≠ OK |

## Cómo se relaciona con otros capítulos
Cada caso enlaza a las unidades que usa: [Red](../01-red/README.md), [IAM](../02-iam/README.md), [Secretos](../03-secretos/README.md), [Compute](../04-compute/README.md), [Ingress](../05-ingress-api/README.md), [Storage](../06-storage/README.md), [Mensajería](../07-mensajeria/README.md), [Datos](../08-datos/README.md), [Gobierno](../09-gobierno/README.md), [Terraform](../10-terraform/README.md).

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
