# Google Cloud · Caso integrado · Runbook de diagnóstico

Son las 21:07 del Cyber y la tienda de ModaLima devuelve 502. Este caso es el **manual de los primeros 5 minutos**: revisar **por capas, de afuera hacia adentro**, con señales objetivas (métricas, logs, salud), detenerse en la **primera capa con problema** y aplicar su runbook, con la mitigación primero (revertir, escalar) y la causa raíz después.

## 1. Qué es

**Analogía:** el protocolo de un paramédico: primero vía aérea, respiración, circulación (en ese orden), estabilizar y luego investigar. No se empieza por la radiografía.

```
 1 Borde        Cloud Armor (¿bloqueos masivos?) · LB: request_count, 5xx por response_code_class
 2 Backends     estado de salud de los NEG / backends · latencia total vs backend
 3 Cómputo      Cloud Run: instancias, arranques en frío, límite de concurrencia · GKE: reinicios, OOM
 4 Dependencias Cloud SQL (conexiones, CPU) · Memorystore · Pub/Sub (backlog, DLQ) · APIs externas
 5 Cambios      último despliegue, último apply, cambios de IAM/red (Audit Logs)
          ▼
 Primera capa con problema → runbook → mitigar (revertir/escalar) → comunicar → causa raíz
```

## 2. Cómo funciona por dentro

| Capa | Señal | Dónde |
|---|---|---|
| Borde | `loadbalancing.googleapis.com/https/request_count` por `response_code_class` | Cloud Monitoring |
| Borde | Solicitudes denegadas por Cloud Armor | Logs del LB (`enforcedSecurityPolicy`) |
| Backends | Salud de backends, `backend_latencies` | LB / Monitoring |
| Cómputo | `run.googleapis.com/request_count`, instancias, `container/restart_count` | Monitoring |
| Dependencias | Conexiones de Cloud SQL, backlog de suscripciones | Monitoring |
| Cambios | Revisiones de Cloud Run, `SetIamPolicy`, `firewalls.*` | Audit Logs |

### Reglas del triage
- De afuera hacia adentro; la primera falla manda.
- «No se pudo comprobar» (permisos, red) es un **hallazgo**, no un OK.
- Mitigar primero: revertir el tráfico de Cloud Run a la revisión anterior es un comando.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Incidente en curso | Este triage |
| Análisis de rendimiento sin incidente | Perfilado y trazas con calma |
| Incidente de seguridad | Su propio runbook (preservar evidencia antes de revertir) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **5xx del LB vs del backend** | 502 suele ser el LB sin backend sano; 500 viene de la app |
| **Tasa de error** | 5xx / total en la ventana |
| **Mitigar** | Quitar el dolor sin saber aún la causa |
| **Revertir** | Volver a la revisión o versión anterior |
| **Causa raíz** | Lo que hay que cambiar para que no vuelva |

## 5. Cómo se usa
1. Panel y alerta de tasa de 5xx: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Triage automático por capas en [Java](uso-en-java.md).
3. Primeros 5 minutos por CLI: [`ejemplos/cli/primeros-5-minutos.sh`](ejemplos/cli/primeros-5-minutos.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Guardia de turno | `roles/monitoring.viewer`, `roles/logging.viewer`, `roles/run.developer` (revertir) | — |
| Servicio de triage | `roles/monitoring.viewer` | — |

- La guardia puede revertir, no crear infraestructura.
- Acceso de emergencia con justificación y registro (*break glass*).

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Revisar por capas en orden | Saltar a la base de datos «porque siempre es la base» |
| Mitigar en minutos | Investigar 40 min con la tienda caída |
| Anotar la línea de tiempo | Confiar en la memoria |
| Tratar «desconocido» como hallazgo | Suponer que está bien |
| Postmortem sin culpables | Buscar culpables |

## 8. Límites, costos y versiones
- **Costo:** Monitoring y Logging según volumen; alertas sin cargo adicional relevante *(verifica)*.
- **Límites** (verifica): retraso de métricas (1–3 min), retención de métricas.
- **Java:** `google-cloud-monitoring` (`MetricServiceClient.listTimeSeries`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
