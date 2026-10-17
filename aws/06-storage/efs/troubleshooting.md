# AWS · EFS · Troubleshooting

Orden: **¿mount target en la zona de la app? → ¿SG permite 2049? → ¿DNS/VPC (resolución de nombres de EFS)? → ¿política del sistema de archivos (TLS/IAM)? → ¿punto de acceso y permisos POSIX? → ¿rendimiento/throughput?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `mount.nfs4: Connection timed out` | SG sin 2049, sin mount target en esa AZ, NACL | `nc -zv <ip-mount-target> 2049` | Regla de SG desde la app; mount target por AZ |
| `Failed to resolve "fs-xxxx.efs..."` | DNS de la VPC desactivado o nombre/región erróneos | `nslookup` | Habilitar DNS hostnames/support en la VPC |
| `access denied by server` | Política del sistema de archivos exige IAM/TLS y falta en el montaje | Política; opciones de montaje | `-o tls,iam` y permisos `ClientMount` en el rol |
| `Permission denied` al escribir | uid/gid sin permiso en el directorio | `ls -ln` | Punto de acceso con `PosixUser` y `CreationInfo` |
| Tarea de ECS no arranca por el volumen | Falta rol/SG o la tarea no está en subred con mount target | Evento de la tarea | Revisar SG, subredes y versión de plataforma de Fargate |
| Lambda: `EFSMountFailureException` | Función sin VPC/SG, o punto de acceso inválido | Configuración de la función | VPC con acceso al mount target; ARN del punto de acceso |
| Lectura/escritura muy lenta | Muchas operaciones pequeñas, throughput insuficiente (provisionado) | Métricas `PercentIOLimit`, `BurstCreditBalance` | Elastic throughput; agrupar operaciones |
| Aplicación se bloquea al tocar el montaje | NFS inaccesible sin timeout | Hilos bloqueados en `read/write` | Timeouts en sondas; montaje `soft` solo si la app tolera errores |
| `Stale file handle` | Archivo/directorio reemplazado mientras estaba abierto | Mensaje de error | Reabrir; evitar reemplazar directorios en uso |
| Costo creciente | Todo en Standard / lecturas altas en Elastic | Costos por tipo de uso | Ciclo de vida a IA; revisar patrones de acceso |
| No se puede cifrar el existente | El cifrado se decide al crear | Propiedades | Crear uno nuevo cifrado y copiar (DataSync) |
