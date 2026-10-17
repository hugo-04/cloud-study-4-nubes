# Google Cloud · Compute · GKE · Casos reales

## 1. La actualización del martes
**Qué pasó:** cada actualización automática de nodos de ModaLima causaba minutos de errores.
**Causa:** servicios con una réplica y sin PDB.
**Arreglo:** ≥ 2 réplicas, PDB `minAvailable: 1`, readiness y apagado ordenado; ventana de mantenimiento de madrugada.
**Lección:** las actualizaciones son normales; diseña para ellas.

## 2. El nodo que se comía todo
**Qué pasó:** un pod sin límites de memoria tumbó a sus vecinos en un clúster Standard.
**Causa:** sin requests/limits.
**Arreglo:** requests y limits obligatorios (política de admisión) o Autopilot.
**Lección:** el planificador necesita saber qué pide cada pod.

## 3. El plano de control público
**Qué pasó:** un escaneo encontró el endpoint de Kubernetes de Café Andino accesible desde Internet.
**Causa:** clúster público sin redes autorizadas.
**Arreglo:** endpoint privado y acceso por IAP/bastión.
**Lección:** la API de Kubernetes es una puerta de administración.

## 4. La versión fuera de soporte
**Qué pasó:** un clúster fijado a una versión vieja fue actualizado a la fuerza.
**Causa:** sin canal y versión al final de su soporte.
**Arreglo:** canal `REGULAR` y pruebas en no-prod con canal `RAPID`.
**Lección:** no puedes quedarte en una versión para siempre.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Errores al actualizar | Una réplica, sin PDB | PDB + réplicas |
| 2 | Vecinos caídos | Sin requests/limits | Obligatorios o Autopilot |
| 3 | API expuesta | Clúster público | Endpoint privado |
| 4 | Actualización forzada | Sin canal | Canal + pruebas |
