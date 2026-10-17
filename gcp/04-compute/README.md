# Google Cloud · 04 Compute

¿Dónde corre mi código? Cuatro respuestas, de más control a menos administración.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Compute Engine](compute-engine/README.md) | ¿Necesito una máquina completa? | Departamentos con plano tipo y administrador | SO, agentes, GPU, legados |
| [GKE](gke/README.md) | ¿Tengo muchos microservicios con plataforma común? | Edificio con administración | Plataforma Kubernetes |
| [Cloud Run](cloud-run/README.md) | ¿Solo quiero correr un contenedor HTTP o un job? | Taxis por aplicación | APIs sin estado, jobs |
| [Cloud Run functions](cloud-functions/README.md) | ¿Es una reacción corta a un evento? | Empleado por horas | Eventos y webhooks |

## Árbol de decisión: «quiero…»

```
¿Necesito el SO, agentes o GPU especial?               → Compute Engine (MIG + plantilla)
¿Muchos microservicios, malla, políticas de plataforma? → GKE Autopilot
¿Una API HTTP/gRPC sin estado?                          → Cloud Run (servicio)
¿Una tarea que corre y termina?                         → Cloud Run jobs (o VMs Spot en MIG para lotes grandes)
¿Reaccionar a un evento con poco código?                → Cloud Run functions
```

## Comparativa

| Característica | Compute Engine | GKE | Cloud Run | Functions |
|---|---|---|---|---|
| **Qué administras** | SO y app | Manifiestos (y nodos en Standard) | Imagen y configuración | Código |
| **Escala a cero** | No | No (Autopilot: pagas pods) | Sí | Sí |
| **Identidad** | SA adjunta | Workload Identity | SA del servicio | SA de la función |
| **Cobro** | VM por segundo | Clúster + pods/nodos | vCPU/GiB-s | vCPU/GiB-s |
| **Error típico** | Cuenta por defecto | Sin PDB | Sin máximo de instancias | No idempotente |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Plataforma de microservicios | GKE Autopilot regional | Muchos servicios y políticas comunes |
| API de precios y webhooks internos | Cloud Run privado | Simple, escala a cero |
| Miniaturas de fotos | Cloud Run functions por evento | Corto e idempotente |
| ERP heredado | Compute Engine con MIG de tamaño 1 | Necesita el SO |
| Reporte nocturno | Cloud Run job | Corre y termina |

## Orden recomendado de adopción
1. Imágenes en Artifact Registry con etiquetas inmutables.
2. Cuentas de servicio propias; Workload Identity en GKE.
3. Cloud Run para lo simple; GKE cuando la plataforma lo justifique.
4. Funciones para eventos, siempre idempotentes.
5. VMs solo cuando el SO lo exija.

## Reglas transversales
- Sin llaves: identidad adjunta en todas las plataformas.
- Privado por defecto (ingress interno, nodos privados, sin IP externa).
- Máximos de escalado coherentes con las bases de datos.
- Apagado ordenado y tolerancia a actualizaciones.
- Etiquetas de costo en todo.

## Java en compute: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Compute Engine | Auditor de VMs | `aggregatedList` |
| GKE | Auditor de clústeres | Ubicación `-` para todas |
| Cloud Run | Llamada con ID token, plazo y reintentos seguros | Política pura |
| Functions | Manejador idempotente + auditor de funciones | Lógica reutilizable |

## Cómo se relaciona con otros capítulos
- [Red](../01-red/README.md): subredes, NAT, acceso privado.
- [IAM](../02-iam/README.md): cuentas de servicio y Workload Identity.
- [Secretos](../03-secretos/README.md): montaje de secretos.
- [Ingress](../05-ingress-api/README.md): cómo llega el tráfico.
- [Mensajería](../07-mensajeria/README.md): eventos que disparan trabajo.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
