# AWS · 08 Datos

Tu aplicación guarda y consulta datos de formas muy distintas: transacciones con integridad, accesos por clave a escala enorme, o respuestas instantáneas que no vale la pena recalcular. En AWS cada forma tiene su servicio. Este capítulo reúne los tres más usados desde Java. La elección no es «cuál es mejor», sino **cómo vas a preguntar tus datos**.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [RDS / Aurora](rds-aurora/README.md) | ¿Puedo consultar mis datos **de muchas maneras**, con transacciones e integridad? | El archivo contable con índices y reglas | Datos relacionales: pedidos, pagos, inventario, reportes con SQL, `JOIN` y restricciones |
| [DynamoDB](dynamodb/README.md) | ¿Puedo **encontrar por clave** en milisegundos, sin importar el volumen? | El casillero gigante de correos | Accesos conocidos de antemano a gran escala: carritos, sesiones, perfiles, idempotencia |
| [ElastiCache](elasticache-redis/README.md) | ¿Puedo **no repetir** trabajo caro y responder en menos de un milisegundo? | La libreta de apuntes en el mostrador | Caché, sesiones efímeras, límites de uso, candados; nunca la fuente de verdad |

> Se **complementan**: el dato vive en Aurora o DynamoDB y ElastiCache lo acelera. Y los tres suelen aparecer en la misma aplicación.

## Árbol de decisión: «quiero…»

```
¿Necesito JOINs, transacciones entre varias tablas, restricciones e informes flexibles con SQL?
   └─ Aurora / RDS

¿Mis consultas son pocas y conocidas (por cliente, por pedido) y el volumen es muy grande o impredecible?
   └─ DynamoDB (bajo demanda para empezar)

¿Una lectura se repite mucho y recalcularla es cara?
   └─ ElastiCache delante de Aurora o DynamoDB (cache-aside con TTL)

¿Necesito sesiones, límites de peticiones o un candado liviano?
   └─ ElastiCache (con TTL; es efímero)

¿Necesito idempotencia de mensajes (no procesar dos veces)?
   └─ DynamoDB (PutItem condicional + TTL)

¿Necesito consultar de muchas formas que aún no conozco?
   └─ Aurora (DynamoDB exige conocer los accesos de antemano)

¿Necesito datos analíticos masivos?
   └─ Exportar a S3 (capítulo 06) y analizar allí, no consultar la base transaccional

¿El objeto es grande (cientos de KB o más)?
   └─ S3 con un puntero en la base
```

## Comparativa

| Característica | RDS / Aurora | DynamoDB | ElastiCache |
|---|---|---|---|
| **Modelo** | Relacional (SQL) | Clave-valor / documentos | En memoria (estructuras) |
| **Consulta** | Cualquier SQL | Por clave y por índices diseñados | Por clave exacta |
| **Latencia típica** | Milisegundos | Milisegundos de un dígito | Submilisegundo |
| **Escala** | Vertical + réplicas de lectura | Horizontal, automática | Por nodos / shards (o serverless) |
| **Transacciones** | Completas | Hasta 100 ítems | Scripts atómicos |
| **Durabilidad** | Alta (replicación + copias) | Alta (replicación + PITR) | **Baja**: es memoria |
| **Conexiones** | Limitadas: pool y RDS Proxy | Sin conexiones (HTTPS) | Muchas, pero finitas |
| **Esquema** | Fijo (migraciones) | Libre (claves fijas) | Libre |
| **Operación** | Media (parches, versiones, failover) | Casi cero | Baja (nodos) / cero (serverless) |
| **Costo base** | Instancias o ACU-hora | Por solicitud o capacidad | Por nodo-hora o GB + ECPU |
| **Error típico** | `too many connections`, transacciones largas | `Scan`, partición caliente, GSI mal dimensionado | Sin TTL, la caché como fuente de verdad |

## La receta ModaLima (cómo se ve junto)

