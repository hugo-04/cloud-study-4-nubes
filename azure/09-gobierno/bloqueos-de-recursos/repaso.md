# Azure · Bloqueos de recursos · Repaso

## Preguntas de repaso
1. ¿Qué es un bloqueo de recursos y a qué alcances se puede aplicar?
   - *Una marca de ARM que impide borrar (y/o modificar) un recurso; se aplica a suscripción, grupo de recursos o recurso (no a grupos de administración).*
2. ¿Qué diferencia hay entre `CanNotDelete` y `ReadOnly`?
   - *`CanNotDelete` permite leer y modificar pero no borrar; `ReadOnly` impide modificar y borrar (y bloquea operaciones `POST` que parecen lectura).*
3. ¿Los bloqueos anulan los permisos de un Owner?
   - *Sí: se aplican por encima de RBAC. Pero un Owner puede quitar el bloqueo, y luego borrar.*
4. ¿Quién puede crear o borrar bloqueos?
   - *Quien tenga `Microsoft.Authorization/locks/*`: Owner, User Access Administrator o un rol personalizado. Contributor no.*
5. ¿Qué pasa con los bloqueos y la herencia?
   - *Se heredan hacia abajo, incluidos los recursos creados después; si hay varios, gana el más restrictivo.*
6. ¿Protegen un bloqueo los datos de una cuenta de almacenamiento?
   - *No: solo actúan en el plano de control. Se puede borrar un blob con la cuenta bloqueada; para eso: versionado, borrado suave, inmutabilidad.*
7. ¿Qué efectos secundarios tiene `ReadOnly` en una cuenta de almacenamiento?
   - *Bloquea *List Keys*, la creación de contenedores y las asignaciones de roles desde el plano de control.*
8. ¿Qué efecto tiene `ReadOnly` en un grupo con App Service o VM?
   - *Bloquea escalar el plan y arrancar/reiniciar las máquinas.*
9. ¿Por qué `CanNotDelete` puede hacer fallar los despliegues de un grupo?
   - *Porque ARM no puede limpiar el historial al llegar a 800 despliegues.*
10. ¿Qué error devuelve ARM cuando un bloqueo impide la operación?
    - *`ScopeLocked`, con los alcances bloqueados.*
11. ¿Cómo se distingue de un problema de permisos o de política?
    - *`AuthorizationFailed` es RBAC; `RequestDisallowedByPolicy` es una política `Deny`; un 403 en un borrado con mención a una política es `DenyAction`.*
12. ¿Cómo se gestionan los bloqueos con Terraform?
    - *Con `azurerm_management_lock`, `depends_on` del recurso, y una variable (`proteger`) para quitarlo en un cambio revisado antes de destruir.*
13. ¿Qué alternativa existe a un bloqueo por recurso?
    - *Un bloqueo en el grupo, una política `DenyAction` por etiqueta, o una pila de despliegue con `denySettings`.*
14. ¿Qué son los `denySettings` de una pila de despliegue?
    - *Una protección que impide modificar y/o borrar los recursos gestionados por la pila (`denyDelete`, `denyWriteAndDelete`), con principales excluidos.*
15. ¿Qué cuesta un bloqueo?
    - *Nada. Es una propiedad de ARM sin cargo.*
16. ¿Cuántos bloqueos puede haber por alcance?
    - *Hasta 20 (verifica el límite vigente).*
17. ¿Cómo se audita quién quita bloqueos?
    - *Con el registro de actividad (`Microsoft.Authorization/locks/delete`), una alerta y consultas KQL en `AzureActivity`.*
18. ¿Por qué no se debe bloquear un grupo que crea un servicio administrado (copias de seguridad)?
    - *El servicio necesita borrar recursos de ese grupo; el bloqueo hace fallar sus operaciones.*
19. ¿Qué ocurre al borrar un grupo con un recurso bloqueado?
    - *El borrado del grupo falla por completo; no hay borrado parcial.*
20. ¿Cómo leerías un `ScopeLocked` desde Java?
    - *Capturas `ManagementException`, miras el código `ScopeLocked`, y devuelves un 409/423 con el procedimiento de desbloqueo, sin quitar el bloqueo automáticamente.*

## Mini-ejercicios
1. Diseña la estrategia de bloqueos de una suscripción de producción con 5 grupos de recursos (datos, red, aplicación, observabilidad, copias). ¿Dónde pones `CanNotDelete`, dónde no pones nada y por qué?
2. Escribe en Terraform un bloqueo `CanNotDelete` para un Key Vault y una variable para quitarlo en un borrado controlado.
3. Un equipo reporta "no puedo iniciar mi VM tras poner un bloqueo". Escribe los pasos para diagnosticar y corregir.
4. Redacta el procedimiento de borrado controlado de un grupo de producción: quién solicita, quién aprueba, qué se registra.
5. Dado un script de limpieza nocturno, ¿qué tres capas de protección pondrías en los recursos compartidos?

## Frases para recordar
- **Un bloqueo es un freno, no una pared.**
- **`CanNotDelete` por defecto; `ReadOnly` solo tras probar.**
- **No protege datos: solo recursos (plano de control).**
- **Bloqueos como código, con notas y alerta si se borran.**
- **Quien opera no administra los candados.**
