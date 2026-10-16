# Azure · Event Hubs (Kafka) · Troubleshooting

Sigue el flujo: **¿se conecta? → ¿puede enviar? → ¿se reparte bien? → ¿lee y avanza el consumidor? → ¿hay capacidad?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Kafka: `SaslAuthenticationException` / `Authentication failed` | Token inválido, ámbito equivocado, claves desactivadas con PLAIN | Logs del cliente; `AZMSRuntimeAuditLogs` | OAUTHBEARER con ámbito `https://<ns>.servicebus.windows.net/.default`; o habilitar claves **solo** para pruebas |
| Kafka: `Broker may not be available` / timeout al conectar | Puerto 9093 bloqueado, DNS privado mal resuelto, nivel Basic (sin Kafka) | `nc -vz <ns>.servicebus.windows.net 9093`; `nslookup` | Abrir 9093; zona `privatelink.servicebus.windows.net`; nivel Standard o superior |
| Kafka: `TopicAuthorizationException` / `UNKNOWN_TOPIC_OR_PARTITION` | El event hub no existe o falta rol en ese event hub | Lista de event hubs; roles | Crear el event hub (Terraform/CLI); *Data Sender/Receiver* en **ese** event hub |
| SDK: `AmqpException ... unauthorized-access` | Falta rol, o se asignó en otro ámbito | IAM del event hub / namespace | Asignar *Data Sender* o *Data Receiver*; esperar propagación (minutos) |
| `ServerBusy` / HTTP 429 / `ThrottledRequests` | Superaste TU/PU | Métricas del namespace | Más capacidad o tope de auto-inflate; lotes; reintento con retroceso |
| Productor: `RecordTooLargeException` / evento rechazado | Tamaño > límite del nivel | Tamaño del lote/evento | Lotes más pequeños; Claim Check para cargas grandes |
| Productor: tiempos de espera tras inactividad | El balanceador cerró la conexión inactiva | Logs con reconexiones | `connections.max.idle.ms=180000`, `metadata.max.age.ms=180000` |
| El orden de los eventos "se mezcla" | Sin clave, o claves distintas para la misma entidad | Particiones y claves reales | Clave de partición = entidad; recordar que el orden es **por partición** |
| Una partición con lag enorme y las otras no | Partición caliente (clave sesgada) | Eventos por partición; lag por partición | Cambiar la clave a una de alta cardinalidad |
| Consumidores sobrantes sin trabajo | Más consumidores que particiones | Asignación de particiones del grupo | Réplicas ≤ particiones; rediseñar particiones (en Standard no se puede cambiar: crear otro event hub) |
| Rebalances constantes / `CommitFailedException` | Se supera `max.poll.interval.ms` o `session.timeout.ms` | `AZMSKafkaCoordinatorLogs` | Menos `max.poll.records`, procesar más rápido, ajustar tiempos |
| Eventos duplicados | Reinicio entre procesar y commit; al menos una vez | Mismo `eventId` | Idempotencia por `eventId`; commit después de procesar |
| Eventos perdidos al reiniciar | Commit/checkpoint **antes** de procesar | Orden en el código | Commit/checkpoint después de procesar |
| El consumidor no recibe nada | Grupo equivocado, `auto.offset.reset=latest` en grupo nuevo, offset al final | Offsets del grupo | `earliest` para grupos nuevos; reposicionar offsets |
| SDK nativo: no reparte particiones entre instancias | No comparten contenedor de checkpoints o el nombre del grupo difiere | Blobs de `checkpoints` | Mismo contenedor, mismo grupo, mismo event hub |
| Checkpoint falla con 403 | Falta *Storage Blob Data Contributor* en el contenedor, o `shared_access_key_enabled=false` con cadena de conexión | Roles del contenedor | Rol al consumidor; usar `credential(...)` en vez de cadena |
| Capture no genera archivos | Sin rol de la identidad del namespace en el contenedor, contenedor inexistente, "skip empty archives" sin tráfico | Métrica `CaptureBacklog`; `AZMSArchiveLogs` | Rol *Storage Blob Data Contributor* a la identidad; contenedor correcto |
| Los datos desaparecen antes de leerse | Consumidor atrasado más que la retención | Retención vs. lag | Más retención (si el nivel lo permite), consumidores más rápidos, Capture |
| Schema Registry: `incompatible schema` | Cambio no compatible con la regla del grupo | Grupo de esquemas y regla | Evolución compatible (campos opcionales con valor por defecto) |
| Kafka Streams / transacciones fallan | Función no disponible en tu nivel | Documentación por nivel | Premium/Dedicated o rediseño |
| `reactor-kafka` falla con una versión nueva de `kafka-clients` | Biblioteca descontinuada; incompatibilidades | Excepción de clases/métodos | Migrar a Spring Kafka o Quarkus (secciones 8 y 9 de uso en Java) |
| Costo alto | TU/PU ociosas, auto-inflate en el tope sin bajar | Costos por recurso; métrica `IncomingBytes` | Reducir capacidad manualmente; presupuesto con alerta |
| Error de red con Private Endpoint | Zona DNS sin enlazar a la red del cliente | `nslookup` resuelve IP pública | Enlazar `privatelink.servicebus.windows.net` a la red y revisar `network_rulesets` |

## Secuencia recomendada
1. **Conectividad:** DNS, puerto (5671/9093/443), regla de red, Private Endpoint.
2. **Identidad:** token correcto, rol en el event hub (no solo en la suscripción).
3. **Productor:** respuesta del envío (`meta.offset()`), tamaño de lote, clave.
4. **Reparto:** eventos por partición (¿caliente?).
5. **Consumidor:** ¿avanza el offset? ¿lag por partición? ¿rebalances?
6. **Capacidad:** ThrottledRequests, TU/PU, auto-inflate.
7. **Plan de salida:** event hub de errores y alertas.

KQL en [ejemplos/kql](ejemplos/kql/kql-eventhubs.md); herramientas de consola en [ejemplos/cli](ejemplos/cli/event-hubs.sh).
