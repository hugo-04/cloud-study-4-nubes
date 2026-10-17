# Azure · Terraform · Módulos y entornos · Troubleshooting

Orden de revisión: **¿inicializó (init)? → ¿validan las variables? → ¿qué dice el plan sobre direcciones (+, -, -/+, ~)? → ¿proveedor y versión correctos? → ¿estado y backend del entorno correctos?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `Module not installed` / `Module source has changed` | Faltó `init` tras cambiar un `source` | `terraform init` | `terraform init` (o `-upgrade` si cambiaste el rango de versiones) |
| `Inconsistent dependency lock file` | El archivo `.terraform.lock.hcl` no coincide con las restricciones | `terraform providers` | `terraform init -upgrade` y versionar el archivo; `providers lock` para varias plataformas |
| `Unsupported argument` en una llamada al módulo | Versión del módulo sin ese argumento | Versión en `?ref=` y variables del módulo | Subir la versión o quitar el argumento |
| `Invalid value for variable` | Una `validation` rechazó el valor | Mensaje de la validación | Corregir el valor |
| `Invalid for_each argument ... will be known only after apply` | Las claves dependen de un valor que Azure calcula | La expresión de `for_each` | Usar claves lógicas fijas y poner el valor desconocido en el valor, no en la clave; aplicar en dos pasos si hace falta |
| `Module is incompatible with count, for_each, and depends_on` | El módulo trae su propio `provider` | Archivos del módulo | Quitar la configuración del proveedor del módulo |
| El plan quiere destruir y crear tras un refactor | Cambió la dirección | Líneas `-/+` | Bloque `moved`; **no aplicar** |
| `Cycle: ...` | Dependencia circular entre recursos o módulos | `terraform graph` | Romper el ciclo (extraer un recurso, usar un *data source*) |
| `Provider configuration not present` | Se borró un módulo que usaba un alias, pero quedan recursos en el estado | Direcciones en el estado | Mantener el alias hasta destruir, o `removed` |
| `Missing required provider` / alias no encontrado | Falta `configuration_aliases` o `providers = {}` | `required_providers` del módulo | Declarar el alias y pasarlo |
| `subscription_id is a required provider property` | `azurerm` 4 sin suscripción | `ARM_SUBSCRIPTION_ID` | Definirla en el proveedor o en el entorno |
| `already exists - needs to be imported` | El recurso existe y no está en el estado | `terraform state list` | Bloque `import` |
| `Resource instance ... has moved ... but the target doesn't exist` | `moved` apunta a algo que no está en el código | Dirección `to` | Corregir la dirección |
| `terraform test` falla con `features is required` | Versión antigua con `mock_provider` de `azurerm` | `terraform version` | Actualizar la herramienta o agregar el bloque requerido por tu versión |
| `terraform test`: ID inválido con el simulado | El simulado inventa valores al azar | Mensaje con el ID | `mock_resource … defaults = { id = "..." }` con un ID válido |
| `Missing expected failure` en una prueba | La validación esperada no se disparó | El valor de prueba | Ajustar el valor o la regla |
| `plan` distinto entre dev y prod sin razón | Versión de módulo o de proveedor distintas | `terraform providers`, `?ref=` | Alinear versiones |
| Plan con cambios constantes en etiquetas | Una política de Azure las modifica | `terraform plan` y registro de actividad | `ignore_changes` con criterio o poner la etiqueta en el código |
| `azapi_resource` pide recrear siempre | Cambió el `body` por una propiedad que Azure devuelve distinta | Salida del plan | Ver qué propiedad cambia en el plan, ajustar el `body` y la versión de API; revisa en la documentación de `azapi` los atributos para ignorar propiedades |
| Un `output` aparece como `(known after apply)` y rompe otro módulo | Depende de un valor que se calcula al crear | Plan | Aplicar el origen primero o usar un *data source* |
| El módulo funciona en local y falla en el pipeline | Versiones distintas de Terraform/proveedor o `.terraform.lock.hcl` sin versionar | Registros del pipeline | Fijar la versión, versionar el archivo de bloqueo |

## Comandos útiles
```bash
terraform providers                          # qué módulo pide qué proveedor y versión
terraform init -upgrade                      # sube dentro de las restricciones
terraform validate                           # sintaxis y tipos
terraform console -var-file=prod.tfvars      # prueba expresiones (for_each, locals)
terraform graph | dot -Tsvg > grafo.svg      # ver dependencias y ciclos
terraform state list                         # qué direcciones existen
terraform plan -generate-config-out=gen.tf   # borrador de código para un import
terraform test -verbose                      # pruebas del módulo con los detalles
```

## Secuencia recomendada
1. **Inicialización:** `init` en el directorio correcto, con el backend del entorno.
2. **Variables:** ¿validan? ¿faltan? ¿el `tfvars` es el del entorno?
3. **Versiones:** módulo (`?ref=`), proveedor, Terraform; `.terraform.lock.hcl` versionado.
4. **Direcciones:** ¿el plan destruye y crea por un cambio de nombre? Añade `moved`.
5. **Proveedores:** ¿alias, suscripción, autenticación?
6. **Estado:** ¿clave y backend del entorno? ([estado remoto](../estado-remoto/troubleshooting.md))
7. **Pruebas:** reproducir con `terraform test` antes de tocar el entorno real.
