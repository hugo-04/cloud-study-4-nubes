# AWS · MSK · Repaso

## Preguntas
1. ¿Qué administra AWS en MSK y qué sigue siendo responsabilidad tuya?
   - *AWS: brokers, parches, reemplazos, zonas, cifrado. Tú: tópicos, particiones, permisos, clientes, capacidad lógica.*
2. ¿Aprovisionado, Express o Serverless?
   - *Aprovisionado: control fino; Express: escalado rápido sin administrar almacenamiento; Serverless: sin dimensionar, solo IAM, con límites por partición.*
3. ¿Qué puertos y modos de autenticación existen?
   - *9098 IAM, 9096 SASL/SCRAM, 9094 TLS mutuo, 9092 sin autenticación (pruebas).*
4. ¿Qué tres recursos controla la política IAM?
   - *Clúster, tópico y grupo de consumidores.*
5. ¿Qué configuración de producción se recomienda para durabilidad?
   - *3 zonas, RF=3, `min.insync.replicas=2`, productor con `acks=all` e idempotencia.*
6. ¿Por qué apagar la autocreación de tópicos?
   - *Evita tópicos accidentales; los tópicos se crean por código con su configuración.*
7. ¿Cómo se crea un tópico en MSK?
   - *Con la API de Kafka (AdminClient/scripts), desde un cliente que llegue a los brokers; no con la API de AWS.*
8. ¿Qué causa los rebalanceos constantes?
   - *Procesar un lote más lento que `max.poll.interval.ms`.*
9. ¿Qué es MSK Connect y cuándo usarlo?
   - *Kafka Connect administrado; para mover datos de/hacia S3, bases de datos, etc., sin operar servidores.*
10. ¿Cuándo preferir Kinesis, SQS o SNS?
    - *Kinesis: flujo sin necesitar Kafka; SQS: cola de trabajo; SNS: fan-out simple.*

## Ejercicios
1. Calcula particiones y almacenamiento para 20 MB/s de entrada, 3 MB/s por consumidor y retención de 3 días con RF=3 usando `PlanificadorMsk`.
2. Escribe la política IAM de un consumidor del tópico `pedidos.orden.creada.v1` con el grupo `facturacion`.
3. Crea un tópico con `AdminTopicos` (RF=3, `min.insync.replicas=2`) y verifica que sea idempotente.
4. Configura un listener de Spring Kafka con commit manual y reintentos con DLQ.

## Autoevaluación
- [ ] Explico los tres modos de clúster y cuándo usar cada uno.
- [ ] Configuro autenticación IAM en un cliente Java.
- [ ] Escribo la política IAM con clúster, tópico y grupo.
- [ ] Diagnostico un `TimeoutException` de metadatos y un rebalanceo continuo.
- [ ] Calculo particiones y almacenamiento con criterios.
