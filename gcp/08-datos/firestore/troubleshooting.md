# Google Cloud · Datos · Firestore · Troubleshooting

## Lista ordenada
1. **¿Modo y ubicación?** Nativo vs Datastore; la ubicación no cambia después.
2. **¿Índice?** El error trae el enlace del índice a crear: llévalo a Terraform.
3. **¿Contención?** `ABORTED` en transacciones sobre el mismo documento.
4. **¿Permisos?** `datastore.user` para el backend.
5. **¿Tamaño?** Documentos cercanos a 1 MiB.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `FAILED_PRECONDITION: requires an index` | Índice compuesto | Créalo como código |
| `ABORTED` / `Too much contention` | Documento caliente | Fragmenta o reduce escrituras |
| `PERMISSION_DENIED` (servidor) | IAM | Rol en el proyecto |
| `PERMISSION_DENIED` (móvil) | Reglas | Revisa reglas |
| `INVALID_ARGUMENT` por tamaño | Documento > 1 MiB | Divide o mueve a Cloud Storage |
