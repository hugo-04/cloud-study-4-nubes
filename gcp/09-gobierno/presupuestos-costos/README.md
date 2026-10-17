# Google Cloud · Gobierno · Presupuestos y costos

El control de costos tiene tres piezas: **presupuestos** (avisan, no frenan) sobre la cuenta de facturación, **exportación de facturación a BigQuery** (el dato fino para *showback* por label) y **recomendaciones** (Recommender: VMs sobredimensionadas, discos sin uso, compromisos). Para frenar de verdad hay que automatizar la reacción a la notificación del presupuesto.

## 1. Qué es

**Analogía:** la tarjeta de crédito familiar: el banco te manda un SMS al 50 %, 90 % y 100 % del límite que elegiste, pero no bloquea la tarjeta; el extracto detallado (BigQuery) te dice quién gastó en qué.

```
 Cuenta de facturación ModaLima
   ├── Presupuesto "tienda-prod" 3 000 USD/mes (proyecto modalima-tienda-prod)
   │     umbrales 50 % · 90 % · 100 % real · 110 % pronosticado
   │     └─▶ correo a dueños + Pub/Sub "presupuestos" → Cloud Run "reaccion-costos"
   └── Exportación detallada → BigQuery dataset facturacion.gcp_billing_export_resource_v1_*
           └─ SQL por label equipo / centro-costo / servicio
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Cuenta de facturación** | Paga los proyectos vinculados |
| **Presupuesto** | Monto fijo o el gasto del periodo anterior, con filtros (proyectos, servicios, labels) |
| **Umbrales** | Porcentaje sobre gasto real o **pronosticado** |
| **Notificaciones** | Correo a administradores/canales y mensaje a Pub/Sub |
| **Exportación a BigQuery** | Estándar y detallada (por recurso); diaria con retraso de horas *(verifica)* |
| **Créditos** | Descuentos por uso sostenido/compromisos; aparecen como `credits` |
| **Recommender** | Sugerencias de ahorro por recurso |
| **Cuotas** | Límites técnicos que también frenan gastos desbocados |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Enterarse antes de fin de mes | Presupuesto con umbral pronosticado |
| Repartir la factura por equipo | Exportación a BigQuery + labels |
| Frenar un proyecto de pruebas desbocado | Pub/Sub → función que escala a cero o desvincula facturación (con cuidado) |
| Reducir costos estructurales | Recommender + compromisos |
| Límite estricto de gasto | No existe como tal: combina cuotas y automatización |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Pronosticado** | Lo que gastarás al final del mes a este ritmo |
| **Showback** | Mostrar a cada equipo su costo |
| **Créditos** | Descuentos que restan al costo bruto |
| **CUD** | Descuento por compromiso de uso |
| **Costo neto** | `cost + suma(credits)` |

## 5. Cómo se usa
1. Exportación (se activa en la consola), presupuesto con Pub/Sub: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Consulta de costo neto por equipo: [`ejemplos/sql/costo-por-equipo.sql`](ejemplos/sql/costo-por-equipo.sql).
3. Proyección y reacción al mensaje del presupuesto en [Java](uso-en-java.md).
4. CLI: [`ejemplos/cli/costos.sh`](ejemplos/cli/costos.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Finanzas | `roles/billing.admin` o `billing.costsManager` | Lectura del dataset de exportación |
| Equipos | `roles/billing.viewer` (limitado) | Vistas autorizadas por equipo |
| Reacción automática | Permisos mínimos sobre los proyectos que puede detener | Suscriptor del tema |

- Desvincular la facturación **apaga** recursos y puede borrar datos: solo en sandbox.
- Vistas por equipo en BigQuery, no acceso a todo el dataset.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Presupuesto por proyecto/entorno | Uno solo para toda la cuenta |
| Umbral pronosticado | Solo al 100 % real |
| Exportación detallada desde el día uno | Activarla tras el problema (no es retroactiva) |
| Labels obligatorios | Costos sin dueño |
| Automatizar en sandbox | Desvincular facturación en producción |

## 8. Límites, costos y versiones
- **Costo:** presupuestos sin cargo; BigQuery cobra almacenamiento y consultas del dataset *(verifica)*.
- **Límites** (verifica): presupuestos por cuenta, frecuencia de evaluación (varias veces al día), retraso de la exportación.
- **Terraform:** `google_billing_budget`; la exportación a BigQuery se configura en la consola.
- **Java:** `google-cloud-bigquery` para consultar; el mensaje del presupuesto es JSON en Pub/Sub.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
