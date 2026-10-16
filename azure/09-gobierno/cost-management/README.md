# Azure · Gobierno · Cost Management (costos y FinOps)

## 1. Qué es

**Microsoft Cost Management es el conjunto de herramientas de Azure para ver cuánto se gasta, quién lo gasta, avisar cuando se desvía y ayudar a gastar menos.** No frena el gasto por sí mismo: **mide, avisa y exporta**. Frenar es cosa de tu automatización (o de políticas que impiden crear lo caro).

Analogía: **el tablero de un auto**. El velocímetro es el *análisis de costos* (cuánto gastas ahora y en qué), la luz de reserva es el *presupuesto con alertas*, el odómetro por viaje son las *exportaciones* (el historial para analizar fuera), y el copiloto que dice "esto no es normal" es la *detección de anomalías*. Ninguno aprieta el freno: eso lo decides tú.

```
 Uso de recursos ──► Datos de costo (llegan en 8–24 h) ──┬─► Análisis de costos (agrupar por etiqueta, servicio, grupo de recursos…)
   (VM, SQL, Storage…)                                    ├─► Presupuestos ──► Alertas (correo / grupo de acciones ──► Function, Logic App, webhook)
                                                          ├─► Anomalías ──► correo (una vez, al detectar)
                                                          ├─► Exportaciones ──► Storage (CSV / Parquet) ──► BI, FinOps, auditoría
                                                          └─► API de consultas y pronósticos ──► tus propias aplicaciones (Java)
          ▲
   Etiquetas (owner, env, cost-center) + herencia de etiquetas  → son lo que permite repartir el costo entre equipos
```

---

## 2. Cómo funciona por dentro

### 2.1 Los datos y su retraso
- Los costos **no son instantáneos**: suelen estar disponibles **8–24 horas** después del uso. Un presupuesto o una alerta nunca reaccionan "en el momento".
- Una **suscripción nueva** puede tardar hasta **48 horas** en tener Cost Management disponible.
- Todas las suscripciones dentro del alcance de un presupuesto deben usar **una sola moneda**; con varias monedas la evaluación no está soportada y se pueden perder alertas.
- Hay dos lecturas del costo: **real (*actual*)** —lo facturable— y **amortizado (*amortized*)** —reparte compras de reservas y planes de ahorro a lo largo del tiempo—. **Los presupuestos se evalúan contra el costo real**, no el amortizado.

### 2.2 Alcances (dónde se consulta y se aplica)
| Familia | Alcances |
|---|---|
| **Azure RBAC** | Grupo de administración, suscripción, grupo de recursos |
| **Enterprise Agreement (EA)** | Cuenta de facturación, departamento, cuenta de inscripción |
| **Microsoft Customer Agreement (MCA)** | Cuenta de facturación, perfil de facturación, sección de factura, cliente |
| **Acuerdos individuales (pago por uso)** | Cuenta de facturación |

> Qué funciones tienes **depende del tipo de contrato** (EA, MCA, pago por uso). En este documento los ejemplos de ModaLima usan el alcance de **suscripción** y de **grupo de recursos**, que existen en todos. *Verifica en tu contrato qué más aplica.*

### 2.3 Análisis de costos (*Cost analysis*)
Es la vista interactiva: acumulado del mes, por día, **agrupado por** servicio, ubicación, grupo de recursos o **etiqueta**, con **filtros**. Es la herramienta del día a día para responder "¿quién gastó esto?". Se pueden guardar **vistas** y programar su envío por correo.

