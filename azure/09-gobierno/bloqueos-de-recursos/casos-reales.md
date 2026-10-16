# Azure · Bloqueos de recursos · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · "Borré el grupo equivocado"
- **Problema:** un ingeniero, con dos pestañas del portal abiertas, borró el grupo de recursos `rg-modalima-prod-datos` en lugar de `rg-modalima-dev-datos`. Dentro había Cosmos DB, un Key Vault y la zona DNS privada.
- **Causa:** el grupo no tenía ningún bloqueo y el ingeniero tenía *Contributor*, que incluye borrar.
- **Solución:** `CanNotDelete` en todos los grupos de recursos de producción (creado como código, no a mano) y una política `DenyAction` para los recursos con `env=prod`. El borrado de producción pasó a ser un procedimiento: ticket → quitar bloqueo → borrar.
- **Lección:** el bloqueo no impide al que tiene permiso; impide al que **no se da cuenta**. Es un freno, no una pared.

## Caso 2 · El `ReadOnly` que dejó sin escalar a la tienda en línea
- **Problema:** un día de campaña, el App Service no podía escalar horizontalmente y la tienda se puso lenta.
- **Causa:** alguien puso un bloqueo `ReadOnly` en el grupo de recursos "para que nadie toque nada". Escalar el plan de App Service es una operación de escritura sobre el plan: bloqueada.
- **Solución:** cambiar a `CanNotDelete` en ese grupo; se documentó la tabla de efectos de `ReadOnly` (escalado, inicio de VM, runbooks) en la guía de la plataforma.
- **Lección:** `ReadOnly` rompe cosas que parecen ajenas ("solo estoy leyendo el estado de salud"). **Prueba antes** y úsalo muy poco.

## Caso 3 · El Terraform que no podía destruir
- **Problema:** al destruir un entorno temporal, `terraform destroy` falló con `ScopeLocked` y dejó el entorno a medias.
- **Causa:** el bloqueo de un grupo de recursos no estaba en el código de Terraform; lo había puesto una persona a mano. El `destroy` borró varios recursos, llegó al bloqueado y se detuvo.
- **Solución:** los bloqueos pasan a `azurerm_management_lock` en el mismo módulo y con una variable `proteger`; para destruir, un cambio revisado pone `proteger = false`, se aplica y recién entonces se destruye. Los entornos efímeros no llevan bloqueo.
- **Lección:** un bloqueo que no está en el código es una **sorpresa para el pipeline**. Ponlo en el código, con `depends_on` del recurso protegido.

## Caso 4 · La copia de seguridad que dejó de limpiar
- **Problema:** meses después de proteger el grupo de recursos de las copias de seguridad, empezaron a fallar con un error al eliminar puntos de restauración.
- **Causa:** el servicio de copias crea un grupo de recursos propio y necesita **borrar puntos de restauración antiguos** (máximo 18). El bloqueo `CanNotDelete` en ese grupo se lo impedía.
- **Solución:** quitar el bloqueo del grupo creado por el servicio; proteger en su lugar el almacén (la *vault*) y usar las protecciones propias del servicio (borrado suave, MFA para operaciones críticas).
- **Lección:** no bloquees los grupos que **un servicio de Azure administra por ti**. Lee la sección de efectos de los bloqueos para cada servicio.

## Caso 5 · Los 800 despliegues
- **Problema:** un grupo de recursos protegido con `CanNotDelete` empezó a rechazar los despliegues nuevos con un error que mencionaba el historial.
- **Causa:** ARM guarda el historial de despliegues y **limpia automáticamente** al llegar a 800. Con el bloqueo, no puede borrar los más antiguos y se llena.
- **Solución:** quitar el bloqueo, limpiar el historial (script programado) y evaluar si el bloqueo debía ir sobre los **recursos críticos** y no sobre el grupo donde se despliega a diario.
- **Lección:** el bloqueo en el grupo de recursos donde se despliega con frecuencia tiene efectos laterales. Considera separar "recursos de estado" (bloqueados) de "recursos de aplicación" (no).

## Caso 6 · "Tengo Owner, ¿por qué no puedo borrar?"
- **Problema:** un nuevo administrador de plataforma, con rol *Owner*, no lograba borrar un servidor SQL de pruebas.
- **Causa:** el bloqueo anula los permisos, incluso del *Owner*. El mensaje decía `ScopeLocked`, pero solo vio "no autorizado" en el portal.
- **Solución:** la guía de soporte enseña a distinguir `ScopeLocked` (bloqueo) de `AuthorizationFailed` (falta de rol) y de `RequestDisallowedByPolicy` o 403 de `DenyAction` (política). Para borrar: el procedimiento de quitar bloqueo.
- **Lección:** tres vallas parecidas, tres errores distintos. Aprende a leerlos.

