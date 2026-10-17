# AWS · Datos · Amazon DynamoDB (clave-valor y documentos sin servidores)

**DynamoDB es una base de datos NoSQL totalmente administrada que guarda ítems (documentos pequeños) y los encuentra por su clave en milisegundos de un dígito, sin importar si tienes mil o mil millones.** No hay servidores que dimensionar, ni parches, ni conexiones: llamas a una API HTTPS y listo. A cambio, **debes diseñar la tabla alrededor de cómo vas a consultar**, porque no existe «busca en todo».

## 1. Qué es

**Analogía:** un **casillero gigante de correos**. Cada casilla tiene una etiqueta (la *clave*) y encontrarla es instantáneo; pero **no puedes preguntar «¿qué casillas tienen cartas rojas?»** sin abrirlas todas (un *Scan*). Por eso la etiqueta se diseña pensando en las preguntas que harás.

```
Tabla "pedidos"   clave de partición (pk) + clave de ordenación (sk)

 pk = CLIENTE#42   ┌ sk = ORDEN#2026-10-16#ord-48213  {total: 189.9, estado: "PAGADO"}
 (una partición)   ├ sk = ORDEN#2026-10-17#ord-48977  {total:  45.0, estado: "NUEVO"}
                   └ sk = PERFIL                      {nombre: "Ana", correo: "…"}

 pk = CLIENTE#77   ┌ sk = ORDEN#2026-10-15#ord-47001  {…}
                   └ sk = PERFIL

 Query(pk = CLIENTE#42, sk begins_with "ORDEN#")  → todas las órdenes de Ana, en orden, de un solo viaje
```

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Tabla / ítem / atributo** | Tabla sin esquema fijo; cada ítem (hasta **400 KB**) es un conjunto de atributos (texto, número, binario, lista, mapa, conjunto…) |
| **Clave primaria** | **Clave de partición** (obligatoria; su hash decide en qué partición física vive el ítem) + **clave de ordenación** (opcional; ordena los ítems de una misma partición) |
| **Particiones** | Trozos físicos internos que DynamoDB divide solas; cada una tiene límites de rendimiento: una clave muy usada genera una *partición caliente* |
| **Modo bajo demanda** | Pagas por lectura/escritura; escala solo; ideal al empezar o con carga impredecible |
| **Modo aprovisionado** | Fijas RCU/WCU (con *auto scaling*); más barato con carga estable y previsible |
| **RCU / WCU** | 1 RCU = una lectura fuerte de hasta 4 KB por segundo (o dos eventuales); 1 WCU = una escritura de hasta 1 KB por segundo |
| **Consistencia** | Lectura *eventual* (por defecto, más barata), *fuerte* (opción), *transaccional* |
| **Índice secundario global (GSI)** | Otra «vista» con otras claves; **eventualmente consistente** y con capacidad propia |
| **Índice secundario local (LSI)** | Misma clave de partición, otra ordenación; solo se crea con la tabla |
| **Query / Scan** | *Query*: lee una partición por su clave (barato y rápido). *Scan*: recorre todo (caro y lento) |
| **Expresiones** | De condición de clave, de filtro, de proyección, de actualización y **condicionales** (`attribute_not_exists`, comparar versión) |
| **Paginación** | Cada respuesta trae hasta 1 MB; si hay más, devuelve `LastEvaluatedKey` |
| **Transacciones** | `TransactWriteItems` / `TransactGetItems` (hasta 100 ítems, todo o nada; cuestan el doble) |
| **Lotes** | `BatchWriteItem` (25) y `BatchGetItem` (100); pueden devolver `UnprocessedItems` |
| **TTL** | Un atributo con la hora de caducidad; DynamoDB borra después (puede tardar hasta ~48 h) |
| **Streams** | Registro ordenado de cambios (24 h) para disparar Lambda, replicar o publicar eventos |
| **PITR y copias** | Restauración a cualquier segundo de los últimos 35 días (crea una tabla nueva) |
| **Tablas globales** | Réplicas multirregión activo-activo *(verifica los modos de consistencia vigentes)* |
| **DAX** | Caché en memoria compatible con la API, para lecturas con latencia de microsegundos |
| **Cifrado** | Siempre en reposo; clave propiedad de AWS, administrada o tuya (KMS) |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Acceso por clave a escala enorme y latencia estable (carritos, sesiones, perfiles, inventario) | **DynamoDB** |
| Control de idempotencia, bloqueos livianos, contadores | **DynamoDB** (escrituras condicionales, TTL) |
| Carga muy variable o picos impredecibles | **DynamoDB bajo demanda** |
| Eventos de cambio hacia otros sistemas | **DynamoDB Streams** → [mensajería](../../07-mensajeria/README.md) |
| Consultas ad-hoc, joins, reportes flexibles | [RDS / Aurora](../rds-aurora/README.md) |
| Búsqueda de texto completo | No: un servicio de búsqueda |
| Datos analíticos masivos | No: exporta a S3 y analiza con otra herramienta |
| Lecturas muy repetidas sobre pocos ítems | DynamoDB + caché ([ElastiCache](../elasticache-redis/README.md) o DAX) |
| Objetos grandes (> 400 KB) | [S3](../../06-storage/s3/README.md) y guarda la referencia |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Patrón de acceso** | Una pregunta concreta que tu aplicación hará («órdenes de un cliente, recientes primero») |
| **Diseño de una sola tabla** | Varias entidades en la misma tabla con claves compuestas (`CLIENTE#42`, `ORDEN#…`) |
| **Clave compuesta** | Prefijo de tipo + identificador en un solo texto, p. ej. `ORDEN#2026-10-16#ord-1` |
| **Partición caliente** | Una clave que concentra el tráfico y se limita mientras las demás están libres |
| **GSI disperso** | Índice donde solo aparecen los ítems que tienen el atributo del índice |
| **Escritura condicional** | «Escribe solo si…»; es la base de idempotencia y de bloqueo optimista |
| **Capacidad** | Cuánto lees/escribes por segundo; en bajo demanda lo administra AWS |
| **Cursor** | El `LastEvaluatedKey` que devuelves a tu cliente para pedir la página siguiente |

