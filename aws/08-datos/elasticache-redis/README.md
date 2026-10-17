# AWS · Datos · Amazon ElastiCache (Valkey / Redis OSS en memoria)

**ElastiCache es una memoria compartida y rapidísima, administrada por AWS, que guarda datos en RAM con respuestas en menos de un milisegundo.** Se usa para **no repetir trabajo caro** (caché), guardar estado efímero (sesiones, contadores, límites de uso, candados) y repartir tareas livianas. Habla el protocolo de **Valkey/Redis OSS** (también existe Memcached, más simple y sin persistencia).

## 1. Qué es

**Analogía:** la **libreta de apuntes en el mostrador** de la tienda. Si un cliente pregunta el precio de un producto, miras la libreta (instantáneo); solo si no está, vas al archivo del sótano (la base de datos), y lo anotas para la próxima. La libreta es pequeña, a veces se borra y **nunca es la fuente de verdad**.

```
        ┌───────────┐  1. ¿está en la libreta?   ┌──────────────────────┐
 App ──►│ servicio  │───────────────────────────►│ ElastiCache (RAM)    │
        │  (Java)   │◄── sí: respuesta en <1 ms ─│  primario + réplicas │
        └─────┬─────┘                            └──────────────────────┘
              │ 2. no está: ir al origen
              ▼
        ┌───────────┐   3. guardar con vencimiento (TTL) y responder
        │ DynamoDB  │──────────────────────────────► (siguiente vez, paso 1 acierta)
        │ / Aurora  │
        └───────────┘
```

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Motor** | Valkey o Redis OSS (estructuras: cadenas, hashes, listas, conjuntos, conjuntos ordenados, streams…) o Memcached |
| **Nodo** | Un servidor con RAM; el tipo (`cache.r7g.large`…) fija memoria y red |
| **Grupo de replicación** | 1 primario (escribe) + hasta 5 réplicas (leen y reemplazan al primario si cae) |
| **Modo clúster deshabilitado** | Un solo *shard*: todos los datos en un primario; endpoint primario y endpoint de lectura |
| **Modo clúster habilitado** | Datos repartidos en varios *shards* (16 384 *slots*); un endpoint de configuración; escala memoria y escritura |
| **Serverless** | Sin nodos que elegir: escala sola; pagas datos almacenados y ECPU (unidades de cómputo) *(verifica mínimos y precios)* |
| **Multi-AZ y failover** | Réplicas en otras zonas; si cae el primario, se promueve una réplica y el DNS del endpoint apunta a la nueva |
| **Grupo de subredes** | En qué subredes privadas de tu VPC viven los nodos |
| **Grupo de parámetros** | Configuración del motor (política de expulsión, memoria reservada, timeouts) |
| **Política de expulsión** | Qué hacer cuando se llena la RAM: `allkeys-lru` (borra lo menos usado), `volatile-lru` (solo claves con TTL), `noeviction` (rechaza escrituras) |
| **TTL** | Vencimiento de cada clave: la caché sin TTL es una fuga de memoria |
| **Persistencia** | Copias (*snapshots*) diarias y manuales; no es una base durable: se pierden datos desde la última copia |
| **Cifrado** | En reposo (KMS) y en tránsito (TLS, direcciones `rediss://`) |
| **Autenticación** | Usuarios y grupos con ACL (RBAC) y contraseña, o IAM (token temporal) *(verifica requisitos)* |
| **Datastore global** | Réplica de solo lectura en otra región |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Resultados caros que se repiten (catálogo, configuración, consultas) | **Caché** (*cache-aside*) |
| Sesiones, carritos temporales, tokens | **ElastiCache** con TTL |
| Límite de peticiones por usuario o por clave de API | **ElastiCache** (contador con vencimiento) |
| Exclusión mutua liviana entre instancias | **ElastiCache** (candado con vencimiento) con las salvedades del §7 |
| Tablas de clasificación, contadores en tiempo real | **ElastiCache** (conjuntos ordenados, contadores) |
| Fuente de verdad de pedidos o pagos | No: [Aurora](../rds-aurora/README.md) o [DynamoDB](../dynamodb/README.md) |
| Cola con garantías de entrega | No: [SQS](../../07-mensajeria/sqs/README.md) |
| Datos que no puedes perder | No (la RAM se pierde; las copias van atrás) |
| Valores enormes (cientos de KB) | No: bloquean el motor y saturan la red; guarda un puntero a [S3](../../06-storage/s3/README.md) |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Cache-aside** | La app mira la caché; si falla, va al origen y la rellena |
| **Acierto / fallo (*hit / miss*)** | Estaba / no estaba en la caché |
| **Estampida (*thundering herd*)** | Miles de peticiones fallan a la vez y golpean el origen |
| **Avalancha** | Muchas claves vencen en el mismo instante; se evita con TTL + azar (*jitter*) |
| **Caché negativa** | Recordar por poco tiempo que algo «no existe» para no preguntar mil veces |
| **Slot y etiqueta de hash** | En modo clúster cada clave cae en un slot; `{etiqueta}` fuerza que varias claves compartan slot |
| **Clave caliente** | Una clave que concentra el tráfico y satura un nodo |
| **Ventana fija** | Contar peticiones en tramos de tiempo (por ejemplo, por minuto) |
| **Candado con vencimiento** | Una clave que dice «estoy trabajando»; vence sola si el dueño muere |

