# Azure · Function Apps · Troubleshooting

Orden: **¿el host arranca? → ¿la función está registrada? → ¿el trigger recibe eventos? → ¿la función falla o se repite?** Para dependencias privadas aplica Identidad → Permiso → Red → DNS → Servicio ([guía](../../01-red/diagnostico-conectividad/README.md)).

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| La Function App está "Running" pero no hay funciones | Paquete mal generado, `function.json` ausente, o runtime/versión de Java incorrectos | `az functionapp function list`; logs de arranque | Revisar el plugin Maven (`package`), runtime Java 21, y el despliegue |
| `Host is offline` / `Function host is not running` | El host no puede usar la cuenta de Storage (`AzureWebJobsStorage`) | Application Insights → *Failures*; setting `AzureWebJobsStorage__accountName` | Roles de datos (*Blob Data Owner*, *Queue/Table Contributor*) y acceso de red al storage |
| `AuthorizationPermissionMismatch` / 403 en Storage | Faltan roles de datos para la identidad | `az role assignment list --assignee <principalId>` | Asignar los tres roles de Storage |
| El trigger no se dispara | Conexión mal nombrada (`connection="SBCONN"` vs settings), sin permiso, o red privada sin ruta | Settings `SBCONN__*`; logs del host | Corregir el nombre y los roles; VNet Integration/DNS |
| Service Bus: se dispara y falla siempre | Excepción sin tratar → reintentos hasta DLQ | DLQ de la cola; logs | Arreglar el dato; mover a revisión; `maxDeliveryCount` razonable |
| El mismo mensaje se procesa dos veces | Entrega *at-least-once*, timeout, lock vencido | `DeliveryCount` > 1; `maxAutoLockRenewalDuration` | Idempotencia; ajustar lock y duración |
| `MessageLockLost` | La función tarda más que el lock | Duración vs `lock-duration` | Subir lock o `maxAutoLockRenewalDuration`; acortar la función |
| Blob trigger no reacciona | Falta suscripción de Event Grid, o se usa sondeo en Flex | Suscripciones de eventos del storage | Crear la suscripción (`source = "EventGrid"`) |
| Blob trigger tarda minutos | Modo por sondeo | `source` del trigger | Cambiar a Event Grid |
| Timer corre a otra hora | UTC por defecto | `WEBSITE_TIME_ZONE` / cálculo | Expresar en UTC o fijar la zona donde se soporte |
| Timer no corre en la segunda instancia | Comportamiento normal: lease singleton | — | Es lo esperado (una ejecución a la vez) |
| Primera petición muy lenta | Arranque en frío de la JVM | Duración del primer request | *Always-ready*, plan Premium, menos trabajo en estáticos, CDS/nativo si aplica |
| Timeout a los 5/10/30 min | `functionTimeout` del plan | `host.json`; límites del plan | Dividir; Durable; subir donde el plan lo permita |
| Durable: `non-deterministic` / orquestación atascada | Código no determinista en el orquestador | Historial de la instancia | Mover I/O, hora y aleatoriedad a actividades |
| Durable: instancia "Running" para siempre | Espera un evento externo que nunca llega | Estado de la instancia | `waitForExternalEvent` con timeout; enviar evento |
| 401/403 en una función HTTP | `authLevel` o falta clave/token | Encabezado `x-functions-key` o token Entra | Ajustar nivel y autenticación |
| Facturación disparada | Bucle de eventos o escala sin tope | Invocaciones por minuto | Separar contenedores/colas; `maximum-instance-count` |
| `Out of memory` | Memoria de instancia insuficiente | Métricas | Subir `instance-memory`; revisar lotes grandes |
| Problemas solo con la red privada | Triggers sin ruta (Service Bus/Storage con Private Endpoint) | Conectividad desde la app | VNet Integration + DNS privado de cada servicio |
| `local.settings.json` funciona pero en Azure no | Falta el setting en la app, o nombre distinto | `az functionapp config appsettings list` | Replicar settings (por identidad) |

## Herramientas
```bash
az functionapp function list -g <rg> -n <func> -o table
az functionapp config appsettings list -g <rg> -n <func> -o table
az functionapp log deployment list -g <rg> -n <func>           # historial de despliegues (según versión)
func azure functionapp logstream <func>                         # logs en vivo
```

## KQL (Application Insights)
```kusto
requests
| where timestamp > ago(1h) and success == false
| summarize fallos = count() by operation_Name, resultCode
| order by fallos desc

traces
| where timestamp > ago(1h) and severityLevel >= 3
| project timestamp, operation_Name, message
```
