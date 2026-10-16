# Azure · Container Apps · Troubleshooting

Orden: **¿se creó la revisión? → ¿arrancan las réplicas? → ¿pasan las sondas? → ¿llega el tráfico? → ¿llega a sus dependencias?** Para dependencias privadas aplica Identidad → Permiso → Red → DNS → Servicio ([guía](../../01-red/diagnostico-conectividad/README.md)).

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| La revisión queda en `Provisioning`/`Failed` | Imagen no se descarga, secreto inaccesible, recursos inválidos | `az containerapp revision show`; `ContainerAppSystemLogs_CL` | Corregir imagen/identidad/secreto/combinación CPU-memoria |
| `ImagePullBackOff` / `unauthorized` | La identidad no tiene `AcrPull` o no se configuró el registro con identidad | Registro de la app; roles sobre el ACR | `--registry-identity` + rol `AcrPull`; esperar propagación |
| `manifest unknown` | Etiqueta/arquitectura incorrecta (imagen arm64 en nodos amd64) | Logs del sistema | Construir la imagen para `linux/amd64` |
| Réplica reinicia en bucle | La app falla al arrancar, OOM o la liveness falla | `az containerapp logs show`; métricas de *restarts* | Ver logs; `MaxRAMPercentage`; subir memoria; relajar la sonda de arranque |
| `OOMKilled` | Memoria del proceso > límite de la réplica | Logs del sistema | Subir memoria; calcular heap + no-heap |
| 502/503 del ingress | Puerto equivocado, la app no escucha en `0.0.0.0`, readiness falla | `targetPort` vs puerto de la app | Alinear `targetPort`; `quarkus.http.host=0.0.0.0` |
| La primera petición tarda muchos segundos | Arranque en frío (escala a cero) | `minReplicas`, historial de réplicas | `minReplicas = 1`; CDS; imagen nativa; más CPU |
| 504 / timeouts del ingress | La petición tarda más que el tiempo del ingress | Latencia de la app | Procesar asíncrono (202); optimizar |
| Una app no llama a otra | Nombre/puerto o ingress de destino `none` o externo | `az containerapp show` del destino | Usar el nombre de la app; habilitar ingress interno |
| No llega a la base de datos privada | Entorno sin VNet, NSG/UDR, DNS privado sin enlace | `nslookup`/`curl` desde `az containerapp exec` | Entorno en VNet + zona privatelink enlazada |
| Error al crear el entorno: subred | Tamaño insuficiente o subred sin delegación | Mensaje de error | Subred /27 (workload profiles) o /23 (Consumption-only), delegada a `Microsoft.App/environments` |
| El worker no escala desde cero | Autenticación de la regla KEDA falla o el nombre de la cola/namespace es incorrecto | Logs del sistema (errores del escalador) | Rol *Service Bus Data Receiver* a la identidad de la regla; nombres correctos |
| Escala demasiado y aplasta la base de datos | `maxReplicas` alto, concurrencia por réplica alta | Réplicas durante la carga | Topes; limitar concurrencia; pool de conexiones por réplica |
| El secreto de Key Vault no se resuelve | Identidad sin *Secrets User*, vault con red cerrada, URL errónea | Estado del secreto en la app; logs del sistema | Rol, red/DNS privado, URL correcta |
| El valor del secreto no cambia tras rotarlo | Las variables se leen al arrancar la réplica | Revisión antigua | Reiniciar la revisión o leer con SDK |
| Dapr: `ERR_PUBSUB_NOT_FOUND` | Componente no definido o app fuera de `scopes` | `az containerapp env dapr-component list` | Definir el componente y su `scopes` |
| Dapr: eventos no llegan | `/dapr/subscribe` no responde o la ruta devuelve error | Logs del sidecar (`daprd`) | Responder 200 y rutas correctas; `appPort` correcto |
| Job no se ejecuta | Cron en UTC, trigger manual, entorno sin capacidad | `az containerapp job execution list` | Revisar la expresión (UTC) y el estado |
| Job "falla" aunque el trabajo terminó | Código de salida ≠ 0 o `replicaTimeout` | Historial de ejecución | Terminar con 0; ajustar timeout |
| Costos altos con escala a cero | Revisiones antiguas activas con `minReplicas > 0` | `az containerapp revision list` | Desactivar revisiones viejas |
| La IP de salida cambia | Egreso por IP compartida | IP vista por el destino | NAT Gateway en entorno de *workload profiles* con VNet |

## Comandos útiles
```bash
az containerapp show -g <rg> -n <app> -o yaml
az containerapp revision list -g <rg> -n <app> -o table
az containerapp replica list -g <rg> -n <app> -o table
az containerapp logs show -g <rg> -n <app> --type console --follow
az containerapp logs show -g <rg> -n <app> --type system
az containerapp exec -g <rg> -n <app> --command sh
az containerapp env show -g <rg> -n <env> --query "properties.{vnet:vnetConfiguration, ip:staticIp, dominio:defaultDomain}" -o json
```

## KQL (Log Analytics)
```kusto
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(1h) and Log_s has_any ("Failed", "BackOff", "Error")
| project TimeGenerated, ContainerAppName_s, RevisionName_s, Log_s

ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(30m) and ContainerAppName_s == "api-pedidos"
| where Log_s has_any ("Exception", "ERROR")
| project TimeGenerated, RevisionName_s, ContainerName_s, Log_s
```
*(Los nombres de tablas y columnas pueden variar entre `_CL` clásicas y el esquema nuevo; verifica en tu workspace.)*
