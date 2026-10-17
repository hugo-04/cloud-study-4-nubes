# Azure · Terraform · Estado remoto · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · Dos `apply` a la vez
- **Problema:** un jueves, dos compañeros ejecutaron `apply` sobre la red casi al mismo tiempo; uno vio `Error acquiring the state lock`.
- **Causa:** el bloqueo del backend (el *lease* del blob) hizo exactamente su trabajo: el segundo esperó afuera.
- **Solución:** el segundo esperó, volvió a ejecutar `plan` (que ya mostraba los cambios del primero) y aplicó lo suyo.
- **Lección:** el bloqueo no es un estorbo. Y si se repite mucho, el estado es demasiado grande o compartido: **divídelo**.

## Caso 2 · El candado huérfano del pipeline cancelado
- **Problema:** una ejecución se canceló a media tarde; desde entonces, todos los `plan` fallaban con el mismo error de bloqueo.
- **Causa:** el proceso murió sin soltar el candado.
- **Solución:** se confirmó en el pipeline y con el equipo que **nadie** aplicaba, se copió el ID del error y se ejecutó `terraform force-unlock <ID>`. Se añadió al pipeline un grupo de concurrencia para que no haya dos ejecuciones sobre el mismo estado.
- **Lección:** `force-unlock` es seguro **solo** cuando has comprobado que nadie está aplicando. Y la mejor defensa es **serializar** los pipelines por estado.

## Caso 3 · El `tfstate` en el repositorio
- **Problema:** un estudiante subió `terraform.tfstate` al repositorio con una contraseña de base de datos generada.
- **Causa:** estado local, sin `.gitignore`.
- **Solución:** rotar la contraseña de inmediato, limpiar el historial, activar el backend remoto y añadir `*.tfstate*`, `*.tfvars` y `tfplan` al `.gitignore`, más un escaneo de secretos en el repositorio.
- **Lección:** el estado es **tan sensible como un secreto**. Un estado local es solo para laboratorios que no se comparten.

## Caso 4 · "Borramos el contenedor de estados"
- **Problema:** durante una limpieza de pruebas se eliminó el contenedor `tfstate`. Veinte estados desaparecieron.
- **Causa:** permisos amplios sobre la cuenta y sin protección de contenedores.
- **Solución:** el **borrado suave de contenedores** (30 días) permitió restaurarlo desde el portal en minutos. Después se añadió el bloqueo `CanNotDelete` sobre la cuenta y se quitó el permiso de escritura de la cuenta a las personas.
- **Lección:** versionado y borrado suave son la red de seguridad más barata que existe. Actívalos **antes** del incidente.

## Caso 5 · 403 el día que se desactivaron las claves
- **Problema:** el equipo de seguridad desactivó el acceso por clave en la cuenta de estados. Todos los pipelines empezaron a fallar con `403` y `AuthorizationPermissionMismatch`.
- **Causa:** el backend seguía configurado con la clave de la cuenta; y las identidades no tenían un rol de datos.
- **Solución:** `use_azuread_auth = true` en `backend.hcl`, rol *Storage Blob Data Owner* sobre el contenedor a la identidad de cada pipeline y `terraform init -reconfigure`.
- **Lección:** desactivar claves es una migración, no un interruptor. Primero los roles de datos, luego el cambio de backend, al final el apagado de las claves.

## Caso 6 · El firewall que dejó fuera a los pipelines
- **Problema:** tras cerrar el firewall de la cuenta, los `plan` de GitHub Actions empezaron a fallar por tiempo de espera.
- **Causa:** los ejecutores públicos no tienen IP estable; ninguna regla los permitía.
- **Solución:** *runners* propios dentro de una red con Private Endpoint hacia el almacén y su zona DNS privada. Un acceso de emergencia por IP (con caducidad) para el equipo de plataforma.
- **Lección:** al cerrar la red del estado, decide **desde dónde** se opera. Los ejecutores públicos y un firewall estricto no se llevan.

