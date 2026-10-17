# Azure · Terraform · Módulos y entornos · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · El módulo copiado cuarenta veces
- **Problema:** ModaLima tenía el mismo bloque de cuenta de almacenamiento copiado en cuarenta repositorios. Seguridad pidió TLS 1.2 y tardaron tres meses en cambiarlo.
- **Causa:** copiar y pegar en vez de reutilizar.
- **Solución:** un módulo `app-base` con valores seguros por defecto, etiquetas de versión y un cambio por entorno con `?ref=`.
- **Lección:** un estándar vive en **un** sitio y se adopta con versiones.

## Caso 2 · `?ref=main` y el viernes de sorpresas
- **Problema:** un `plan` mostró cambios en recursos que nadie había tocado.
- **Causa:** el módulo se llamaba con `?ref=main` y alguien fusionó una mejora el jueves.
- **Solución:** etiquetas (`?ref=v1.3.0`), actualización deliberada por entorno y un `changelog`.
- **Lección:** un módulo sin versión es un cambio sin avisar.

## Caso 3 · `count` y la lista reordenada
- **Problema:** al borrar el primer elemento de una lista, el plan quería destruir y recrear las otras tres bases de datos.
- **Causa:** `count` identifica por posición; todo se desplazó.
- **Solución:** `for_each` por nombre de base y bloques `moved` de `[0]`, `[1]`, `[2]` a sus claves.
- **Lección:** identifica por **nombre estable**, no por posición.

## Caso 4 · Renombrar el módulo y casi perder la red
- **Problema:** al cambiar `module.red` por `module.red_hub`, el plan mostraba destruir y crear la VNet de producción.
- **Causa:** la dirección cambió y no había `moved`.
- **Solución:** `moved { from = module.red  to = module.red_hub }` y un plan con "0 to destroy".
- **Lección:** después de **cualquier** refactor, el plan debe decir "0 to destroy".

## Caso 5 · El proveedor configurado dentro del módulo
- **Problema:** no se podía usar `for_each` ni borrar el módulo: `Module is incompatible with count, for_each, and depends_on`.
- **Causa:** el módulo traía su propio `provider "azurerm"`.
- **Solución:** el módulo solo declara `required_providers`; el llamador configura el proveedor (y alias si hace falta).
- **Lección:** los módulos **declaran**, no **configuran** proveedores.

## Caso 6 · Dev y prod con el mismo código copiado
- **Problema:** prod quedó atrás de dev en tres versiones y nadie sabía qué tenía cada uno.
- **Causa:** carpetas copiadas con cambios a mano.
- **Solución:** un módulo, una carpeta por entorno con su `tfvars` y su estado, y un pipeline que promueve dev → qa → prod con la misma versión del módulo.
- **Lección:** los entornos se diferencian por **variables**, no por código.

## Caso 7 · El nombre de cuenta de 26 caracteres
- **Problema:** `apply` falló en producción con "name must be between 3 and 24 characters" y la aplicación `aplicacionlarg` no pudo desplegarse.
- **Causa:** `st` + aplicación + entorno (`prod`, más largo que `dev`) + sufijo superaba el límite; en dev funcionaba.
- **Solución:** una `precondition` que valida la longitud al planificar, una prueba con `expect_failures` y reglas de nombres en el portal de autoservicio.
- **Lección:** mueve el error del `apply` al `plan`, y del `plan` al formulario.

## Caso 8 · La prueba que no necesitó Azure
- **Problema:** probar un cambio al módulo requería una suscripción de pruebas, credenciales y veinte minutos.
- **Causa:** no había pruebas automáticas.
- **Solución:** `terraform test` con `mock_provider` y `assert`; el pipeline de pull request las ejecuta en segundos.
- **Lección:** prueba el **contrato** (nombres, seguridad, validaciones) sin crear nada.

## Caso 9 · Traer lo heredado
- **Problema:** Café Andino tenía un grupo de recursos creado a mano con diez recursos.
- **Causa:** crecimiento sin Terraform.
- **Solución:** `aztfexport` para el borrador, bloques `import` revisados, etiqueta `gestionado = "terraform"` y un plan limpio antes de tocar nada.
- **Lección:** importar es un proyecto pequeño: borrador automático, **revisión humana** y un plan sin cambios.

## Caso 10 · El módulo que pedía un secreto
- **Problema:** el módulo de base de datos recibía `administrator_password` como variable; apareció en el estado, en el plan y en un comentario de pull request.
- **Causa:** contrato con un secreto.
- **Solución:** el módulo genera/lee la clave desde Key Vault con identidad administrada, y la variable desapareció.
- **Lección:** el contrato de un módulo no debe incluir secretos.

## Caso 11 · `-target` para salir del paso
- **Problema:** para "arreglar rápido" se aplicó con `-target` y luego el plan completo quería cambiar quince cosas más.
- **Causa:** el código y la realidad quedaron desfasados por aplicar parcialmente.
- **Solución:** plan completo, revisar cada cambio, dividir el estado para que los planes sean pequeños.
- **Lección:** `-target` es una herramienta de emergencia, no un atajo.

---

## Patrones que se repiten
| Patrón | Casos |
|---|---|
| Una receta, versionada | 1, 2, 6 |
| Identificar por nombre, no por posición | 3, 4 |
| Los módulos declaran proveedores, no los configuran | 5 |
| Validar temprano: formulario → `validation` → `plan` | 7 |
| Pruebas sin infraestructura | 8 |
| Importar con revisión | 9 |
| Sin secretos en el contrato | 10 |
| Aplicar siempre el plan completo | 11 |
