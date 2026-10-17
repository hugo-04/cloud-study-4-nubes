# AWS · CloudFront y WAF · Troubleshooting

Orden: **¿qué estado devuelve y quién (cabecera `X-Cache`: Hit/Miss/Error; `Via`) → ¿es la CDN o el origen? (prueba el origen directo) → ¿certificado/alias? → ¿política de caché y TTL? → ¿WAF bloqueando? (logs de WAF) → ¿acceso al origen (OAC, SG)?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `403` desde S3 (`AccessDenied`) | OAC sin política en el bucket, o objeto inexistente | Política del bucket; clave del objeto | Política con `AWS:SourceArn` de la distribución |
| `502 Bad Gateway` | Fallo de TLS/handshake con el origen o el origen cierra la conexión | Certificado del origen, protocolo | Certificado válido para el nombre del origen; `origin_protocol_policy` |
| `504 Gateway Timeout` | El origen tarda más que el timeout de respuesta | Latencia del origen | Optimizar; subir `origin_read_timeout` |
| `403` de WAF (`The request could not be satisfied`) | Una regla bloqueó | Logs de WAF (`terminatingRuleId`) | Excepción o ajuste de la regla; ponerla en Count |
| Contenido viejo | TTL largo o invalidación pendiente | `X-Cache`, `Age` | Invalidar; hash en nombres |
| Nunca hay `Hit` | Clave de caché con cookies/cabeceras variables o `Cache-Control: no-store/private` del origen | Política de caché; cabeceras | Minimizar la clave; arreglar `Cache-Control` |
| Datos de otro usuario | Cache de una ruta privada | Política del comportamiento | Desactivar caché; `no-store` |
| Certificado no aparece | El certificado no está en `us-east-1` o no está validado | ACM | Emitirlo en `us-east-1` |
| `CNAMEAlreadyExists` | El alias ya está en otra distribución | Mensaje | Quitarlo de la otra o usar otro |
| CORS falla | Cabeceras no incluidas en la clave/política de petición | Cabeceras de la respuesta | Política de cabeceras de respuesta de CORS |
| SPA da 404 en rutas profundas | Sin respuesta de error personalizada | Comportamiento | 403/404 → `/index.html` con 200 |
| URL firmada rechazada | Reloj, expiración, `Key-Pair-Id` equivocado o clave no está en el grupo de confianza | Parámetros de la URL | Revisar hora, grupo de claves |
| Origen recibe tráfico directo | SG abierto | SG del ALB | Prefix list de CloudFront + cabecera secreta |
