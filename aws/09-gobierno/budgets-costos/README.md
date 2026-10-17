# AWS · Gobierno · AWS Budgets y Cost Explorer (costos y alertas)

**AWS Budgets te avisa (o actúa) cuando el gasto se acerca a un límite; Cost Explorer te deja preguntar «¿en qué se fue la plata?»; Cost Anomaly Detection te avisa de picos raros; y las etiquetas de asignación de costos dicen de quién es cada sol.** Juntos convierten la factura —que llega una vez al mes y asusta— en una conversación diaria con números.

## 1. Qué es

**Analogía:** el **tablero de gastos de la casa**. El *presupuesto mensual* (Budgets) con una luz amarilla al 80 % proyectado; el *estado de cuenta por categorías* (Cost Explorer); el aviso del banco por *«compra inusual»* (Anomaly Detection); y la *etiqueta con el nombre de quién hizo la compra* (etiquetas de asignación de costos). Nada de esto **detiene** el gasto por sí solo: informa, y con las acciones de presupuesto puede aplicar un freno que tú definiste.

```
 Uso de los servicios ──► Facturación (datos con retraso de horas)
                              │
     ┌────────────────────────┼─────────────────────────────┬───────────────────────┐
     ▼                        ▼                             ▼                       ▼
  Budgets                Cost Explorer              Cost Anomaly Detection     Data Exports (CUR 2.0)
  límite + avisos        UI y API: agrupar por      monitores + suscripciones  archivos Parquet en S3
  (real / pronóstico)    servicio, cuenta, etiqueta  (SNS / correo)             ──► Athena
  + acciones             y tipo de uso
```

## 2. Cómo funciona por dentro

| Pieza | Qué hace |
|---|---|
| **Budgets: tipos** | Costo, uso, utilización y cobertura de Reservas y de Savings Plans. El más usado es el de **costo** (mensual, trimestral, anual) |
| **Filtros del presupuesto** | Por servicio, cuenta, región, **etiqueta** (`TagKeyValue`: `user:equipo$pagos`), categoría de costos… Un presupuesto por equipo o producto |
| **Avisos** | Umbral en % o monto sobre el gasto **real** (`ACTUAL`) o **pronosticado** (`FORECASTED`); destinatarios por correo, tópico SNS o chat (AWS Chatbot) |
| **Acciones de presupuesto** | Al cruzar un umbral: aplicar una política IAM o una SCP, o ejecutar un documento de SSM (por ejemplo, detener instancias). Con aprobación manual o automática |
| **Pronóstico de Budgets** | Estimación del cierre del mes; necesita historial previo de uso *(verifica cuántas semanas)* |
| **Cost Explorer** | Consola y **API** (`GetCostAndUsage`, `GetCostForecast`, `GetAnomalies`…). Granularidad mensual, diaria u horaria (esta última, optativa) |
| **Etiquetas de asignación de costos** | Una etiqueta de recurso solo aparece en costos **cuando se activa en Facturación**; desde ese momento (con posibilidad de rellenar hacia atrás *(verifica)*) |
| **Categorías de costos** | Reglas que agrupan costos en nombres de negocio («tienda-online», «compartido») |
| **Cost Anomaly Detection** | **Monitores** (por servicio, cuenta, etiqueta o categoría) que aprenden el patrón normal; **suscripciones** que avisan si el impacto supera un umbral, de inmediato (SNS) o en resumen diario/semanal (correo) |
| **Data Exports / CUR 2.0** | Tabla detallada de cada línea de uso en S3 (Parquet) para consultar con Athena: el nivel más fino |

Dos relojes que conviene recordar: los datos de costo llegan **con retraso** (Budgets se actualiza varias veces al día; Cost Explorer, al menos una vez cada 24 horas *(verifica)*), y los créditos, impuestos y soporte cambian la lectura del «gasto». Por eso un presupuesto nunca es un freno en tiempo real.

## 3. Para qué sirve y cuándo NO

| ✅ Sirve para | ❌ No sirve para |
|---|---|
| Avisar al 80 % **pronosticado** y al 100 % real de cada equipo | Detener el gasto de inmediato (hay retraso; las acciones no son un interruptor instantáneo) |
| Saber qué servicio, cuenta o etiqueta explica el aumento | Atribuir costos de recursos **sin etiqueta** (aparecen como «sin etiqueta») |
| Detectar picos inusuales sin definir umbrales a mano | Reemplazar la observabilidad técnica (un bucle de errores se ve antes en métricas) |
| Repartir la factura entre equipos (*showback/chargeback*) | Auditar *quién* hizo un cambio (eso es CloudTrail) |
| Análisis fino de líneas de uso con Athena | Facturación en tiempo real por cliente final de tu producto |

## 4. Conceptos clave

