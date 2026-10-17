# Oracle OCI · Storage · File Storage · Troubleshooting

## Lista ordenada
1. **¿Red?** El cliente alcanza la IP del mount target (misma VCN o con ruta); NSG/lista de seguridad con los puertos NFS.
2. **¿Export correcto?** Ruta exacta (`/catalogo-media`) y export en el export set del mount target.
3. **¿Export options?** El CIDR del cliente debe coincidir con alguna opción; si no, «access denied».
4. **¿Puerto privilegiado?** Si se exige, monta como root (o desactívalo con criterio).
5. **¿Permisos UNIX?** UID/GID del proceso contra los del archivo; *squash* convierte root en anónimo.
6. **¿Rendimiento?** Muchos archivos pequeños; usa varios hilos y opciones de montaje adecuadas.
7. **¿Kubernetes?** Driver CSI, `StorageClass`/`PersistentVolume` con el OCID del file system y mount target.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `mount: connection timed out` | NSG o rutas | Abre puertos NFS desde el cliente |
| `access denied by server` | CIDR fuera de las export options | Ajusta la opción |
| `Permission denied` al escribir | Root squash o UID distinto | UID/GID coherentes |
| `ls` muy lento | Muchos archivos en una carpeta | Particiona directorios |
| Pod en `ContainerCreating` | Montaje CSI fallido | Eventos del pod; red del nodo |