## Caso 7 · El plan que tardaba 25 minutos
- **Problema:** un solo estado con 3 000 recursos (red, bases de datos, aplicaciones, alertas). Cada `plan` en el pipeline tardaba 25 minutos y los despliegues se ponían en cola.
- **Causa:** Terraform refresca **cada recurso** en cada `plan`; y todo el equipo competía por el mismo candado.
- **Solución:** dividir por ciclo de vida y dueño: `plataforma/*`, `prod/red`, `prod/app-pedidos`, `prod/app-catalogo`… con `moved` e `import` para trasladar sin destruir. Los planes bajaron a 2–4 minutos.
- **Lección:** un estado grande es lento, frágil y un cuello de botella. Parte por **ciclo de vida, dueño y radio de daño**.

## Caso 8 · Renombrar sin destruir
- **Problema:** al mover la red a un módulo, el plan mostró `-/+` sobre la VNet (destruir y crear).
- **Causa:** al cambiar la dirección en el código, Terraform no sabía que era "el mismo" recurso.
- **Solución:** un bloque `moved { from = azurerm_virtual_network.vnet  to = module.red.azurerm_virtual_network.vnet }`; el plan pasó a "0 cambios".
- **Lección:** **leer el plan** es tu trabajo más importante, y `moved` deja la intención en el código y en la revisión (a diferencia de `state mv`).

## Caso 9 · `terraform_remote_state` que mostraba secretos
- **Problema:** el equipo de la aplicación leía las salidas del estado de base de datos con `terraform_remote_state`. Descubrieron que tenían acceso de lectura al estado completo, con la contraseña del administrador.
- **Causa:** para leer un estado hay que poder leer todo el blob.
- **Solución:** reemplazar la lectura por *data sources* de `azurerm` (por nombre del recurso), retirar el acceso de lectura al estado de datos y mover las contraseñas a Key Vault.
- **Lección:** compartir estado es compartir todo lo que contiene.

## Caso 10 · Recuperar el estado de ayer
- **Problema:** un `apply` interrumpido dejó el estado de `prod/app-pedidos` incompleto: faltaban recursos que sí existían en Azure.
- **Causa:** corte de red durante la escritura del estado.
- **Solución:** con el versionado del blob se descargó la versión anterior, se revisó (`serial`, `lineage`, recursos), se volvió a subir como versión actual y se ejecutó `plan -refresh-only` para reconciliar con la realidad. Los pocos recursos nuevos se trajeron con bloques `import`.
- **Lección:** el versionado te da una máquina del tiempo; la **reconciliación** (`refresh-only`, `import`) cierra la brecha.

## Caso 11 · El estado sin dueño
- **Problema:** `plataforma/legado.tfstate` no se modificaba hacía dos años y nadie sabía qué administraba.
- **Causa:** un proyecto abandonado.
- **Solución:** revisar sus recursos con `state list`, hablar con los `owner` de las etiquetas, migrar lo útil a estados nuevos y borrar el resto con `destroy` revisado. El auditor de estados (ver [uso en Java](uso-en-java.md)) lista ahora los inactivos para revisar cada trimestre.
- **Lección:** el inventario del almacén de estados es, de hecho, el inventario de tu infraestructura administrada. Cuídalo.

---

## Patrones que se repiten
| Patrón | Casos |
|---|---|
| El bloqueo protege; serializa los pipelines | 1, 2 |
| El estado es un secreto | 3, 9 |
| Versionado, borrado suave y bloqueo de la cuenta | 4, 10 |
| Migrar de claves a Entra ID con roles de datos | 5 |
| Decidir desde dónde se opera cuando cierras la red | 6 |
| Dividir el estado por ciclo de vida y dueño | 7, 11 |
| `moved`, `import` y `removed` en lugar de cirugía manual | 8, 10 |