## Caso 7 · Quien despliega no debe quitar el candado
- **Problema:** una auditoría descubrió que los desarrolladores quitaban los bloqueos "para poder desplegar" y luego no los volvían a poner.
- **Causa:** los desarrolladores tenían *Owner* en su suscripción (por comodidad).
- **Solución:** *Contributor* para los equipos (no pueden crear ni borrar bloqueos), el rol personalizado "Administrador de bloqueos" solo para plataforma, PIM para el acceso temporal y una alerta del registro de actividad en cada creación o borrado de un bloqueo.
- **Lección:** el bloqueo solo sirve si **no es trivial quitarlo**. Separa funciones y alerta.

## Caso 8 · Bloqueo en el almacenamiento, y el equipo que perdió el acceso por clave
- **Problema:** tras poner `ReadOnly` en una cuenta de almacenamiento, una aplicación antigua dejó de funcionar.
- **Causa:** la aplicación obtenía las **claves de la cuenta** con *List Keys* (una operación `POST`), que `ReadOnly` bloquea. Tampoco se podían crear contenedores desde el plano de control.
- **Solución:** quitar el bloqueo `ReadOnly`, usar `CanNotDelete`, y migrar la aplicación a **Entra ID** (roles de datos) para no depender de las claves. Para impedir borrados de blobs: versionado y borrado suave, no bloqueos.
- **Lección:** el bloqueo no protege los datos y puede romper el modo de autenticación.

## Caso 9 · Limpieza automática que borró lo que no debía
- **Problema:** un script de FinOps borraba cada noche los recursos "sin etiqueta de dueño" y eliminó una zona DNS de la que dependían varios servicios.
- **Solución:** `CanNotDelete` en los recursos compartidos de red (DNS, VNet, hub) y política que exige la etiqueta `owner`. El script quedó con una lista de exclusión y un modo "solo informa" por defecto.
- **Lección:** los bloqueos protegen también de **tus propios scripts**. Ponlos en los recursos que muchas cosas necesitan.

## Caso 10 · El grupo que no se podía borrar y el bloqueo olvidado
- **Problema:** un proyecto terminó, pero su grupo de recursos no se podía borrar y seguía generando costo.
- **Causa:** un bloqueo que alguien puso "temporalmente" dos años atrás. Nadie sabía por qué, y la nota estaba vacía.
- **Solución:** regla: todo bloqueo lleva **notas** con motivo, dueño y ticket; una revisión trimestral de bloqueos (`az lock list` + Resource Graph) y borrado de los que no tengan dueño. Los bloqueos nuevos solo se crean desde código.
- **Lección:** un bloqueo sin notas es deuda técnica. Documenta el porqué.

## Caso 11 · Bloqueos y asignaciones de roles: la baja que falló
- **Problema:** el proceso de baja de empleados fallaba al quitar los permisos de una persona en un grupo de producción.
- **Causa:** con `CanNotDelete`, **borrar asignaciones de roles** en ese alcance también se bloquea.
- **Solución:** gestionar los permisos con **grupos de Entra ID** (se quita a la persona del grupo, no se borra la asignación) y mantener las asignaciones de roles estables en código.
- **Lección:** los permisos por grupos son más resistentes que las asignaciones personales; el bloqueo lo hace evidente.

## Caso 12 · Pilas de despliegue en vez de cientos de bloqueos
- **Problema:** Café Andino desplegaba un entorno completo por cliente (30 recursos) y quería evitar que nadie tocara lo desplegado. Poner un bloqueo por recurso era inmanejable.
- **Solución:** cada entorno se despliega como **pila de despliegue** (*deployment stack*) con `denyWriteAndDelete`, el *pipeline* como principal excluido y `--action-on-unmanage deleteAll` para que al quitar un recurso del código se borre de verdad.
- **Lección:** para entornos completos, la pila de despliegue protege **lo que gestiona**; los bloqueos son para recursos sueltos y grupos.

---

## Patrones que se repiten
| Patrón | Casos |
|---|---|
| Frenar el error humano o de un script, no al administrador malintencionado | 1, 9 |
| `ReadOnly` rompe operaciones "de lectura" que usan `POST` | 2, 8 |
| Los bloqueos tienen que ser código (Terraform) | 3, 10 |
| No bloquear lo que un servicio administra por ti | 4, 5 |
| Separar quién opera de quién administra candados + alertar | 6, 7, 11 |
| Para entornos completos, pilas de despliegue o política | 12 |
