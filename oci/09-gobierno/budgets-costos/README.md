# Oracle OCI · Gobierno · Presupuestos y costos

Cómo saber cuánto gastas, en qué y quién, y enterarte **antes** de pasarte: **análisis de costos** y **reportes de uso** para mirar, **presupuestos** con **alertas** (reales y proyectadas) para reaccionar, y la **Usage API** para automatizar.

## 1. Qué es

**Analogía:** la app del banco con presupuesto mensual por categoría. Ves en qué se fue la plata (análisis), defines «máximo 500 en comida» (presupuesto) y te avisa al 80 % o si, al ritmo que vas, te pasarás (alerta proyectada).

```
 Uso medido por recurso ──► Usage API / Cost Analysis / reportes de costo (CSV en Object Storage)
                               agrupar por servicio, compartimento, etiqueta (centro_costo)
 Presupuesto "modalima-prod" (compartimento o etiqueta, 5.000 USD/mes)
   ├─ alerta REAL      al 80 %   ──► correo a finanzas y plataforma
   └─ alerta PROYECTADA al 100 % ──► correo + tema de Notifications
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Cost Analysis** | Exploración en consola por servicio, compartimento, etiqueta y tiempo |
| **Reportes de costo y uso** | Archivos detallados generados en un bucket de Oracle que puedes leer *(verifica)* |
| **Usage API** | `RequestSummarizedUsages`: costo o uso agregado por día/mes y agrupado |
| **Presupuesto** | Monto por periodo sobre un compartimento o una etiqueta de costo |
| **Regla de alerta** | `ACTUAL` o `FORECAST`, umbral en % o monto, destinatarios o tema |
| **Etiquetas de costo** | Etiquetas definidas marcadas para filtrar costos (ver [compartimentos y etiquetas](../compartimentos-etiquetas/README.md)) |

### Tiempos
- Los datos de costo llegan con **retraso** (horas) *(verifica)*: los presupuestos no son un freno en tiempo real.
- Un presupuesto **avisa**, no detiene recursos: para topes duros usa **cuotas**.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Avisar si prod va a superar el mes | Presupuesto con alerta proyectada |
| Saber cuánto cuesta el producto «pagos» | Etiqueta de costo + Cost Analysis/Usage API |
| Reporte semanal automático por equipo | Usage API desde un job |
| Impedir que no-prod gaste más | **Cuotas** (el presupuesto solo avisa) |
| Optimizar recursos ociosos | Cloud Advisor *(verifica)* + revisión |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Proyección** | Estimar el cierre de mes con el ritmo actual |
| **Showback** | Mostrar a cada equipo su gasto |
| **Chargeback** | Cobrarle a cada equipo su gasto |
| **Costo no etiquetado** | Gasto que no se puede asignar |
| **Compromiso (Universal Credits)** | Contrato prepago con consumo mínimo *(verifica)* |

## 5. Cómo se usa
1. Presupuestos por compartimento y por etiqueta con alertas real y proyectada: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Proyección propia por servicio con la Usage API: [uso en Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/costos.sh`](ejemplos/cli/costos.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Finanzas/plataforma | `manage usage-budgets` | — |
| Reportes automáticos | `read usage-reports` (Usage API) | Lectura de reportes de costo |
| Equipos | `read usage-budgets` de su compartimento | — |

- Los reportes de costo revelan la arquitectura: acceso restringido.
- Alertas a listas de distribución, no a personas individuales.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Presupuesto por compartimento de producto | Un único presupuesto global |
| Alertas proyectadas además de reales | Enterarte el día 30 |
| Etiquetas de costo obligatorias | Tener 30 % de gasto sin dueño |
| Cuotas donde haga falta frenar | Creer que el presupuesto detiene recursos |
| Revisión mensual de costos con cada equipo | Que solo finanzas mire la factura |

## 8. Límites, costos y versiones
- **Costo:** presupuestos y Usage API sin cargo *(verifica)*.
- **Límites** (verifica): presupuestos por tenancy, reglas por presupuesto, granularidad de datos, retraso de datos.
- **Terraform:** `oci_budget_budget`, `oci_budget_alert_rule`.
- **SDK:** `UsageapiClient`, `BudgetClient` (`oci-java-sdk-usageapi`, `oci-java-sdk-budget`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
