# AWS · MSK · Troubleshooting

Orden: **red (¿llego al puerto?) → autenticación (¿puerto y mecanismo correctos? ¿rol?) → autorización (clúster/tópico/grupo) → tópico (existe, RF, `min.insync.replicas`) → rendimiento (particiones, *lag*, disco) → comportamiento del cliente (timeouts, rebalanceos).**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `Connection to node -1 could not be established` / `Timed out waiting for a node assignment` | Cliente fuera de la VPC, grupo de seguridad cerrado o puerto equivocado | `nc -vz <broker> 9098` desde el cliente; reglas del SG | Cliente en la VPC; SG permite el puerto del modo de autenticación |
| `SaslAuthenticationException: Access denied` | Rol sin `kafka-cluster:Connect`, o credenciales no encontradas | Identidad del pod/tarea (`aws sts get-caller-identity`); política | Política con `Connect` y rol asociado al servicio |
| Conecta al 9092/9094 pero el clúster exige IAM | Puerto o mecanismo no coinciden | `get-bootstrap-brokers` (cadena `SaslIam`) | Usar el bootstrap IAM (9098) y `AWS_MSK_IAM` |
| `TopicAuthorizationException` | Falta permiso sobre el tópico | ARN del tópico en la política | Agregar `DescribeTopic`/`ReadData`/`WriteData` con el patrón correcto |
| `GroupAuthorizationException` | Falta permiso sobre el grupo | ARN del grupo | `DescribeGroup`, `AlterGroup` sobre el grupo |
| `TimeoutException: Topic ... not present in metadata after 60000 ms` | Tópico inexistente (autocreación apagada) o sin permiso de `DescribeTopic` | `kafka-topics --describe` | Crear el tópico; revisar permisos |
| `NotEnoughReplicasException` | Una réplica caída con `acks=all` y `min.insync.replicas` igual al RF | Estado de brokers (métrica `UnderReplicatedPartitions`) | RF=3 y `min.insync.replicas=2`; resolver el broker |
| `CommitFailedException` / rebalanceos constantes | Lote más lento que `max.poll.interval.ms` | Registros del cliente | Bajar `max.poll.records`, subir el intervalo, acelerar el procesamiento |
| *Lag* creciente | Pocas particiones/instancias o procesamiento lento | `MaxOffsetLag`, `kafka-consumer-groups --describe` | Más instancias (hasta el nº de particiones), optimizar, más particiones |
| Disco al 90 % en un broker | Retención × rendimiento mayor que la capacidad, o particiones desbalanceadas | `KafkaDataLogsDiskUsed` | Autoescalado, `update-broker-storage`, almacenamiento por niveles, balancear |
| Mensajes duplicados | Reintentos del productor o reproceso tras rebalanceo | Mismo identificador de negocio | Productor idempotente; consumidor idempotente |
| Desorden dentro de una clave | Clave distinta, o `max.in.flight` alto sin idempotencia | Claves usadas | Misma clave; `enable.idempotence=true` |
| Error al cambiar la configuración del clúster | Propiedad no permitida o revisión incorrecta | `describe-configuration-revision` | Corregir y aplicar nueva revisión |
