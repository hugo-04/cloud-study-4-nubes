# NotebookLM · AWS · Capítulo 08 Datos

**Fuentes a subir:** este `README.md` y los `README.md`, `casos-reales.md` y `uso-en-java.md` de `rds-aurora`, `dynamodb` y `elasticache-redis`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, sobre los datos en AWS: Amazon RDS y Aurora, Amazon DynamoDB y Amazon ElastiCache (Valkey/Redis). Habla solo de AWS; no compares con otras nubes.

Estructura obligatoria:
1. La pregunta que responde cada servicio con su analogía (archivo contable, casillero gigante, libreta de apuntes) y cómo se complementan.
2. Aurora y RDS: motores, clúster, endpoints de escritura y lectura, failover, RDS Proxy, cuenta del pool de conexiones, autenticación IAM, secretos administrados, Blue/Green, recuperación a un punto en el tiempo, clasificación de errores SQL y reintento de la transacción completa.
3. DynamoDB: claves de partición y ordenación, particiones calientes, bajo demanda y aprovisionado, índices secundarios, Query y Scan, paginación con cursor firmado, escrituras condicionales, idempotencia con TTL, lotes con UnprocessedItems, bloqueo optimista, Streams y PITR.
4. ElastiCache: nodos, grupos de replicación, modo clúster, serverless, política de expulsión, TTL con azar, cache-aside con una sola recarga y caché negativa, limitador por ventana con script, candado con ficha, etiquetas de hash, TLS y ACL.
5. La tabla comparativa y el árbol de decisión; cuándo NO usar cada uno.
6. La receta de ModaLima y el orden de adopción; reglas transversales (la caché no es la fuente de verdad, diseño por patrón de acceso, red privada, cifrado, alarmas, probar la caída).
7. Java: el patrón de núcleo puro más envoltorio en Spring (MVC y WebFlux) y Quarkus (imperativo y Mutiny); ejemplos de cada servicio.
8. Los casos reales de cada servicio como historias con su lección.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 7 puntos de resumen y 5 preguntas de repaso.
```
