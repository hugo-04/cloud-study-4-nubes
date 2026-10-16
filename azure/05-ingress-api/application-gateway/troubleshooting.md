# Azure · Application Gateway · Troubleshooting

Primero decide **quién** respondió el error: ¿el gateway o el backend? Mira el campo de origen en `ApplicationGatewayAccessLog` (código del gateway vs. `serverStatus` del backend).

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| **502** | Backend no sano / inalcanzable | `show-backend-health`; sonda; NSG; DNS | Corregir sonda, ruta, puerto o red |
| 502 con HTTPS al backend | Certificado no confiable o nombre distinto | Detalle del *backend health* ("certificate…") | Subir raíz de confianza; arreglar CN/SAN; SNI correcto |
| **504** | Backend tarda más que el *timeout* | `timeTaken` en el log; tiempo del backend | Optimizar; patrón asíncrono; ajustar *timeout* solo si es justo |
| **403** | WAF (o restricción del backend) | `ApplicationGatewayFirewallLog` | Exclusión puntual; regla personalizada Allow |
| 403 del App Service | Restricción de acceso no permite la subred del gateway | Configuración de red del App Service | Permitir la subred (o el servicio) del gateway |
| **404** | Ruta/host no coincide en el backend | Probar el backend directo con el mismo `Host` | Corregir el host/ruta o *rewrite* |
| **413** | Cuerpo mayor que el límite | Cuerpo de la solicitud | Subir límite WAF/gateway o usar SAS |
| 400 Bad Request | Cabecera demasiado grande o inválida | Log del gateway | Reducir cookies/cabeceras |
| Redirecciones infinitas | App redirige a HTTPS y el gateway reenvía HTTP | `curl -v` | `forward-headers-strategy` + `X-Forwarded-Proto` |
| El navegador acaba en `azurewebsites.net` | Host del backend distinto | Cabecera `Location` | Configurar el host (original vs del backend) |
| `ERR_CERT_COMMON_NAME_INVALID` | Certificado del listener no cubre el host | `openssl s_client -servername` | Certificado correcto/SAN; SNI en multi-site |
| Gateway en estado `Failed`/`Updating` | NSG bloquea `GatewayManager`; subred sin IPs; permisos | Actividad del recurso | Reglas obligatorias; ampliar subred; permisos |
| Certificado de Key Vault no carga | Identidad sin rol; vault con firewall | Mensaje de error en el listener | *Key Vault Secrets User*; red del vault |
| Certificado no se renueva solo | La referencia incluye **versión** | URL del secreto | Usar el secreto sin versión |
| Algunas peticiones fallan al desplegar | Backend retirado sin drenar | Errores solo al desplegar | *Connection draining*; readiness; retirar el backend del pool primero |
| WebSocket se cae | *Timeout* de inactividad | Corte a tiempo fijo | Latido; ajustar tiempo de espera |
| Latencia alta | Pocas unidades; backend lento | Métrica de unidades de capacidad; `timeTaken` | Subir `min`; optimizar backend |
| Sesiones se pierden | Afinidad desactivada con estado en memoria | Comportamiento por instancia | Estado compartido o afinidad por cookie |
| IP del cliente mal leída | `X-Forwarded-For` con puerto | Cabecera en el backend | Quitar el puerto en la app o con *rewrite* |

## KQL útil (Log Analytics)
Ver [ejemplos/kql/kql-appgw.md](ejemplos/kql/kql-appgw.md): errores 5xx por backend, tiempo de respuesta, top de reglas WAF y IPs bloqueadas.

## Secuencia recomendada para un 5xx
1. `az network application-gateway show-backend-health` → ¿`Healthy`?
2. ¿Responde el backend **directo** con el mismo `Host`? (`curl -H "Host: ..." http://IP-backend/ruta`)
3. NSG y DNS entre la subred del gateway y el backend ([diagnóstico](../../01-red/diagnostico-conectividad/README.md)).
4. Sonda: ruta, host, códigos aceptados, *timeout*.
5. Si usa HTTPS: cadena, nombre y SNI.
6. Mira el `X-AppGW-Trace-Id` de la petición fallida en el log de acceso.
