# Google Cloud · Storage · URLs firmadas · Troubleshooting

## Lista ordenada
1. **¿Venció?** `X-Goog-Expires` y la fecha de firma.
2. **¿Método igual?** Una URL GET no sirve para PUT.
3. **¿Cabeceras firmadas iguales?** `Content-Type`, metadatos, precondiciones.
4. **¿El firmante tiene permiso sobre el objeto?** La URL hereda sus permisos.
5. **¿`signBlob` permitido?** `serviceAccountTokenCreator` sobre la SA y API IAM Credentials habilitada.
6. **¿CORS?** Para el navegador, el bucket debe permitir el origen, método y cabeceras.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `SignatureDoesNotMatch` | Cabecera o método distinto | Iguala lo firmado |
| `ExpiredToken` | Vencida | Nueva URL |
| 403 `AccessDenied` | Firmante sin permiso | Rol en el bucket |
| Error al firmar | Sin `signBlob` | Rol TokenCreator |
| Bloqueo CORS | Bucket sin CORS | Configura CORS |
