# Oracle OCI · Mensajería · Streaming · Repaso

## Preguntas
1. ¿Qué es un stream pool?
2. ¿Qué decide la partición de un mensaje?
3. ¿Dónde hay orden garantizado?
4. ¿Qué es un offset?
5. ¿Para qué sirven los grupos de consumidores?
6. ¿Cómo se conecta un cliente Kafka?
7. ¿Qué pasa si una clave concentra el tráfico?
8. ¿Qué revisas en la respuesta de `PutMessages`?
9. ¿Se pueden cambiar las particiones de un stream?
10. ¿Cuándo prefieres Queue?

## Respuestas
1. Un agrupador de streams con endpoint, cifrado y configuración Kafka.
2. Su clave.
3. Dentro de cada partición.
4. La posición del mensaje en su partición.
5. Repartir particiones y guardar el progreso de cada aplicación.
6. Con el bootstrap del pool, SASL_SSL PLAIN, usuario `<tenancy>/<usuario>/<ocid pool>` y auth token.
7. Se forma una partición caliente con *throttling*.
8. `failures` y el error de cada entrada.
9. No; se crea un stream nuevo.
10. Para tareas con reintento por mensaje y DLQ.

## Ejercicios
1. Calcula las particiones del clickstream de ModaLima para 3 MB/s con margen del 50 %.
2. Elige la clave para eventos de pedidos que deben procesarse en orden por pedido.
3. Diseña la exportación diaria a Object Storage.