## 5. Cómo se usa
1. Decide el **uso** (caché, sesiones, límites) y la **política de expulsión** acorde: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Crea el grupo en **subredes privadas** con grupo de seguridad que permita el puerto 6379 **solo desde el grupo de tu aplicación** ([red](../../01-red/README.md)). No hay acceso desde Internet.
3. Activa **TLS**, cifrado en reposo y usuarios con permisos mínimos: [`ejemplos/acl/acceso.txt`](ejemplos/acl/acceso.txt).
4. Conéctate desde Java con un solo cliente por proceso, **tiempos de espera cortos** y reconexión que falle rápido ([uso en Java](uso-en-java.md)).
5. Todo con **TTL** y nombres con prefijo (`app:prod:tipo:id`).
6. Alarmas: memoria, expulsiones, CPU del motor, conexiones, retraso de réplica ([`ejemplos/cli/elasticache.sh`](ejemplos/cli/elasticache.sh)).
7. Ensaya el *failover* antes de producción.

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Aplicación** | — | **No va por IAM de datos** (salvo autenticación IAM): usuario ACL + contraseña (desde [Secrets Manager](../../03-secretos/README.md)) o token IAM, sobre TLS |
| **Operaciones** | `elasticache:Describe*`, `ModifyReplicationGroup`, `TestFailover`, `CreateSnapshot` | — |
| **Pipeline** | `elasticache:Create*`, `Modify*`, `Delete*` (acotado por etiquetas) | — |

- **Red:** subredes privadas + grupo de seguridad de origen = grupo de la app; sin IP públicas.
- **Cifrado:** en tránsito (TLS) y en reposo (KMS) activados **al crear** el grupo (en tránsito no siempre se puede activar después sin interrupción: planifícalo).
- **ACL:** usuario por aplicación, restringido a su prefijo de claves y sin comandos peligrosos (`-@dangerous`); desactiva el usuario `default`.
- **Datos:** no guardes datos personales sin TTL; la caché también es un almacén sujeto a tus políticas.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| TTL en **todas** las claves, con azar para evitar avalanchas | Claves sin vencimiento «porque cabe» |
| Tratar la caché como **opcional**: si falla, ir al origen | Hacer que la app caiga si la caché no responde |
| Tiempos de espera cortos y fallo rápido durante reconexión | Dejar el comportamiento por defecto que acumula comandos |
| Réplicas en varias zonas y failover automático | Un solo nodo en producción |
| Etiquetas de hash para claves que se usan juntas (modo clúster) | Operaciones multi-clave entre slots distintos (`CROSSSLOT`) |
| Escaneo incremental (`SCAN`) para recorrer claves | `KEYS *` o `FLUSHALL` en producción |
| Valores pequeños y estructuras adecuadas | Objetos grandes o listas de millones de elementos |
| Candados solo para eficiencia; correctitud con condiciones en la base | Candados distribuidos como única garantía de exclusión |
| Cierre ordenado y un cliente por proceso | Un cliente nuevo por petición |
| Probar failover y reinicios | Descubrir el failover en producción |

## 8. Límites, costos y versiones
- **Costo:** por hora de nodo (tipo y número), o por GB de datos + ECPU en *serverless*; copias de seguridad, transferencia entre zonas y datastores globales *(verifica precios)*. Las réplicas multiplican el costo de memoria.
- **Límites** *(verifica)*: memoria por tipo de nodo; conexiones simultáneas por nodo (decenas de miles); valores de hasta 512 MB (no lo uses).
- **Terraform:** `aws_elasticache_replication_group`, `aws_elasticache_serverless_cache`, `aws_elasticache_subnet_group`, `aws_elasticache_parameter_group`, `aws_elasticache_user`, `aws_elasticache_user_group`, `aws_security_group`. Validado con `init` + `validate`.
- **Java:** Lettuce (con Spring Data Redis) o el cliente de Quarkus; Java 21.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
