# Oracle OCI · Terraform · Autenticación y pipelines · Casos reales

## 1. La llave del exempleado
**Qué pasó:** el pipeline de ModaLima seguía usando la API key de un ingeniero que ya no estaba.
**Causa:** el CI usaba credenciales personales.
**Arreglo:** usuario de servicio por entorno con rotación trimestral; runners en OCI con instance principal.
**Lección:** los pipelines no son personas.

## 2. No-prod borró prod
**Qué pasó:** un error de variables hizo que el pipeline de no-prod apuntara al compartimento de prod y lo modificara.
**Causa:** una sola identidad con permisos en ambos.
**Arreglo:** identidades separadas; la de no-prod no tiene permisos en prod.
**Lección:** que el error sea imposible, no improbable.

## 3. El apply distinto al plan
**Qué pasó:** se aprobó un plan con 3 cambios y el apply hizo 7.
**Causa:** el apply recalculó el plan tras nuevos commits.
**Arreglo:** `plan -out` como artefacto y `apply` de ese archivo.
**Lección:** aplica exactamente lo que se revisó.

## 4. La llave en el repositorio
**Qué pasó:** una llave privada apareció en el historial de Git de Café Andino.
**Causa:** se copió `~/.oci` a la carpeta del proyecto.
**Arreglo:** revocar la llave, escaneo de secretos en PR y `.gitignore`.
**Lección:** revoca primero, investiga después.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Credencial huérfana | Llave personal | Usuario de servicio / instance principal |
| 2 | Cambio cruzado | Una identidad para todo | Identidad por entorno |
| 3 | Apply inesperado | Plan recalculado | Aplicar plan guardado |
| 4 | Llave expuesta | Archivo en el repo | Revocar + escaneo |
