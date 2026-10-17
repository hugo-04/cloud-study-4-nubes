# Oracle OCI · Ingress y API · API Gateway · Troubleshooting

## Lista ordenada
1. **¿Ruta correcta?** Host del gateway + `path_prefix` + ruta; método permitido.
2. **¿Registros de ejecución?** Actívalos en `INFO` temporalmente.
3. **¿401?** Token ausente, emisor/audiencia distintos, reloj desfasado o JWKS inaccesible.
4. **¿403?** Autenticado pero sin el alcance de la ruta.
5. **¿429?** Límite de tasa o cuota del usage plan.
6. **¿502/504?** Backend inaccesible (NSG, rutas) o lento.
7. **¿Funciones?** Política `request.principal.type = 'ApiGateway'`.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 | Prefijo o ruta no coinciden | Revisa `path_prefix` y la ruta |
| 401 | JWT inválido para este deployment | `iss`, `aud`, `exp`, JWKS |
| 403 | Falta *scope* | Alcances del token |
| 429 | Límite alcanzado | Ajusta tasa o cuotas |
| 502 | Backend no alcanzable | NSG, DNS privado, puerto |
| 504 | Backend lento | Tiempos o patrón asíncrono |
| CORS bloqueado | Origen no permitido | `allowed_origins` |
