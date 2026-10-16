# Azure · Azure Policy · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · "Nadie crea IP públicas en Corp"
- **Problema:** una máquina virtual de pruebas con IP pública y RDP abierto quedó olvidada durante meses y apareció en un informe de seguridad.
- **Causa:** no había ninguna regla que impidiera asociar IP públicas a interfaces de red en las suscripciones internas.
- **Solución:** la política integrada *Network interfaces should not have public IPs* con `Deny`, asignada en el grupo de administración **Corp** (no en cada suscripción). Las pruebas pasaron a hacerse por Bastion; las excepciones, por exención con fecha.
- **Lección:** prevenir cuesta menos que detectar. La regla va **arriba** para que ningún equipo pueda quitarla.

## Caso 2 · Etiquetas obligatorias para saber quién gasta
- **Problema:** el 30 % de los recursos no tenía dueño y el informe de costos no se podía repartir por equipo.
- **Solución:** una política de etiqueta `owner`, `env` y `cost-center`: **un mes en `Audit`** (informe semanal por equipo), luego `Deny` solo en Dev y Prod; y `Modify` para **heredar `env`** del grupo de recursos.
- **Resultado:** informes de costo por equipo y cero recursos huérfanos nuevos.
- **Lección:** introduce la regla **auditando** y comunicando antes de bloquear; usa `Modify` para lo que se puede resolver sin molestar a nadie.

## Caso 3 · Regiones por normativa… y Front Door que no se podía crear
- **Problema:** los datos de clientes solo podían estar en dos regiones. Se asignó *Allowed locations* en la raíz y, a la semana, un equipo no podía crear un perfil global de Front Door.
- **Causa:** los recursos globales usan la ubicación `global`, que no estaba en la lista de regiones permitidas.
- **Solución:** incluir `global` en el parámetro de regiones (o revisar el comportamiento de la definición con los recursos globales) y probarla con un despliegue de cada tipo habitual antes de pasar a `Deny`.
- **Lección:** una política de ubicación afecta también a recursos que "no tienen región". Prueba con **tipos de recurso reales**.

## Caso 4 · "El despliegue falló por una política"
- **Problema:** el *pipeline* de un equipo devolvía `RequestDisallowedByPolicy` sin más explicación en el registro del CI.
- **Causa:** el mensaje de error de ARM incluye la **asignación**, la **definición** y la propiedad que incumple, pero el *pipeline* solo mostraba la primera línea.
- **Solución:** (1) el *pipeline* imprime el error completo; (2) el servicio de autoservicio lee `additionalInfo` y devuelve un 422 con la regla y cómo corregirla (ver [uso en Java](uso-en-java.md)); (3) el mensaje de no conformidad de la asignación incluye el enlace a la guía y el correo del equipo de gobierno.
- **Lección:** el error ya dice qué regla y qué campo. Haz que ese texto llegue entero a quien lo tiene que arreglar.

## Caso 5 · 200 recursos antiguos que no cumplen
- **Problema:** al activar una política de TLS mínimo, el informe mostró cientos de recursos preexistentes no conformes.
- **Causa:** `Deny` solo afecta lo **nuevo**; lo existente queda marcado como no conforme.
- **Solución:** cambiar a una política `Modify` (poner `minimumTlsVersion`) con **tarea de remediación** para lo que se puede corregir sin riesgo, y un plan por equipo para lo que requiere ventana de mantenimiento.
- **Lección:** `Deny` para lo nuevo, `Modify`/DINE + remediación para lo existente.

## Caso 6 · La remediación "se queda en fallida"
- **Problema:** la tarea de remediación de *heredar etiquetas* terminaba con todos los recursos en error de autorización.
- **Causa:** la asignación se creó con Terraform; **con Terraform, CLI o SDK los roles de la identidad no se conceden solos** (solo el asistente del portal lo hace). La identidad administrada de la asignación no tenía permisos.
- **Solución:** `azurerm_role_assignment` para la identidad de la asignación (el rol de `roleDefinitionIds` de la definición, en el alcance correcto) y la tarea de remediación con `depends_on` de ese rol.
- **Lección:** toda política `Modify`/DINE necesita **identidad + rol + tarea**; documéntalo en el módulo.

## Caso 7 · El ensayo que evitó un apagón
- **Problema:** se quería activar `Deny` para "PaaS sin acceso público" en toda la organización.
- **Solución:** primero se asignó con `DoNotEnforce`. El informe mostró **1 300 recursos** incumpliendo, incluidos dos servicios críticos de pagos que usaban acceso público por una integración externa. Se acordó un plan: Private Endpoint para los críticos, exención con fecha para dos integraciones, y activar `Deny` primero en Sandbox y Dev (4 semanas) y luego en Prod.
- **Lección:** el modo de ensayo no es burocracia: **es lo que te dice a quién vas a romper**.