| Palabra | Significado simple |
|---|---|
| **Gasto real / pronosticado** | Lo ya consumido / la estimación al cierre del mes |
| **Umbral** | El punto donde se dispara un aviso (80 %, 100 %, 150 %) |
| **Costo sin mezclar (`UnblendedCost`)** | El costo tal como lo ve la cuenta que consume, sin promediar descuentos entre cuentas |
| **Costo amortizado** | Reparte pagos por adelantado (Reservas, Savings Plans) a lo largo del período |
| **Etiqueta de asignación** | Etiqueta de recurso activada en Facturación para que aparezca en los costos |
| **Showback / chargeback** | Mostrar a cada equipo lo que gasta / cobrárselo internamente |
| **Cuenta de administración / miembro** | Las cuentas miembro ven Cost Explorer solo si la cuenta de administración lo permite |
| **Impacto de la anomalía** | Dólares de más frente a lo esperado |
| **Run-rate** | Ritmo diario actual proyectado al resto del mes |

## 5. Cómo se usa
1. **Etiqueta** todo (`equipo`, `entorno`, `producto`) y **actívalas** en Facturación ([`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)). Fuerza el etiquetado con SCP o políticas de etiquetas ([Organizations](../organizations-scp/README.md)).
2. Crea un **presupuesto total** y uno **por equipo**, con avisos: pronosticado 80 % y 100 %, real 100 %. Destinos: correo **y** SNS ([`ejemplos/cli/presupuestos.sh`](ejemplos/cli/presupuestos.sh)).
3. Activa **Cost Anomaly Detection**: un monitor por servicio y suscripciones inmediata (SNS → chat) y diaria (correo).
4. Para entornos de pruebas, añade una **acción de presupuesto** que aplique una política de bloqueo al 100 % (con aprobación manual al principio).
5. Revisa **Cost Explorer** cada semana: agrupa por servicio, luego por tipo de uso; busca el NAT, el almacenamiento huérfano y los registros.
6. Activa **Data Exports** a S3 y consulta con Athena para el detalle ([`ejemplos/sql/cur-athena.sql`](ejemplos/sql/cur-athena.sql)).
7. Automatiza informes y proyecciones desde Java ([uso en Java](uso-en-java.md)).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Equipo de finanzas** | `budgets:*` acotado, `ce:*` de lectura, acceso a Facturación | Consulta de costos y exportaciones |
| **Aplicación de informes** | — | `ce:GetCostAndUsage`, `ce:GetCostForecast`, `budgets:ViewBudget` (ver [`ejemplos/json/politica-costos-lectura.json`](ejemplos/json/politica-costos-lectura.json)) |
| **Servicio Budgets (acciones)** | Rol de ejecución con `iam:AttachRolePolicy`/`DetachRolePolicy` solo sobre el rol objetivo y la política de bloqueo | — |
| **Servicio de alertas de costos** | Publica en el tópico SNS (política del tópico) | — |

- Las acciones `ce:` **no admiten permisos por recurso** (`Resource: "*"`): decide *quién* puede llamar, no *qué*.
- Los costos son información sensible (revelan arquitectura y proveedores): acceso mínimo.
- Una acción de presupuesto es **poder de bloqueo**: rol de ejecución estrecho y aprobación manual al principio.
- La política del tópico SNS debe permitir a `budgets.amazonaws.com` y `costalerts.amazonaws.com` publicar (con `aws:SourceAccount` donde se admite).

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Aviso **pronosticado** además del real | Esperar al 100 % real para enterarte |
| Un presupuesto por equipo/producto con etiqueta activada | Un solo presupuesto global que nadie siente suyo |
| Destinos duales: correo y SNS (para automatizar) | Solo un correo personal |
| Anomaly Detection con suscripción inmediata | Descubrir el pico al cierre del mes |
| Caché de minutos al llamar a la API de Cost Explorer | Llamar a `GetCostAndUsage` por cada petición HTTP (cada solicitud tiene costo) |
| Contar «sin etiqueta» como indicador de calidad | Ignorar la cubeta «sin etiqueta» |
| Acciones de presupuesto con aprobación manual al inicio | Acciones automáticas de bloqueo sobre producción |
| Revisar costos amortizados al evaluar Reservas/Savings Plans | Proyecciones lineales con pagos por adelantado |

## 8. Límites, costos y versiones
- **Costo:** Cost Explorer en consola es gratuito; **cada solicitud a la API se cobra** (≈ 0,01 USD por solicitud paginada *(verifica)*). Budgets: los presupuestos con acciones tienen cuota gratuita y luego costo diario; los demás, según el plan *(verifica)*. Cost Anomaly Detection es gratuito. Data Exports: costo de almacenamiento y consulta en S3/Athena.
- **Límites** *(verifica)*: pocos avisos por presupuesto (alrededor de 5) y pocos destinatarios por aviso; cuota de presupuestos por cuenta; el historial de Cost Explorer es de unos 13 meses (con opción de ampliarlo).
- **Endpoints globales:** Budgets y Cost Explorer se llaman en `us-east-1` aunque tus cargas estén en otra región.
- **Terraform:** `aws_budgets_budget`, `aws_budgets_budget_action`, `aws_ce_cost_allocation_tag`, `aws_ce_cost_category`, `aws_ce_anomaly_monitor`, `aws_ce_anomaly_subscription`, `aws_sns_topic(+policy)`. Validado con `init` + `validate`.
- **Java:** AWS SDK v2 `budgets` y `costexplorer`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
