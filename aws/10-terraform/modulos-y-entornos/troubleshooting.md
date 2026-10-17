# AWS · Módulos y entornos · Troubleshooting

Orden: **¿corriste `init` (o `init -upgrade`) tras cambiar el `source`? → ¿la variable cumple la `validation`? → ¿hay valores desconocidos en `for_each`? → ¿el proveedor y la versión son los del `.terraform.lock.hcl`? → ¿el plan destruye algo que solo cambió de dirección (`moved`)?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `Module not installed` | No se ejecutó `init` tras añadir/cambiar el módulo | Mensaje | `terraform init` (o `-upgrade` si cambió la versión) |
| `Unsupported argument` en el módulo | La variable no existe en esa versión | Versión del módulo | Ajustar la versión o el argumento |
| `Variable validation failed` | El valor no cumple el contrato | Mensaje de `error_message` | Corregir el valor |
| `Invalid for_each argument … cannot be determined until apply` | La clave depende de algo desconocido | Origen de las claves | Usar claves conocidas (nombres) y no atributos calculados |
| El plan quiere destruir y recrear todo | `count` con orden cambiado o falta `moved` | Direcciones en el plan | `for_each` con mapa; añadir `moved` |
| `Cycle` | Dependencias circulares entre recursos/módulos | `terraform graph` | Romper la dependencia (variable o salida) |
| `Provider configuration not present` | Proveedor definido dentro del módulo | Estructura | Pasar `providers = { aws = aws.otro }` desde el raíz |
| Funciona en mi máquina, no en CI | `.terraform.lock.hcl` ausente o plataforma distinta | Bloqueo en Git | Subirlo; `providers lock -platform=linux_amd64 -platform=darwin_arm64` |
| `terraform test` falla con valores desconocidos | El simulado no devuelve datos reales | Aserciones sobre atributos calculados | Aserciones sobre lo conocido en el plan; `override_resource` |
| `expect_failures` no atrapa el error | La validación está en otro punto | Nombre del objeto | Apuntar a `var.x` o al recurso con `precondition` |
| Cambios por `tags` en cada plan | Etiquetas por defecto y del recurso se pisan | `default_tags` vs `tags` | Usar solo `default_tags` para las comunes |
| Salida con secreto se muestra | Falta `sensitive = true` | Salida del plan | Marcar la salida (aun así queda en el estado) |
| Dos entornos comparten estado | Misma `key` en el backend | `backend.<env>.hcl` | Una `key` por entorno y componente |
| El módulo remoto no baja | Credenciales de Git/red | Mensaje de `init` | Acceso del pipeline al repositorio de módulos |