## Caso 8 · La exención que duró dos años
- **Problema:** una auditoría encontró un recurso de producción con acceso público "temporalmente" permitido hacía dos años.
- **Causa:** la exención se creó sin fecha de caducidad y sin dueño.
- **Solución:** consulta de Resource Graph para exenciones sin `expiresOn` o por vencer ([A4 y A5](ejemplos/kql/kql-policy.md)), servicio de exenciones que **exige** fecha (máx. 90 días), motivo y solicitante, y una revisión mensual.
- **Lección:** una exención sin fecha es una desactivación permanente con otro nombre.

## Caso 9 · La política que no hacía nada
- **Problema:** una política `Deny` de "Service Bus sin acceso público" estaba asignada, pero un equipo creó un espacio de nombres con acceso público sin problema.
- **Causa:** el alias de la propiedad estaba mal escrito; la condición nunca era verdadera, así que el estado era "100 % conforme".
- **Solución:** validar el alias con `az provider show … --expand "resourceTypes/aliases"`, empezar siempre en `Audit` y comprobar con una **consulta independiente de Resource Graph** ([B3](ejemplos/kql/kql-policy.md)) que lo que la política dice coincide con la realidad. Un despliegue de prueba que *debe fallar* quedó en el *pipeline* de la política.
- **Lección:** un cumplimiento de 100 % puede ser una regla rota. **Prueba que la política bloquea lo que debe.**

## Caso 10 · Alguien quitó la política de la suscripción
- **Problema:** una asignación de seguridad en la suscripción de un equipo desapareció "para poder desplegar".
- **Causa:** el equipo era *Owner* de su suscripción y podía borrar asignaciones hechas en ese nivel.
- **Solución:** mover las asignaciones al **grupo de administración** (el dueño de la suscripción no puede quitarlas), dar *Owner* solo cuando hace falta, y una alerta del registro de actividad cuando se cambia o borra una asignación.
- **Lección:** el nivel de la asignación decide quién puede deshacerla.

## Caso 11 · Los diagnósticos automáticos que subieron la factura
- **Problema:** tras asignar una política DINE que activa diagnósticos hacia Log Analytics, el costo del workspace se triplicó.
- **Causa:** la política desplegó **todas las categorías de registros** de todos los recursos, incluidos los de mayor volumen.
- **Solución:** parámetros para elegir categorías, *Basic logs* o tablas de bajo costo para lo voluminoso, retención diferenciada y un presupuesto con alerta sobre el workspace.
- **Lección:** DINE hace cosas **en nombre tuyo** y a escala; revisa el costo de lo que despliega. Ver [Costos](../cost-management/README.md).

## Caso 12 · Terraform y `Modify` se pelean por las etiquetas
- **Problema:** cada `terraform plan` quería quitar la etiqueta `env` que la política había agregado.
- **Causa:** Terraform ve la diferencia entre su estado (sin la etiqueta) y la realidad (la política la agregó) y propone "corregirla".
- **Solución:** `lifecycle { ignore_changes = [tags["env"]] }` en los recursos afectados, o declarar la etiqueta explícitamente en el código para que coincida con lo que la política pondría.
- **Lección:** las políticas `Modify`/`Append` y la IaC deben **ponerse de acuerdo** en quién es dueño de cada propiedad.

## Caso 13 · Gatekeeper rechazó el agente de monitoreo
- **Problema:** tras activar la política de AKS "no permitir `hostNetwork`", los pods del agente de monitoreo dejaron de arrancar.
- **Causa:** la política se aplicó a **todos** los espacios de nombres, incluidos los del sistema.
- **Solución:** parámetro de espacios de nombres excluidos (`kube-system` y los del agente), la política en `audit` unos días y pruebas en un clúster de preproducción. Ver [AKS](../../04-compute/aks/README.md).
- **Lección:** las políticas de Kubernetes rechazan al **admitir** el objeto; un rechazo se ve como pods que no se crean. Excluye los espacios de nombres de infraestructura.

---

## Patrones que se repiten
| Patrón | Casos |
|---|---|
| Ensayar (`Audit`/`DoNotEnforce`) antes de bloquear | 2, 5, 7, 9 |
| Asignar arriba (grupo de administración) | 1, 10 |
| Lo existente se arregla con remediación | 5, 6 |
| Exenciones con fecha, dueño y revisión | 7, 8 |
| Probar que la política hace lo que dice | 3, 9, 13 |
| Efectos secundarios (costos, IaC, rechazos inesperados) | 11, 12, 13 |
