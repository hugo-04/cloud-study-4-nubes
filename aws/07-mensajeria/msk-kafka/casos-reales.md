# AWS · MSK · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El tópico que se creó solo
**Qué pasó:** un productor escribió en `pedidos.orden.creda` (con un error de tipeo) y el clúster, con `auto.create.topics.enable=true`, lo creó con 1 partición y RF=1. Nadie lo leía. **Solución:** `auto.create.topics.enable=false` y tópicos creados por código con su configuración. **Lección:** los tópicos son infraestructura, no un efecto secundario.

## 2. «Desde mi laptop no conecta»
**Qué pasó:** el equipo intentó usar el clúster desde casa y obtenía `Connection to node -1 could not be established`. **Solución:** los brokers están en subredes privadas; se trabaja desde la VPC (bastión por Session Manager o contenedores) y el grupo de seguridad solo abre 9098 a los clientes. **Lección:** MSK vive dentro de tu red; el acceso público no es la respuesta.

## 3. IAM sí, pero `GroupAuthorizationException`
**Qué pasó:** el consumidor se conectaba y veía el tópico, pero fallaba al unirse al grupo. Faltaba el permiso sobre el **grupo** (`DescribeGroup`, `AlterGroup`). **Solución:** política con los tres recursos: clúster, tópico y grupo. **Lección:** en MSK con IAM, cada acción tiene su recurso.

## 4. Rebalanceos eternos
**Qué pasó:** el consumo de facturación llamaba a una API lenta; cada lote tardaba más que `max.poll.interval.ms`, Kafka sacaba al consumidor del grupo y todo se reequilibraba una y otra vez, con `CommitFailedException`. **Solución:** `max.poll.records` menor, tiempo de sondeo adecuado, procesamiento idempotente y membresía estática. **Lección:** el consumidor debe volver a sondear a tiempo; un lote lento es un consumidor «muerto» para el grupo.

## 5. Disco lleno a las 3 a.m.
**Qué pasó:** la retención de 7 días con el pico del Black Friday llenó los discos de un broker; las escrituras fallaron. **Solución:** autoescalado de almacenamiento, almacenamiento por niveles para retención larga y alarmas de `KafkaDataLogsDiskUsed` al 70 %. **Lección:** capacidad = rendimiento × retención × réplicas; calcúlala y vigílala.

## 6. Piloto serverless, producción aprovisionada
**Qué pasó:** Café Andino empezó con MSK Serverless para validar el flujo de inventario, sin dimensionar nada. Al crecer, necesitó configuración fina y límites distintos. **Solución:** migrar a un clúster aprovisionado, replicando los tópicos y offsets con MSK Replicator, y cambiando solo los *bootstrap servers* de los clientes. **Lección:** empieza simple; los clientes no cambian porque el protocolo es Kafka.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Tópico creado por error | Autocreación apagada + tópicos por código |
| 2 | Conexión desde fuera de la VPC | Red privada + SG + bastión |
| 3 | Falta permiso de grupo | Política IAM con clúster, tópico y grupo |
| 4 | Rebalanceos por lote lento | `max.poll.records`, idempotencia, membresía estática |
| 5 | Disco lleno | Autoescalado, niveles, alarmas |
| 6 | Cambio de modelo de capacidad | MSK Replicator + mismo protocolo |
