# Google Cloud · Secretos · Secret Manager · Troubleshooting

## Lista ordenada
1. **¿Nombre completo?** `projects/<p>/secrets/<s>/versions/<v|latest>`.
2. **¿Rol sobre el secreto?** `secretAccessor` para la cuenta efectiva.
3. **¿Versión habilitada?** `latest` ignora deshabilitadas; una versión fija deshabilitada falla.
4. **¿CMEK?** El agente de Secret Manager necesita `cryptoKeyEncrypterDecrypter` en la llave.
5. **¿Secreto regional?** Usa el endpoint regional correspondiente.
6. **¿Cuotas?** 429 por tasa de acceso.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `PERMISSION_DENIED` | Falta accessor | Rol en el secreto |
| `NOT_FOUND` | Nombre o proyecto | Nombre completo |
| `FAILED_PRECONDITION` | Versión deshabilitada/destruida | Usa otra versión |
| 429 | Lecturas excesivas | Caché |
| Error de llave | CMEK sin permisos | Permiso del agente de servicio |
