# Azure · Cost Management · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · La factura que nadie esperaba
- **Problema:** al cerrar el mes, el gasto de la tienda en línea era el triple de lo normal; nadie lo supo hasta que llegó la factura.
- **Causa:** no había presupuestos ni alertas; el análisis de costos se miraba "cuando alguien se acordaba".
- **Solución:** un presupuesto mensual por suscripción con avisos al 50 % y 80 % reales y un aviso **pronosticado** al 110 %, más una alerta de anomalías. Todo creado con código ([Terraform](ejemplos/terraform/main.tf)) en el alta de cada suscripción.
- **Lección:** el aviso que importa es el que llega **a mitad de mes**, no el de la factura. El umbral pronosticado es el más útil.

## Caso 2 · El presupuesto que nunca avisó
- **Problema:** se había "creado un presupuesto" para Sandbox, pero el gasto se duplicó sin ningún correo.
- **Causa:** se creó con `az consumption budget create`, que **no permite definir umbrales ni destinatarios**: el presupuesto existía, pero sin notificaciones.
- **Solución:** los presupuestos pasan a crearse solo desde Terraform/REST, y una revisión mensual (consulta con la API) comprueba que **todo presupuesto tenga al menos una notificación**.
- **Lección:** un presupuesto sin notificaciones es un número decorativo. Verifica que alerte, no que exista.

## Caso 3 · "Pensé que el presupuesto lo frenaba"
- **Problema:** un laboratorio de Sandbox superó seis veces su presupuesto en un fin de semana.
- **Causa:** los presupuestos **no detienen el consumo**; solo avisan, y el correo llegó el lunes.
- **Solución:** al 100 % real, el grupo de acciones llama a una Function que **desasigna** (apaga) las máquinas con la etiqueta `auto-apagar=si` de ese grupo; los avisos al 50 % y 80 % van antes. La acción es **reversible** (apagar, no borrar) y solo aplica a lo etiquetado.
- **Lección:** el freno lo construyes tú. Hazlo reversible, acotado y con aviso previo.

## Caso 4 · El 30 % de los recursos sin dueño
- **Problema:** el informe por equipo no cuadraba: casi un tercio del gasto aparecía como "sin etiqueta".
- **Solución:** Azure Policy: un mes en `Audit`, luego `Deny` en Dev y Prod ([Azure Policy](../azure-policy/README.md)); herencia de etiquetas de Cost Management para que los registros de uso hereden las de la suscripción y el grupo; consulta de recursos sin etiqueta ([A1](ejemplos/kql/kql-costos.md)) en la revisión mensual.
- **Lección:** el reparto de costos es tan bueno como el etiquetado. Imponlo con política, no con correos.

## Caso 5 · `prod`, `Prod` y `produccion`
- **Problema:** el presupuesto filtrado por `env=prod` mostraba la mitad del gasto real.
- **Causa:** los equipos escribían la etiqueta de tres maneras; el filtro solo veía una.
- **Solución:** política con **valores permitidos** (`prod`, `staging`, `dev`, `sandbox`), consulta de valores fuera de lo permitido ([A3](ejemplos/kql/kql-costos.md)) y corrección con `Modify` de lo existente.
- **Lección:** una etiqueta libre es una etiqueta rota. Limita los valores.

## Caso 6 · El presupuesto de empresa sin acciones
- **Problema:** se creó un presupuesto sobre el grupo de administración raíz de ModaLima con un grupo de acciones; la acción nunca se disparó.
- **Causa:** los **grupos de acciones solo funcionan en alcance de suscripción y de grupo de recursos**; en un grupo de administración solo hay correo.
- **Solución:** el presupuesto de empresa quedó como aviso a finanzas (correo); las acciones automáticas viven en presupuestos por suscripción de Sandbox y Dev.
- **Lección:** conoce qué admite cada alcance antes de diseñar la respuesta.