### 2.4 Presupuestos (*Budgets*)
| Aspecto | Detalle |
|---|---|
| **Qué hacen** | Siguen el gasto contra un monto y **notifican** al alcanzar umbrales. **No afectan a los recursos ni detienen el consumo** |
| **Alcances** | Grupo de administración, suscripción y grupo de recursos (más los de facturación de EA/MCA) |
| **Periodo** | Mensual, trimestral o anual (calendario). En pago por uso, MSDN y Visual Studio, también mes/trimestre/año **de facturación**. Un monto trimestral se reparte en tres meses y uno anual en doce |
| **Reinicio** | Se reinician solos al terminar el periodo con el mismo monto (si la fecha de fin está en el futuro). Para montos distintos en el tiempo, presupuestos distintos. Los vencidos se borran solos |
| **Umbrales** | Entre **1 y 5** por presupuesto, de **0,01 % a 1000 %**, de tipo **real** (gasto acumulado) o **pronosticado** (*forecast*, el gasto proyectado) |
| **Destinatarios** | Entre **1 y 5** correos por presupuesto; los destinatarios por rol solo se configuran por API |
| **Grupos de acciones** | **Solo en alcance de suscripción y de grupo de recursos.** Disparan Azure Functions, webhooks, Logic Apps, notificaciones push… |
| **Evaluación** | **Cada 24 horas**; el correo suele salir dentro de la hora siguiente a una evaluación que cumple el umbral |
| **Filtros** | Por grupo de recursos, servicio, etiqueta, etc. Para limitar a consumo propio de Azure: *Publisher Type = Azure* y *Charge Type = Usage*. Las compras de reservas se incluyen en la evaluación |
| **Permisos** | Leer: *Reader*/*Cost Management Reader*. Crear o modificar: *Contributor*/*Cost Management Contributor* (en suscripción, *Owner* puede crear, modificar y borrar) |

> **Trampa:** el comando `az consumption budget create` crea el presupuesto **sin notificaciones** (no tiene parámetros de umbral ni de correos): un presupuesto sin alertas no avisa de nada. Para crear con umbrales usa REST, Terraform, Bicep o el SDK. Lo mismo ocurre con los presupuestos creados con PowerShell, que **no envían notificaciones** según la documentación.

### 2.5 Alertas de Cost Management
| Tipo | Qué hace | Notas |
|---|---|---|
| **Presupuesto** | Aviso al llegar a un umbral | Se generan solas; aparecen en *Cost alerts* y llegan por correo |
| **Crédito** | Aviso al consumir el prepago (90 % y 100 %) | Solo EA |
| **Cuota de departamento** | Aviso al alcanzar un porcentaje de la cuota | Solo EA |
| **Anomalía** | Aviso cuando el gasto diario sale de lo esperable | Ver §2.6 |

Estado de una alerta: **Activa** (sigue vigente) o **Descartada** (alguien la marcó como irrelevante; se puede reactivar).

### 2.6 Detección de anomalías
- Corre **por suscripción**, una vez al día: compara el uso del día con un pronóstico basado en los **últimos 60 días** (que contempla patrones recurrentes, como picos semanales). El modelo de series de tiempo se entrena con 60 días de historial.
- La detección se ejecuta **36 horas después** de terminar el día (UTC), para tener datos completos. Un alta nueva puede tardar hasta 24 horas en mostrar estado.
- **Alerta de anomalía:** solo en **alcance de suscripción**, hasta **cinco por suscripción**, solo en la nube pública (no en gobierno ni nubes soberanas). El correo resume los cambios por grupo de recursos y se envía **una sola vez**, al detectar.
- Se crea con el portal o con la API de acciones programadas (tipo `InsightAlert`) o con Terraform (`azurerm_cost_anomaly_alert`). El creador debe **mantener el rol Reader**: la alerta usa su acceso actual al enviar.

### 2.7 Exportaciones (*Exports*)
| Aspecto | Detalle |
|---|---|
| **Qué exportan** | Costo y uso: **real**, **amortizado**, **FOCUS** (formato abierto de FinOps), **solo uso** (ya no se crean nuevos); **hoja de precios**; **detalles, recomendaciones y transacciones de reservas** |
| **Alcances** | Suscripción, grupo de recursos, grupo de administración (solo EA, solo uso, hasta 3 000 suscripciones, sin FOCUS), departamento, inscripción, cuenta de facturación (socios) |
| **Frecuencia** | Única, diaria (mes hasta la fecha), mensual (mes anterior) y, para costos, mensual del último mes de facturación. **Se ejecutan en UTC** |
| **Destino** | Cuenta de almacenamiento (blob o archivos). Ruta: `contenedor/directorio/nombre/[AAAAMMDD-AAAAMMDD]/[RunID]/`. No uses un contenedor destino de replicación de objetos |
| **Seguridad del destino** | Se crea una **identidad administrada** del export con *Storage Blob Data Contributor* en el contenedor; con *firewall* hay que permitir **servicios de confianza de Azure** (se hace solo con una cuenta existente) y la cuenta debe estar en el **mismo tenant**. API `2023-08-01` o posterior para cuentas con firewall |
| **Formatos** | CSV (sin compresión o gzip) y **Parquet** (sin compresión o snappy) para costo y uso |
| **Particionado** | Siempre activo; archivos de menos de 1 GB sin comprimir. **Lee el `manifest.json`** de cada ejecución para reconstruir los datos: no escribas nombres de archivo a mano |
| **Tiempos** | Los datos suelen estar en menos de 4 h tras iniciar la ejecución; el proceso puede tardar hasta 24 h. Los días 1 a 5 de cada mes los costos se exportan **dos veces** (la segunda regenera el mes anterior para que coincida con la factura) |
| **Histórico** | Rellenar meses pasados (hasta 13 en el portal; más por API) |

