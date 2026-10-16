# NotebookLM · Azure · Azure Files

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Files, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es Azure Files, con la analogía de la carpeta compartida de la oficina, y en qué se diferencia de Blob Storage y de los discos.
2. Niveles y modelos: premium, estándar optimizado para transacciones, Hot y Cool; SMB frente a NFS; redundancia.
3. Las piezas: cuenta, share, directorios, instantáneas, soft delete, Azure Backup, File Sync y cuota (y por qué en premium la cuota define el rendimiento).
4. Autenticación y permisos: clave de la cuenta, Active Directory, Entra Domain Services y Entra Kerberos; las dos capas (RBAC de share y ACL NTFS); roles.
5. Red: el puerto 445, Private Endpoint, DNS privado, VPN, y por qué NFS solo va por red privada.
6. Casos de uso: lift-and-shift, ReadWriteMany en AKS, perfiles de usuario, intercambio de archivos, híbrido con File Sync; y cuándo NO usarlo.
7. Seguridad e IAM completa, incluyendo el conflicto entre desactivar las claves y los montajes que las usan.
8. Los 11 casos reales como historias con su lección.
9. Código Java: ruta montada con escritura .part y renombrado atómico, procesador con sondeo y reclamo por ATOMIC_MOVE, SDK por REST con identidad, versión reactiva y Quarkus con Mutiny, instantáneas y restauración.
10. Ejemplos de Terraform, CLI y YAML de Kubernetes (StorageClass, PVC, Deployment, NFS, PV estático).
11. Qué hacer y qué NO hacer, límites y costos, tabla de troubleshooting con la secuencia de diagnóstico y las consultas KQL.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
