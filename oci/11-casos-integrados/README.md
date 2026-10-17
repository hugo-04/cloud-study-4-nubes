# Oracle OCI · 11 Casos integrados

Los capítulos anteriores explican **piezas**; aquí se arman **sistemas**. Cada caso resuelve un problema real de ModaLima o Café Andino combinando varios servicios, con Terraform validado, código Java compilado (Spring MVC/WebFlux y Quarkus imperativo/reactivo) y pruebas del núcleo.

| Caso | El problema | Piezas principales | Lo que enseña |
|---|---|---|---|
| [Tienda online](tienda-online/README.md) | Crear un pedido sin perder eventos ni duplicar facturas | WAF, LB, OKE, ATP, Queue, Notifications, NoSQL, Vault | Outbox, relay, inbox idempotente |
| [Subida con claim check](subida-claim-check/README.md) | Subir archivos grandes sin pasarlos por la API | PAR, Object Storage, Events, Functions, Queue | Cuarentena, firma de archivo, transiciones condicionales |
| [Clickstream](clickstream/README.md) | Medir clics con orden por sesión y relectura | API Gateway, Streaming, OCI Cache, Service Connector | Ventanas por hora del evento, marca de agua, commit seguro |
| [Landing zone](landing-zone/README.md) | Abrir una unidad nueva con base segura | Compartimentos, IAM, VCN, cuotas, presupuestos, Cloud Guard | Planificación de CIDR, verificación posterior |
| [Runbook de diagnóstico](runbook-diagnostico/README.md) | Atender un incidente con método | Monitoring, Notifications, LB, Audit | Roles, cadena de capas, triage automático |

## Árbol de decisión: «quiero…»

```
¿Publicar un hecho de negocio sin perderlo si falla la mensajería?
   └─ Tienda online (outbox + Queue/Notifications + inbox)

¿Que usuarios suban archivos grandes y procesarlos después?
   └─ Subida con claim check (PAR + evento + estado condicional)

¿Analizar un flujo continuo con orden por clave?
   └─ Clickstream (Streaming + ventanas + historial)

¿Abrir una unidad o producto nuevo con guardarraíles?
   └─ Landing zone (planificador + Terraform + verificador)

¿Estar listo para el próximo incidente?
   └─ Runbook (alarmas por síntoma + triage + postmortem)
```

## Comparativa

| Característica | Tienda | Subida | Clickstream | Landing zone | Runbook |
|---|---|---|---|---|---|
| **Patrón central** | Outbox/inbox | Claim check + máquina de estados | Ventanas + marca de agua | IaC + verificación | Triage por capas |
| **Garantía clave** | Ni pérdida ni duplicado | Nada sin validar | Orden por sesión | Sin solapes | Lo desconocido es hallazgo |
| **Error típico** | Publicar después del commit | Validar por extensión | Contar por hora de llegada | CIDR elegido al azar | Alarmar por CPU |

## La receta ModaLima
| Momento | Caso |
|---|---|
| Lanzar la tienda | Landing zone → tienda online |
| Cargar el catálogo de la temporada | Subida con claim check |
| Cyber | Clickstream para el tablero + runbook listo |
| Después de cada incidente | Postmortem y mejora de alarmas |

## Orden recomendado de adopción
1. Landing zone.
2. Tienda online (outbox desde el primer evento).
3. Runbook y alarmas por síntoma antes de abrir al público.
4. Subida con claim check para el catálogo.
5. Clickstream cuando el tráfico lo justifique.

## Reglas transversales
- Al menos una vez en todas partes: idempotencia.
- Todo privado salvo el borde (WAF/LB/API Gateway).
- Identidad sin llaves (workload/instance/resource principal).
- Como código y verificado.
- Lo que no se puede comprobar se reporta.

## Java en los casos: qué construye cada `uso-en-java.md`
| Caso | Qué construyes | Patrón común |
|---|---|---|
| Tienda online | Relay del outbox + inbox | Repositorio y publicador como interfaces |
| Subida | Validación por firma + `renameObject` condicional | Máquina de estados pura |
| Clickstream | Agregador con marca de agua + lector de grupo | Commit tras escribir |
| Landing zone | Planificador de CIDR sin solapes | Lectura paginada de todo el tenancy |
| Runbook | Triage por capas con métricas MQL | DESCONOCIDO ≠ OK |

## Cómo se relaciona con otros capítulos
Cada caso enlaza a las unidades que usa: [Red](../01-red/README.md), [IAM](../02-iam/README.md), [Secretos](../03-secretos/README.md), [Compute](../04-compute/README.md), [Ingress](../05-ingress-api/README.md), [Storage](../06-storage/README.md), [Mensajería](../07-mensajeria/README.md), [Datos](../08-datos/README.md), [Gobierno](../09-gobierno/README.md), [Terraform](../10-terraform/README.md).

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
