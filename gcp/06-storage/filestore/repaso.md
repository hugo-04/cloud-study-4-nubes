# Google Cloud · Storage · Filestore · Repaso

## Preguntas
1. ¿Qué es Filestore?
2. ¿Qué controla las opciones de exportación?
3. ¿Qué hace root squash?
4. ¿Cómo se usa en GKE?
5. ¿Qué se cobra?
6. ¿Controla IAM el acceso a los archivos?
7. ¿Cómo se conecta a tu VPC?
8. ¿Qué protege de borrados?
9. ¿Cuándo usar Cloud Storage?
10. ¿Cómo lo auditas desde Java?

## Respuestas
1. NFS administrado.
2. Quién puede montar, en qué modo y con qué squash.
3. Convierte al root del cliente en anónimo.
4. Con el driver CSI y PVC `ReadWriteMany`.
5. La capacidad aprovisionada según el nivel.
6. No; red y UID/GID.
7. Por peering administrado o PSC según el nivel.
8. Snapshots y respaldos.
9. Para servir o archivar archivos.
10. Con Cloud Asset Inventory.

## Ejercicios
1. Escribe las opciones de exportación del CMS de ModaLima.
2. Diseña snapshots y respaldos.
3. Escribe el PVC para un deployment de 3 réplicas.