### 2.8 Etiquetas y reparto de costos
Sin etiquetas no se puede repartir el gasto por equipo. Tres piezas:

1. **Etiquetas obligatorias** (`owner`, `env`, `cost-center`) **impuestas con Azure Policy** ([capítulo de Policy](../azure-policy/README.md)): auditar, luego exigir, y `Modify` para heredar `env`.
2. **Herencia de etiquetas de Cost Management** (EA, MCA y socios con plan de Azure): aplica las etiquetas de la suscripción y del grupo de recursos a los **registros de uso** de los recursos hijos (no a los recursos). Se activa en la cuenta de facturación (EA), el perfil (MCA) o la suscripción. Se refleja en las 8–24 h siguientes, y afecta a los datos **del mes en curso**. Una etiqueta del propio recurso manda, salvo que elijas lo contrario. Las compras y los recursos sin uso a nivel de suscripción no reciben las etiquetas.
3. **Reglas de asignación de costos** (*cost allocation rules*): para repartir el costo de servicios compartidos (el *hub* de red, el *workspace* central) entre los equipos que los usan. *Consulta el artículo "Allocate costs" para los métodos de reparto.*

### 2.9 Automatizar la respuesta
Un presupuesto puede **disparar acciones**, pero tú las programas:

```
Presupuesto (suscripción o grupo de recursos)
   └─ umbral 100 % (real) ──► Grupo de acciones ──► Azure Function / Logic App / webhook
                                                     └─ apaga las VM de desarrollo con etiqueta auto-apagar=si
                                                     └─ publica en el canal del equipo
                                                     └─ abre un ticket
```
Reglas: acciones **reversibles** (apagar, no borrar), solo sobre recursos etiquetados para ello, y el umbral de acción **después** de los avisos humanos (50 % y 80 % avisan; 100 % actúa; 120 % pronosticado avisa antes).

### 2.10 Dónde buscar ahorros (FinOps)
| Palanca | Idea |
|---|---|
| **Dimensionar** (*right-sizing*) | Máquinas, bases de datos y SKU sobredimensionados; Azure Advisor lo recomienda |
| **Apagar lo que no se usa** | Entornos de desarrollo fuera de horario; recursos huérfanos (discos, IP, NIC sin dueño) |
| **Compromisos** | Reservas y planes de ahorro para cargas estables |
| **Licencias** | Beneficio híbrido de Azure donde aplica |
| **Retención y niveles** | Datos fríos en niveles baratos; retención de logs y de diagnósticos ajustada (Log Analytics) |
| **Región y SKU** | Políticas que limitan SKU y regiones en Sandbox |
| **Arquitectura** | Autoescalado, serverless con consumo, colas en lugar de capacidad ociosa |

Ciclo FinOps: **informar** (ver y repartir) → **optimizar** (actuar sobre las palancas) → **operar** (gobernar: presupuestos, políticas, revisiones mensuales).

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Ver y repartir** el gasto por equipo, entorno y proyecto (showback/chargeback).
- **Avisar a tiempo**: presupuestos reales y pronosticados, anomalías diarias.
- **Exportar** el detalle para BI, auditoría y FinOps.
- **Consultar por API** el costo del mes y su pronóstico desde tus propios servicios.
- **Gobernar el gasto de Sandbox**: presupuesto + acción de apagado + políticas de SKU.