| Dato | Pieza | Por qué |
|---|---|---|
| Pedidos, pagos, inventario contable | **Aurora PostgreSQL** (+ RDS Proxy) | Integridad, transacciones, reportes con SQL |
| Carrito y perfil del cliente | **DynamoDB** (`CLIENTE#id`) | Acceso por cliente, picos de campaña |
| Idempotencia de mensajes (SQS/EventBridge) | **DynamoDB** con TTL | `PutItem` condicional, limpieza automática |
| Catálogo de la portada | **ElastiCache** (cache-aside) | Lectura repetida, TTL con azar |
| Sesiones y límites de la API de socios | **ElastiCache** | Efímero, atómico con scripts |
| Cambios de pedidos hacia otros sistemas | **DynamoDB Streams** o eventos de la aplicación → [EventBridge](../07-mensajeria/eventbridge/README.md) | Desacople |

## Orden recomendado de adopción

1. **Aurora** como base transaccional (con RDS Proxy si hay muchas conexiones o Lambda).
2. **DynamoDB bajo demanda** para el primer acceso por clave de alto volumen (carrito, sesión) y para idempotencia.
3. **ElastiCache** cuando una lectura repetida duele (mide primero: aciertos y fallos).
4. **Copias y recuperación probadas** (PITR, snapshots, failover) antes de producción.
5. **Todo como código** (capítulo 10).

## Reglas transversales

- **El dato vive en la base; la caché solo lo acelera.** Si la caché desaparece, nada se pierde.
- **Diseña por patrón de acceso.** En DynamoDB define las consultas antes que las tablas; en Aurora, índices para las consultas reales.
- **Reintentos solo de lo seguro:** transacciones enteras en SQL, lotes por elemento en DynamoDB, comandos idempotentes en la caché.
- **Credenciales sin secretos en archivos:** Secrets Manager o identidad de la carga (Aurora con IAM, DynamoDB con rol); contraseña ACL de la caché desde un secreto.
- **Red privada:** subredes privadas para Aurora y ElastiCache; endpoint de VPC de pasarela para DynamoDB.
- **Cifrado con KMS** en reposo; TLS en tránsito.
- **Alarmas sobre lo que se degrada:** conexiones y latencia (Aurora), *throttling* (DynamoDB), memoria y expulsiones (ElastiCache).
- **Prueba la caída:** failover de Aurora, partición caliente en DynamoDB, failover de la caché.

## Java en datos: qué construye cada `uso-en-java.md`

Todos siguen el mismo molde: **un núcleo puro** (se prueba sin red), **un envoltorio** y los mismos casos en Spring MVC, WebFlux, Quarkus imperativo y Mutiny.

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| RDS / Aurora | Cálculo del pool, clasificador de errores SQL, reintento de la transacción entera, token IAM con caché, ensayo de failover | Núcleo puro + reintento de la unidad completa |
| DynamoDB | Claves que ordenan, cursor firmado, lotes con `UnprocessedItems`, idempotencia condicional, bloqueo optimista | Escrituras condicionales + resultado por elemento |
| ElastiCache | Claves y slots, TTL con azar, cache-aside con una recarga por clave, limitador, candado con ficha | La caché es opcional: ante fallo, al origen |

Reglas comunes: en reactivo, todo SDK bloqueante va a `boundedElastic` / pool de trabajo (o se usa el cliente asíncrono); cierre ordenado (`destroyMethod`, `@Disposes`); credenciales por la cadena por defecto.

## Cómo se relaciona con otros capítulos

- [Fundamentos](../00-fundamentos/README.md): regiones, cuotas y costos.
- [Red](../01-red/README.md): subredes privadas, grupos de seguridad y endpoints de VPC.
- [IAM](../02-iam/README.md): roles de servicio y permisos por tabla/índice.
- [Secretos](../03-secretos/README.md): credenciales de Aurora y de la caché.
- [Compute](../04-compute/README.md): Lambda y contenedores como clientes (conexiones y RDS Proxy).
- [Storage](../06-storage/README.md): objetos grandes y exportaciones.
- [Mensajería](../07-mensajeria/README.md): flujos de cambios, idempotencia de consumidores.
- [Terraform en AWS](../10-terraform/README.md): todo lo anterior como código.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, JSON y los específicos de cada servicio), troubleshooting, repaso y prompt de NotebookLM.
