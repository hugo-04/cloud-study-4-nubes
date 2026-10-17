# Google Cloud · Ingress y API · API Gateway · Troubleshooting

## Lista ordenada
1. **¿La configuración se creó?** Errores de validación de OpenAPI 2.0.
2. **¿El gateway apunta a la configuración nueva?**
3. **¿401?** JWT: emisor, JWKS, audiencia, expiración.
4. **¿403?** Llave de API no habilitada para esta API o cuota.
5. **¿403 del backend?** La cuenta del gateway sin `run.invoker`.
6. **¿404?** Ruta no declarada en la especificación.
7. **¿502/504?** Backend caído o timeout de `x-google-backend`.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 401 `Jwt issuer is not configured` | Emisor no declarado | `x-google-issuer` |
| 401 audiencia | `aud` distinto | `x-google-audiences` |
| 429 | Cuota agotada | Revisa límites |
| 403 al backend | Invoker | Rol a la SA del gateway |
| Rutas duplicadas | `path_translation` | Ajusta la dirección |