## Caso 7 · La anomalía de la madrugada
- **Problema:** un lunes, el gasto diario de una suscripción de producción subió un 300 % por un servicio que nadie esperaba; el presupuesto mensual todavía iba por el 40 %.
- **Causa:** un cambio de configuración activó registros de diagnóstico muy verbosos hacia Log Analytics.
- **Solución:** la **alerta de anomalías** de la suscripción avisó a las 36 horas del cierre del día; se ajustaron las categorías y la retención. Desde entonces hay una alerta de anomalías por suscripción de producción hacia un buzón del equipo.
- **Lección:** el presupuesto mira el acumulado; la anomalía mira la **forma** del gasto diario. Se complementan.

## Caso 8 · "Pero el recurso ya estaba apagado"
- **Problema:** el equipo apagó un clúster caro el martes y siguió recibiendo alertas el miércoles y el jueves.
- **Causa:** los datos de costo llegan con **8–24 horas de retraso**, y los presupuestos se evalúan **cada 24 horas**.
- **Solución:** para decisiones inmediatas se usan métricas de Azure Monitor (uso de CPU, número de nodos); los costos sirven para tendencias y para el cierre.
- **Lección:** Cost Management no es tiempo real. No lo uses como termómetro de lo que pasa ahora.

## Caso 9 · La exportación que rompió el panel de BI
- **Problema:** el panel de BI dejó de actualizarse cuando creció el gasto.
- **Causa:** el proceso leía un archivo por nombre fijo; al crecer los datos, la exportación se **particionó** en varios archivos (menos de 1 GB sin comprimir cada uno).
- **Solución:** el proceso lee el **`manifest.json`** de cada ejecución, que lista todas las particiones, y cargó el formato Parquet para ahorrar espacio.
- **Lección:** el particionado no se puede desactivar. Reconstruye siempre desde el manifiesto.

## Caso 10 · La exportación que no podía escribir
- **Problema:** una exportación nueva fallaba al entregar los datos a una cuenta de almacenamiento con firewall.
- **Causa:** el firewall no permitía a los **servicios de confianza de Azure**, y además la cuenta estaba en otro tenant (con firewall solo se admite el mismo tenant).
- **Solución:** cuenta de almacenamiento central en el mismo tenant, con servicios de confianza permitidos; la identidad administrada del export con *Storage Blob Data Contributor* en el contenedor; versión de API `2023-08-01` o posterior.
- **Lección:** el destino es parte del diseño de seguridad. Si cambias su red, **actualiza y guarda** la exportación.

## Caso 11 · La alerta de anomalías que se apagó sola
- **Problema:** durante meses no llegó ninguna alerta de anomalías, aunque hubo varias.
- **Causa:** la alerta la creó una persona que dejó el equipo y perdió el rol *Reader*; estas alertas usan el **acceso actual del creador** al enviarse.
- **Solución:** crearlas con una identidad de servicio mediante la API (o Terraform con la identidad del *pipeline*), con destinatarios en un buzón del equipo, y comprobar su vigencia cada trimestre.
- **Lección:** las alertas dependen de quién las creó. Hazlas con identidades que no se van.

## Caso 12 · Mil dólares al mes en discos sueltos
- **Problema:** una revisión de FinOps encontró unos mil dólares mensuales en discos, IP públicas y tarjetas de red huérfanos.
- **Causa:** proyectos terminados cuyos recursos secundarios nunca se borraron.
- **Solución:** una revisión mensual con las consultas de huérfanos ([B1–B4](ejemplos/kql/kql-costos.md)), etiqueta `owner` para saber a quién preguntar y una política de `DenyAction` para no borrar por accidente lo de producción (ver [bloqueos](../bloqueos-de-recursos/README.md)) mientras se limpia lo demás.
- **Lección:** el ahorro más fácil es dejar de pagar por lo que nadie usa.

---

## Patrones que se repiten
| Patrón | Casos |
|---|---|
| Avisar a mitad de mes (pronóstico, anomalías) | 1, 7 |
| Verificar que el presupuesto realmente alerta | 2, 6 |
| El freno lo construyes tú: reversible, acotado, con aviso previo | 3 |
| Etiquetas impuestas por política, con valores limitados | 4, 5 |
| Tiempos de los datos (8–24 h, 24 h, 36 h) | 7, 8 |
| Exportaciones: manifiesto, red y permisos | 9, 10 |
| Alertas que dependen de personas | 11 |
| Limpieza periódica de huérfanos | 12 |
