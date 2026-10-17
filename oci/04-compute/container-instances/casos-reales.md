# Oracle OCI · Compute · Container Instances · Casos reales

## 1. El reporte que cambió solo
**Qué pasó:** el reporte de ventas de ModaLima salió con columnas nuevas un lunes sin que nadie desplegara nada.
**Causa:** la instancia usaba `reportes:latest` y alguien subió una versión de prueba con esa etiqueta.
**Arreglo:** etiqueta inmutable en el registro y validación en el orquestador que rechaza `latest`.
**Lección:** la etiqueta es parte del contrato del despliegue.

## 2. Dos migraciones a la vez
**Qué pasó:** la migración de catálogo corrió duplicada y dejó registros repetidos.
**Causa:** un *timeout* de red en `CreateContainerInstance`; el cliente reintentó sin token y OCI creó dos instancias.
**Arreglo:** `opcRetryToken` derivado del identificador del trabajo (`migracion-catalogo-2026-10-17`).
**Lección:** toda creación desde código debe ser idempotente.

## 3. La contraseña en la consola
**Qué pasó:** un auditor vio la contraseña de la base en el detalle de la instancia.
**Causa:** se pasaba como variable de entorno `DB_PASSWORD`.
**Arreglo:** el contenedor lee el secreto de Vault con resource principal al arrancar.
**Lección:** las variables de entorno son configuración visible, no un cofre.

## 4. La factura de los fantasmas
**Qué pasó:** Café Andino pagaba cada mes por decenas de instancias.
**Causa:** los lotes terminaban (`INACTIVE`) pero nadie las borraba y algunas tenían `ALWAYS` y reiniciaban en bucle.
**Arreglo:** política `NEVER` para lotes, borrado automático tras leer el código de salida y alarma de instancias activas > N.
**Lección:** un lote debe terminar y desaparecer.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Cambio no desplegado | `latest` | Etiqueta inmutable + validación |
| 2 | Trabajo duplicado | Reintento sin token | `opcRetryToken` |
| 3 | Secreto expuesto | Variable de entorno | Vault al arrancar |
| 4 | Costo inesperado | Instancias olvidadas | `NEVER` + borrado automático |
