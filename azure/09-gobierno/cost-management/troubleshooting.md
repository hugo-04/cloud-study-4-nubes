# Azure · Cost Management · Troubleshooting

Sigue el flujo: **¿es un problema de datos (retraso, moneda, alcance), de permisos, de configuración (umbrales, destinatarios, grupo de acciones) o de entrega (correo, almacenamiento)? → ¿qué alcance y qué tipo de contrato?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| No veo costos en una suscripción nueva | Hasta 48 h para que Cost Management esté disponible | Antigüedad de la suscripción | Esperar |
| Los costos de ayer no aparecen | Los datos llegan en 8–24 h | Hora de la última actualización en el análisis | Esperar; para tiempo real usa métricas de Azure Monitor |
| El presupuesto existe pero nunca avisa | Se creó sin notificaciones (p. ej., con `az consumption budget create`) | `az consumption budget show` → `notifications` vacío | Crear con REST/Terraform con umbrales y correos |
| No llegó el correo de umbral | Evaluación cada 24 h; correo dentro de la hora siguiente; destinatario mal escrito; filtro de correo | Fecha de la última evaluación; alertas en *Cost alerts* | Revisar destinatarios (máx. 5), bandeja de spam y reglas de correo (`microsoft-noreply@microsoft.com`) |
| Alerta pronosticada nunca salta | El pronóstico no supera el umbral; poco historial | Pronóstico en el análisis de costos | Ajustar el umbral; esperar historial |
| El grupo de acciones no se dispara | Alcance de grupo de administración (no admite grupos de acciones) o el grupo no está en la notificación | Alcance del presupuesto; `contactGroups` | Mover el presupuesto a suscripción/grupo de recursos |
| La Function de apagado no corre | Webhook mal configurado, sin permisos o con el esquema común desactivado | Historial del grupo de acciones; registros de la Function | Probar el grupo de acciones; revisar la identidad de la Function |
| El presupuesto con filtro por etiqueta muestra menos | Etiquetas inconsistentes (`Prod`/`prod`) o sin herencia | Consulta [A3](ejemplos/kql/kql-costos.md) | Política de valores permitidos; herencia de etiquetas |
| Las etiquetas heredadas no aparecen | Tarda hasta 24 h; el contrato no lo admite; son compras o recursos sin uso | Configuración de herencia del alcance | Esperar; verificar tipo de contrato y alcance |
| El presupuesto parece contar de menos/más | Se evalúa el costo **real**, no el amortizado; cargos de reservas incluidos | Tipo de costo en el análisis | Comparar con el mismo tipo de costo |
| Alertas perdidas con varias monedas | Un presupuesto no admite monedas distintas en su alcance | Moneda de cada suscripción | Un presupuesto por moneda |
| No puedo crear presupuestos | Falta *Contributor*/*Cost Management Contributor* | Roles en el alcance | Conceder el rol (EA: requiere permisos de contribuidor) |
| No puedo ver costos | Falta *Reader*/*Cost Management Reader* o la política de ver cargos del contrato | Roles; configuración del contrato | Conceder el rol; revisar "ver cargos" (EA indirecto/MCA con socio) |
| No tengo funciones de EA (crédito, cuota de departamento) | Contrato distinto de EA | Tipo de contrato | Esas alertas solo existen en EA |
| La alerta de anomalías no existe en mi suscripción | Solo nube pública y alcance de suscripción; hasta 5 por suscripción | Nube y cantidad de alertas | Usar nube pública; editar una alerta existente si llegaste a 5 |
| La alerta de anomalías dejó de llegar | El creador perdió el rol *Reader* o la alerta expiró | Roles del creador; vigencia | Recrearla con una identidad de servicio / buzón de equipo |
| La exportación no entrega datos | Permisos del destino, firewall o tenant distinto | Ejecuciones del export; red de la cuenta | Servicios de confianza permitidos, mismo tenant, rol *Storage Blob Data Contributor* de la identidad del export |
| La exportación cambió de ruta o de archivos | Particionado (siempre activo) o sobrescritura distinta | `manifest.json` de la ejecución | Leer siempre el manifiesto |
| Faltan datos del mes anterior en la exportación | La exportación se creó los días 1–5 (no genera el mes previo) | Fecha de creación | Rellenar con "Exportar fechas seleccionadas" / API *Execute* |
| Totales distintos entre exportación y análisis | Decimales truncados en BI o tipos de columna | Tipo de la columna de costo | Convertir a número decimal |
| La API de costos devuelve 429 | Límite de solicitudes | Cabeceras `Retry-After` | Cachear; reintentar con espera; reducir la frecuencia |
| La consulta de la API tarda o se corta | Demasiados datos en un alcance amplio | Tamaño del resultado y `nextLink` | Agrupar menos; acotar el periodo; seguir `nextLink` |
| Terraform quiere recrear el presupuesto | Cambió `time_period.start_date` o el nombre | `terraform plan` | Mantener fecha de inicio y nombre estables |
| Error de fecha de inicio | El presupuesto debe empezar el día 1 de un mes (UTC) | Valor de `start_date` | Usar el primer día de mes |

## Comandos útiles
```bash
# Presupuestos del alcance y detalle (¿tienen notificaciones?)
az consumption budget list -o table
az rest --method get --url "https://management.azure.com/subscriptions/<ID>/providers/Microsoft.Consumption/budgets?api-version=2023-05-01" \
  --query "value[].{nombre:name, monto:properties.amount, gastoActual:properties.currentSpend.amount, avisos:length(keys(properties.notifications))}" -o table

# Alertas de costo activas
az rest --method get --url "https://management.azure.com/subscriptions/<ID>/providers/Microsoft.CostManagement/alerts?api-version=2023-11-01" \
  --query "value[].{tipo:properties.definition.type, estado:properties.status, fecha:properties.creationTime}" -o table

# Ejecuciones de una exportación
az rest --method get --url "https://management.azure.com/subscriptions/<ID>/providers/Microsoft.CostManagement/exports/export-modalima-diario/runHistory?api-version=2023-08-01"

# Recursos sin dueño
az graph query -q "resources | where isempty(tags['owner']) | summarize count() by type | order by count_ desc | take 20" -o table
```

## Secuencia recomendada
1. **Datos:** ¿hay retraso esperable (8–24 h, 48 h en suscripciones nuevas)? ¿una sola moneda? ¿el mismo tipo de costo (real/amortizado)?
2. **Alcance y contrato:** ¿qué admite este alcance (grupos de acciones, anomalías) y este contrato (EA/MCA/pago por uso)?
3. **Configuración:** umbrales (máx. 5), destinatarios (máx. 5), tipo (real/pronosticado), grupo de acciones.
4. **Entrega:** correo (spam, remitente), almacenamiento (firewall, tenant, rol), Function (webhook, identidad).
5. **Etiquetas:** valores consistentes, herencia activa, cobertura (consultas A1–A3).
6. **Permisos:** quién creó la alerta y si sigue con *Reader*; roles de lectura/escritura en el alcance.
7. **IaC:** fecha de inicio estable, nombre estable, día 1 del mes.
8. **API:** `Retry-After`, `nextLink`, caché.
