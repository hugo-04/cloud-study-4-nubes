# Oracle OCI · Storage · File Storage · Repaso

## Preguntas
1. ¿Qué piezas forman un montaje de File Storage?
2. ¿Dónde se define quién puede montar?
3. ¿Qué hace el root squash?
4. ¿Qué es el puerto privilegiado?
5. ¿Para qué sirven los snapshots?
6. ¿Qué modo de acceso de Kubernetes habilita?
7. ¿Cuándo prefieres Object Storage?
8. ¿Controla IAM el acceso a los archivos?
9. ¿Cómo cifras en tránsito?
10. ¿Qué tipo de carga es lenta en NFS?

## Respuestas
1. File system, mount target, export set y export.
2. En las export options (CIDR, acceso, squash) más NSG.
3. Convierte al root del cliente en un usuario anónimo.
4. Exigir que el cliente monte desde un puerto menor a 1024.
5. Restaurar archivos borrados o modificados y clonar.
6. `ReadWriteMany`.
7. Para servir, archivar o compartir archivos con terceros.
8. No: IAM controla los recursos; los datos se controlan por red y UID/GID.
9. Con el paquete de cifrado en tránsito (TLS) del cliente.
10. Muchas operaciones de metadatos sobre archivos pequeños.

## Ejercicios
1. Escribe las export options de la carpeta de medios de ModaLima (app RW, reportes RO).
2. Diseña la política de snapshots de las facturas de Café Andino.
3. Escribe el `PersistentVolume` y `PersistentVolumeClaim` para un deployment con 3 réplicas.
