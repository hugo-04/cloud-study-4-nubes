# Google Cloud · IAM · Roles y políticas · Casos reales

## 1. El editor que borró producción
**Qué pasó:** un desarrollador de ModaLima borró un tema de Pub/Sub de producción creyendo que era de pruebas.
**Causa:** `roles/editor` en la carpeta que contenía ambos proyectos.
**Arreglo:** roles predefinidos por proyecto; en prod solo lectura para desarrollo.
**Lección:** los roles básicos son demasiado grandes.

## 2. El bucket para «todos»
**Qué pasó:** un bucket de reportes era legible por cualquier cuenta de Google.
**Causa:** binding con `allAuthenticatedUsers`.
**Arreglo:** quitarlo, política de organización de prevención de acceso público y URLs firmadas.
**Lección:** «autenticado» no significa «de mi empresa».

## 3. Terraform borró los permisos de otros
**Qué pasó:** un `apply` dejó sin acceso a medio equipo de Café Andino.
**Causa:** `google_project_iam_policy` reemplaza la política completa.
**Arreglo:** recursos `iam_member` aditivos.
**Lección:** cuidado con los recursos autoritativos.

## 4. El acceso de soporte que nunca venció
**Qué pasó:** un proveedor conservaba acceso un año después del proyecto.
**Causa:** binding sin expiración.
**Arreglo:** condición `request.time < timestamp(...)`.
**Lección:** lo temporal debe vencer solo.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Borrado indebido | Rol básico amplio | Predefinidos por proyecto |
| 2 | Datos expuestos | `allAuthenticatedUsers` | Quitar + política de org |
| 3 | Permisos perdidos | Recurso autoritativo | `iam_member` |
| 4 | Acceso eterno | Sin expiración | Condición de tiempo |
