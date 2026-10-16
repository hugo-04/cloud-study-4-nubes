# Azure · App Service · Troubleshooting

Orden: **¿arranca? → ¿responde por dentro? → ¿llega el tráfico? → ¿llega a sus dependencias?** Para dependencias privadas aplica Identidad → Permiso → Red → DNS → Servicio ([guía](../../01-red/diagnostico-conectividad/README.md)).

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| 503 / "Application Error" al iniciar | La app no escucha en el puerto que espera la plataforma, o tarda en arrancar | *Log stream*; `az webapp log tail`; consola de Kudu | Leer `SERVER_PORT` (JAR) o fijar `WEBSITES_PORT` (contenedor); subir `WEBSITES_CONTAINER_START_TIME_LIMIT` |
| Reinicia en bucle | OOM de la JVM o excepción en el arranque | Logs de consola; métrica *Memory working set* | `MaxRAMPercentage`, subir SKU, arreglar la excepción |
| 502 / 504 tras mucho rato | Petición supera ~230 s o la app no responde | Tiempo de la petición en `AppServiceHTTPLogs` | Responder 202 y procesar asíncrono; revisar la dependencia lenta |
| 502 justo después de un swap | La app aún no está lista | Hora del swap vs. arranque | `WEBSITE_SWAP_WARMUP_PING_PATH`, readiness real, *swap with preview* |
| Redirecciones a `http://` o enlaces sin HTTPS | El framework no confía en `X-Forwarded-*` | `request.getScheme()` en la app | `server.forward-headers-strategy=framework` / `quarkus.http.proxy.proxy-address-forwarding=true` |
| IP del cliente con `:puerto` | App Service añade el puerto en `X-Forwarded-For` | Cabecera en el log | Normalizar la IP |
| `Connection timed out` a base de datos/Redis privados | Falta VNet Integration, NSG/UDR lo bloquea o DNS resuelve a IP pública | `nameresolver <host>` y `tcpping <host>:<puerto>` en la consola Kudu | Integración VNet + zona DNS enlazada + reglas |
| La app resuelve el host privado a IP pública | Zona privatelink sin enlace a la VNet de la integración | `nslookup` desde Kudu | Enlazar la zona; revisar `WEBSITE_DNS_SERVER` |
| Todo el tráfico saliente falla tras activar "route all" | NSG/UDR/Firewall sin regla de salida | Rutas efectivas de la subred de integración | Permitir salida (443, DNS) o ajustar la ruta |
| `@Microsoft.KeyVault(...)` aparece literal | Identidad sin rol, red del vault cerrada, o falta `keyVaultReferenceIdentity` | Portal → Configuración → estado de la referencia | Rol *Secrets User*, acceso de red, identidad correcta |
| 403 desde Front Door / "Ip Forbidden (403)" | Access restriction bloquea | `az webapp config access-restriction show` | Añadir service tag `AzureFrontDoor.Backend` + cabecera `X-Azure-FDID` |
| Health check saca instancias sin motivo | La ruta del health consulta dependencias lentas o devuelve ≠ 2xx | Métrica *Health check status* | Ruta ligera de readiness, umbral razonable |
| Con 1 instancia el health check "no hace nada" | No hay otra instancia para reemplazar | Plan con 1 instancia | Mínimo 2 instancias |
| Tarea programada corre 3 veces | `@Scheduled` en cada instancia | Logs con `WEBSITE_INSTANCE_ID` | ShedLock o mover a Function de timer |
| Sesiones perdidas al escalar | Sesión en memoria | Varias instancias, mismo usuario | Redis/JWT; desactivar affinity |
| Archivos "desaparecen" | Escritos en disco efímero | Ruta de escritura | `/home` (compartido) o Blob Storage |
| Se despliega pero sigue la versión anterior | Despliegue al slot equivocado o sin reiniciar | Versión mostrada en `/actuator/info` | Verificar slot; `az webapp restart` |
| `Conflict`/409 al desplegar | Despliegue anterior en curso (SCM bloqueado) | Estado del despliegue en Kudu | Esperar o reiniciar el sitio SCM |
| Autoescalado no reacciona | Reglas con ventana larga, cooldown, o límite de máximo | Historial de actividad del autoscale | Ajustar ventana y límites |
| Imagen de contenedor no se descarga | La identidad no tiene `AcrPull` o falta `acrUseManagedIdentityCreds` | Logs de Docker en *Log stream* | Rol `AcrPull` y configuración de ACR con identidad |
| `AADSTS`/403 al llamar a Storage/Key Vault | Identidad equivocada o sin rol de datos | `AZURE_CLIENT_ID`, roles | Fijar `AZURE_CLIENT_ID`; asignar rol |

## Herramientas dentro de la app (Kudu / SSH)
```bash
# Consola avanzada: https://<app>.scm.azurewebsites.net  (o  az webapp ssh -g <rg> -n <app>)
nameresolver <host>              # DNS tal como lo ve la app
tcpping <host>:<puerto>          # conectividad TCP
curl -v https://<host>           # TLS y respuesta (si hay curl en la imagen)
env | grep -E "WEBSITE_|SERVER_PORT|AZURE_"
```

## KQL útil (Log Analytics)
```kusto
AppServiceHTTPLogs
| where TimeGenerated > ago(1h) and ScStatus >= 500
| summarize n = count() by CsUriStem, ScStatus
| order by n desc

AppServiceConsoleLogs
| where TimeGenerated > ago(30m) and ResultDescription has_any ("Exception", "OutOfMemory", "ERROR")
| project TimeGenerated, ResultDescription
```
