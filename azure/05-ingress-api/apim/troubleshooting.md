# Azure · APIM · Troubleshooting

Primero responde: **¿quién devolvió el error, APIM o el backend?** En `GatewayLogs`: `ResponseCode` (lo que vio el cliente), `BackendResponseCode` (lo que dijo el backend), `LastErrorReason`, `LastErrorSource` (política o sección) y los tiempos (`TotalTime`, `BackendTime`).

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| **401** `Unauthorized` | Token ausente, caducado, audiencia/emisor distinto | Decodifica el JWT (jwt.ms); compara `aud`, `iss`, `ver`, `exp` con la política | Corregir `audiences`/`issuers` o la versión del token |
| 401 por **clave** | Falta `Ocp-Apim-Subscription-Key` o es inválida | Respuesta "Access denied due to missing subscription key" | Enviar la cabecera/query correcta; verificar el estado de la suscripción |
| **403** `Forbidden` | Suscripción sin acceso al producto; `ip-filter`; claim `roles` ausente; CORS (en navegador) | Traza; revisar producto y política | Asociar la API al producto; permitir la IP; rol correcto |
| **404** `Resource not found` | Ruta/operación no definida; versión o revisión equivocada; sufijo de URL | Lista de operaciones de la API; URL exacta | Crear/importar la operación; revisar el esquema de versión |
| 404 desde el backend | `rewrite-uri`/`set-backend-service` mal armado | Trazar la URL final del backend | Corregir plantilla y `base-url` |
| **405** | Método no permitido en la operación | Operación definida solo para GET | Definir el método |
| **413 / 400** | Cuerpo muy grande o `validate-content` falla | Mensaje de validación | Ajustar el límite/esquema |
| **429** `Too Many Requests` | `rate-limit`, `quota` o límite del backend | Cabecera `Retry-After`; política | Subir el límite o cambiar la clave; el cliente respeta `Retry-After` |
| 429 a todos | Clave por IP del gateway delante | `context.Request.IpAddress` = IP de Application Gateway | Clave por suscripción/JWT/`X-Forwarded-For` |
| **500** `Internal Server Error` | Error en una política o expresión | `LastErrorReason` / `LastErrorSource` en `GatewayLogs` | Corregir expresión, null checks (`?.`) |
| **500** al validar JWT | Imposible descargar la configuración OpenID | Red de salida hacia `login.microsoftonline.com` | Permitir la salida / DNS |
| **502** `Bad Gateway` | Backend inalcanzable, TLS inválido | `BackendResponseCode` vacío; `LastErrorReason` | Red/NSG/DNS; certificado del backend; `forward-request` |
| **503** | Backend sin capacidad / *circuit breaker* abierto | Estado del backend | Escalar; revisar reglas de circuito |
| **504** / `Timeout` | Backend lento o inalcanzable | `BackendTime` alto | Optimizar; ajustar `timeout`; patrón asíncrono |
| Gateway lento, backend rápido | Capacidad alta, políticas costosas, `send-request` | Métrica *Capacity*; `TotalTime - BackendTime` | Escalar; simplificar políticas; caché |
| Estado del servicio "Unhealthy"/gestión caída | NSG bloquea **3443** desde `ApiManagement` | Estado en el portal; reglas NSG | Permitir 3443 (ApiManagement) y 6390 (AzureLoadBalancer) |
| No resuelve el nombre en modo interno | Falta zona DNS privada | `nslookup <nombre>.azure-api.net` desde la VNet | Crear zona y registros a la IP privada |
| Named value de Key Vault en rojo | APIM sin identidad / sin rol; vault con firewall | Estado del named value | Identidad administrada + *Key Vault Secrets User*; red del vault |
| "Try it" del portal falla | CORS o certificado/hostname del gateway | Consola del navegador | Política `cors`; dominio personalizado correcto |
| Los cambios de política no aplican | Edición en otra revisión; caché del gateway; propagación | Revisión actual; esperar | Publicar la revisión; probar de nuevo |
| `terraform apply`: nombre no disponible | Soft-delete retiene el nombre | Lista de APIM eliminados | Purgar o usar otro nombre |
| Facturación inesperada | Developer/Premium encendidos; multi-región | Costos por recurso | Apagar/borrar laboratorios; revisar unidades |

## Cómo depurar una política
1. **Traza:** envía la petición con `Ocp-Apim-Subscription-Key` de un administrador y `Ocp-Apim-Trace: true`; revisa el panel de traza del portal ("Test").
2. **`trace` en la política:** `<trace source="debug"><message>@(context.Request.Url.ToString())</message></trace>` (solo en pruebas).
3. **`GatewayLogs` y Application Insights:** busca por `CorrelationId`/`OperationId`.
4. **Aísla:** deja solo la política mínima y añade una a la vez.
5. **Compara con una llamada directa** al backend con el mismo token.

## KQL
[ejemplos/kql/kql-apim.md](ejemplos/kql/kql-apim.md).

## Si el problema es de red
Sigue la escalera **RPDSI** del [diagnóstico de conectividad](../../01-red/diagnostico-conectividad/README.md): Resolución DNS → Puerto/ruta → Denegaciones (NSG/Firewall) → Servicio destino → Identidad.