| NO lo uses para | Alternativa |
|---|---|
| **Frenar** el gasto automáticamente | Funciones/Logic Apps disparadas por el grupo de acciones; políticas que impiden crear lo caro |
| Decisiones **en tiempo real** (los datos tardan 8–24 h) | Métricas de uso (Azure Monitor) para reaccionar al instante |
| Cuota técnica (límites de recursos) | Cuotas y límites de suscripción |
| Reemplazar el **etiquetado** | Azure Policy + herencia de etiquetas |
| Prever **todo** el gasto con exactitud | Es una estimación; revisa tendencias, no centavos |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Costo real (*actual*)** | Lo facturable en el periodo | Base de los presupuestos |
| **Costo amortizado** | Compras de reservas repartidas en el tiempo | Para comparar equipos |
| **Presupuesto** | Monto + periodo + umbrales + destinatarios | 2 000 USD/mes en Sandbox |
| **Umbral real / pronosticado** | % del presupuesto gastado / proyectado | 80 % real, 100 % pronosticado |
| **Grupo de acciones** | Qué hacer al alertar (correo, Function, webhook…) | `ag-finops` |
| **Anomalía** | Gasto diario fuera de lo esperado por 60 días de historia | Salto de un servicio |
| **Exportación** | Envío programado de datos de costo a Storage | `export-modalima-diario` |
| **FOCUS** | Formato abierto de FinOps para costos | Datos comparables entre herramientas |
| **Etiqueta (*tag*)** | Par clave/valor en el recurso | `cost-center=cc-1200` |
| **Herencia de etiquetas** | Etiquetas de suscripción/grupo en los registros de uso | `env` heredada |
| **Regla de asignación** | Reparte costo compartido entre equipos | Hub de red |
| **Showback / Chargeback** | Mostrar / cobrar el costo a cada equipo | Informe mensual |
| **FinOps** | Disciplina de gestionar costos en la nube | Informar-optimizar-operar |
| **Alcance (*scope*)** | Nivel de la consulta o presupuesto | `/subscriptions/{id}` |

---

## 5. Cómo se usa

1. **Define quién es dueño de qué:** etiquetas `owner`, `env`, `cost-center` obligatorias (Policy: auditar → exigir) y herencia de etiquetas activada.
2. **Crea presupuestos por alcance con código** ([Terraform](ejemplos/terraform/main.tf)): uno por suscripción de equipo, uno por Sandbox, y uno **pronosticado** que avise antes.
   - Umbrales típicos: 50 % y 80 % real (aviso), 100 % real (acción), 110 % pronosticado (aviso temprano).
3. **Conecta un grupo de acciones** a los presupuestos de Sandbox y Dev: apagar lo etiquetado, avisar al canal.
4. **Activa alertas de anomalía** en las suscripciones de producción (hasta cinco por suscripción) a un buzón del equipo.
5. **Programa una exportación diaria** (real o FOCUS, Parquet) a una cuenta de almacenamiento central para BI y auditoría.
6. **Reúnete cada mes:** análisis por etiqueta, recursos sin etiqueta, recomendaciones de Advisor, decisiones de ahorro.
7. **Para aplicaciones propias:** consulta el costo y el pronóstico por API (ver [uso en Java](uso-en-java.md)); cachea el resultado.
8. **Revisa lo que no tiene dueño:** consulta de recursos sin etiqueta ([KQL](ejemplos/kql/kql-costos.md)).

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/costos.sh) · [KQL](ejemplos/kql/kql-costos.md) · [consultas JSON](ejemplos/json/).

---

## 6. Seguridad

- **Los datos de costo son sensibles** (revelan arquitectura, tamaño y proveedores). Da *Reader* de costos solo a quien lo necesita; usa *Cost Management Reader* en lugar de *Reader* amplio.
- **Exportaciones:** el almacenamiento destino sin acceso público, con la identidad administrada del export, firewall con servicios de confianza y datos con retención definida.
- **Correos de alertas** a buzones de equipo, no a personas (rotan).
- **Alertas de anomalía:** quien las crea debe conservar el rol *Reader*; si se va, dejan de enviarse. Créalas con una identidad de servicio si tu política lo exige.
- **Respuestas automáticas** (apagar recursos): identidad con el mínimo permiso (solo apagar etiquetados), acciones reversibles y registro de cada ejecución.
- **Presupuestos y políticas por código** y con revisión: cambiar un umbral es cambiar el gobierno del gasto.