## 5. Cómo se usa
1. **Lista los patrones de acceso** antes de crear nada (qué preguntas, con qué frecuencia, qué orden).
2. Diseña claves que los respondan con `Query` (prefijos por tipo, fechas ordenables, GSI para el segundo ángulo): [`ejemplos/json/tabla-pedidos.json`](ejemplos/json/tabla-pedidos.json).
3. Crea la tabla como código con bajo demanda, PITR, cifrado, TTL y protección contra borrado: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
4. Usa el **endpoint de VPC de tipo pasarela** (gratuito) para que el tráfico no salga a Internet ([red](../../01-red/README.md)).
5. En Java: **Enhanced Client**, escrituras condicionales con versión, paginación con cursor firmado, lotes con reintento de `UnprocessedItems` ([uso en Java](uso-en-java.md)).
6. Alarmas de *throttling* y errores del sistema; revisa Contributor Insights si hay claves calientes.

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Servicio (lectura/escritura)** | — | `dynamodb:GetItem`, `Query`, `PutItem`, `UpdateItem`… sobre `table/<t>` **y** `table/<t>/index/*` |
| **Multi-inquilino** | — | Condición `dynamodb:LeadingKeys` para que cada identidad vea solo sus claves |
| **Consumidor de Streams** | — | `DescribeStream`, `GetRecords`, `GetShardIterator`, `ListStreams` sobre el ARN del stream |
| **Pipeline** | `dynamodb:CreateTable`, `UpdateTable`, `UpdateTimeToLive`, `UpdateContinuousBackups` | — |

- **Políticas por acción y por índice:** olvidar `table/<t>/index/*` es el `AccessDenied` clásico al consultar un GSI.
- **Cifrado:** siempre activo; con clave propia, los servicios necesitan permisos KMS.
- **Red:** endpoint de pasarela + política del endpoint que limite tablas y acciones.
- **Datos personales:** cifra campos sensibles en la aplicación si hace falta; los ítems aparecen en Streams, copias y exportaciones.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Diseñar desde los patrones de acceso | Modelar tablas como en SQL y luego «escanear» |
| `Query` con clave de partición | `Scan` en el camino de una petición |
| Claves de alta cardinalidad y reparto parejo | Claves con pocos valores o con la fecha de hoy |
| Escrituras condicionales para idempotencia y versión | Leer-modificar-escribir sin condición |
| Bajo demanda al empezar; aprovisionado con auto scaling si es estable | Aprovisionar «a ojo» sin auto scaling |
| TTL para datos efímeros y filtrar vencidos al leer | Suponer que el borrado por TTL es inmediato |
| PITR activado y protección contra borrado | Tablas de producción sin copias |
| Paginar con `LastEvaluatedKey` (cursor firmado) | Asumir que una consulta devuelve todo |
| Proyectar solo los atributos necesarios en GSI | Proyectar todo en todos los índices |
| Referencias a S3 para objetos grandes | Ítems de cientos de KB |

## 8. Límites, costos y versiones
- **Costo:** bajo demanda = por millón de lecturas/escrituras; aprovisionado = por RCU/WCU-hora; más almacenamiento, índices, Streams, copias, tablas globales y transferencia *(verifica precios)*. Un `Scan` o un GSI mal proyectado multiplican la cuenta.
- **Límites** *(verifica)*: ítem 400 KB; 1 MB por página; 100 ítems por transacción; 25/100 por lote; 20 GSI por tabla; límites por partición.
- **Terraform:** `aws_dynamodb_table`, `aws_appautoscaling_target/policy`, `aws_vpc_endpoint` (pasarela), `aws_cloudwatch_metric_alarm`. Validado con `init` + `validate`.
- **Java:** AWS SDK v2 (`dynamodb`, `dynamodb-enhanced`), cliente asíncrono para flujos reactivos.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
