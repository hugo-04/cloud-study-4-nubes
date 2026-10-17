# AWS · EFS · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El modelo de 4 GB para la Lambda
**Qué pasó:** una Lambda de recomendaciones cargaba un modelo de 4 GB desde S3 en cada arranque en frío (30 s). **Solución:** el modelo vive en EFS (montado con punto de acceso de solo lectura) y se mapea a memoria. **Lección:** EFS para datos grandes y compartidos que cambian poco.

## 2. Tres réplicas escribiendo el mismo archivo
**Qué pasó:** tres contenedores generaban `reporte.csv` al mismo tiempo y a veces se mezclaban datos. **Solución:** escritura atómica (archivo temporal + `move`) y un nombre único por ejecución; bloqueo `FileChannel.lock()` cuando hay que coordinarse. **Lección:** NFS comparte, no sincroniza por ti.

## 3. El pod colgado por un montaje caído
**Qué pasó:** un fallo de red dejó el mount target inaccesible; el *health check* tocaba el disco sin timeout y los hilos se bloquearon, reiniciando pods en cascada. **Solución:** sonda con timeout y propia (`SondaMontaje`), y no usar el EFS en la sonda de *liveness*. **Lección:** un NFS colgado no devuelve error, devuelve silencio.

## 4. La factura de los archivos fríos
**Qué pasó:** 2 TB de adjuntos antiguos estaban en Standard. **Solución:** ciclo de vida a IA a los 30 días (y de vuelta al primer acceso). **Lección:** el ahorro llega con una regla de tres líneas.

## 5. Dos aplicaciones que se veían los archivos
**Qué pasó:** dos servicios montaban `/` del mismo EFS como root. Uno borró carpetas del otro. **Solución:** un punto de acceso por servicio (raíz `/app-a`, uid 1001; raíz `/app-b`, uid 1002). **Lección:** el punto de acceso es el aislamiento.

## 6. «Permiso denegado» en Fargate
**Qué pasó:** la tarea montaba el EFS pero no podía escribir: el contenedor corría como uid 1000 y el directorio pertenecía a root. **Solución:** punto de acceso con `PosixUser` y `CreationInfo` (propietario y permisos). **Lección:** los permisos POSIX siguen aplicando.

| Problema | Solución |
|---|---|
| Arranque lento de Lambda | Modelo en EFS |
| Escrituras mezcladas | Atómicas + bloqueo |
| Pods colgados | Sondas con timeout |
| Costo de fríos | Ciclo de vida a IA |
| Invasión entre apps | Un punto de acceso por app |
| Permisos POSIX | `PosixUser` + `CreationInfo` |