### IAM de este servicio

| Plano | Quién | Qué hace | Rol/permiso mínimo |
|---|---|---|---|
| **Control** | Equipos de aplicación | Ver el costo de su suscripción o grupo | *Cost Management Reader* en su alcance |
| **Control** | FinOps / plataforma | Crear presupuestos, vistas, alertas, exportaciones | *Cost Management Contributor* en el alcance (o *Contributor*) |
| **Control** | Finanzas | Ver costos de la organización | *Cost Management Reader* en el grupo de administración / cuenta de facturación |
| **Control** | Pipeline de gobierno | Crear presupuestos y exportaciones como código | Identidad federada con *Cost Management Contributor* en el alcance |
| **Control** | Exportación | Escribir en el almacenamiento | Identidad administrada del export con *Storage Blob Data Contributor* en el contenedor |
| **Control** | Quien crea una alerta de anomalía | Mantenerla activa | *Cost Management Contributor* para crear; *Reader* para conservarla |
| **Control** | Función de respuesta | Apagar recursos etiquetados | Rol personalizado: solo `…/virtualMachines/deallocate/action` y lectura, en el grupo de Sandbox |
| **Datos** | Aplicación Java | Consultar costos y pronósticos por API | *Cost Management Reader* en el alcance (identidad administrada) |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- **Etiquetas obligatorias** + herencia + presupuestos **por equipo y por entorno**.
- Un presupuesto **pronosticado** para enterarte *antes* de pasarte.
- **Umbrales escalonados**: avisar (50 %, 80 %), actuar (100 %), con acciones reversibles.
- **Anomalías** activas en producción; **exportación diaria** a un almacenamiento central.
- **Revisión mensual** de costos con los dueños de cada etiqueta.
- Todo **como código**; el presupuesto de cada suscripción nueva se crea en el alta.
- Cachear los resultados de la API: los datos cambian cada pocas horas.

**Qué NO hacer**
- Creer que un presupuesto **detiene** el gasto.
- Crear presupuestos con `az consumption budget create` esperando alertas (no define umbrales).
- Presupuestos de grupo de administración esperando **grupos de acciones** (solo suscripción y grupo de recursos).
- Mezclar monedas en un mismo presupuesto.
- Poner **borrar** como acción automática: apaga, no borres.
- Alertas a personas individuales.
- Decidir con datos del mismo día: llegan con 8–24 horas de retraso.
- Dejar recursos **sin etiqueta**: son el gasto sin dueño.

---

## 8. Límites, costos y versiones
- **Costo:** las funciones de Cost Management para recursos de Azure no tienen cargo adicional (*verifica según tu contrato*). Pagas el **almacenamiento** de las exportaciones y lo que despliegues para responder (Functions, Logic Apps, Log Analytics).
- **Límites clave:** 5 umbrales y 5 correos por presupuesto; 5 alertas de anomalía por suscripción; hasta 3 000 suscripciones en una exportación de grupo de administración (solo EA); particiones de menos de 1 GB; 10 exportaciones por lote de creación. *Verifica los vigentes.*
- **Latencia:** datos en 8–24 h; evaluación de presupuestos cada 24 h; anomalías 36 h después de terminar el día; suscripciones nuevas hasta 48 h.
- **API:** presupuestos en `Microsoft.Consumption/budgets`; consultas, pronósticos, exportaciones y acciones programadas en `Microsoft.CostManagement`.
- **SDK de Java:** `azure-resourcemanager-consumption` 1.0.0 (presupuestos) y `azure-resourcemanager-costmanagement` 1.0.0 (consultas, pronósticos, exportaciones, alertas, acciones programadas).
- **Terraform:** `azurerm_consumption_budget_subscription` / `_resource_group` / `_management_group`, `azurerm_cost_anomaly_alert`, `azurerm_subscription_cost_management_export` (y sus variantes de grupo de recursos y cuenta de facturación), `azurerm_cost_management_scheduled_action` y `azurerm_subscription_cost_management_view`.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
