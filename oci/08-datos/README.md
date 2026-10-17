# Oracle OCI · 08 Datos

¿Dónde guardo los datos de cada microservicio? Tres bases relacionales, una clave-valor y una caché, cada una para un patrón de acceso.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Autonomous Database](autonomous-database/README.md) | ¿Quiero SQL Oracle sin administrar nada? | Auto con chofer y mecánico | OLTP/analítica sin DBA |
| [MySQL HeatWave](mysql-heatwave/README.md) | ¿Mi app es MySQL y además necesito analítica? | Cocina con horno industrial | Apps MySQL, OLTP + reportes |
| [PostgreSQL](postgresql/README.md) | ¿Necesito PostgreSQL y sus extensiones? | Biblioteca con depósito central | Modelo relacional, `pgvector` |
| [NoSQL](nosql/README.md) | ¿Leo y escribo por clave a cualquier escala? | Pared de casilleros numerados | Carritos, sesiones, perfiles |
| [OCI Cache](cache-redis/README.md) | ¿Cómo respondo en microsegundos lo que se lee mucho? | Mostrador de cafés listos | Catálogo, sesiones, límites de tasa |

## Árbol de decisión: «quiero…»

```
¿Necesito transacciones y SQL relacional?
   ├─ ¿Mi app ya es MySQL?                     → MySQL HeatWave (+ HeatWave para analítica)
   ├─ ¿Necesito PostgreSQL o sus extensiones?  → OCI Database with PostgreSQL
   └─ ¿Prefiero cero administración / SQL Oracle? → Autonomous (ATP)

¿Accedo casi siempre por una clave conocida y necesito escala?
   └─ NoSQL (diseño por patrón de acceso, TTL)

¿Leo mucho lo mismo y puedo tolerar segundos de desactualización?
   └─ OCI Cache delante de la base (cache-aside)
```

## Comparativa

| Característica | Autonomous | MySQL HeatWave | PostgreSQL | NoSQL | Cache |
|---|---|---|---|---|---|
| **Modelo** | Relacional Oracle | Relacional MySQL | Relacional PostgreSQL | Clave-valor/JSON | Clave-valor en memoria |
| **Escala** | Autoescalado ECPU | Forma + réplicas + HeatWave | Forma + réplicas | Unidades/bajo demanda | Nodos/shards |
| **Alta disponibilidad** | Data Guard | HA 3 instancias | Almacenamiento replicado | Administrada | Réplicas |
| **Acceso a datos** | JDBC Oracle | JDBC MySQL | JDBC/R2DBC | SDK (IAM) | Cliente Redis |
| **Error típico** | Servicio `high` para OLTP | Pools sin tope global | Leer de réplica tras escribir | Leer-modificar-escribir sin versión | TTL sincronizado |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Pedidos y pagos | Autonomous ATP (`tp`) | Transacciones sin DBA |
| Catálogo heredado en MySQL + reporte de ventas | MySQL + HeatWave | Sin ETL para reportes |
| Recomendaciones con vectores | PostgreSQL con `pgvector` | Relacional + vectores |
| Carritos | NoSQL con TTL y versión | Clave conocida, concurrencia |
| Fichas de producto | OCI Cache | Lecturas masivas |

## Orden recomendado de adopción
1. Una base por microservicio (o un esquema por servicio como mínimo).
2. Credenciales desde Vault y usuarios de app con privilegios mínimos.
3. Pools dimensionados contra el total del motor.
4. Respaldos con restauración probada.
5. Caché solo cuando haya una lectura caliente medida.
6. NoSQL para patrones clave-valor claros.

## Reglas transversales
- Endpoints privados y TLS siempre.
- Nada de usuarios administradores en las aplicaciones.
- Migraciones versionadas y con rol propio.
- «Leer lo que escribí» en el primario.
- Protección contra borrado en producción.

## Java en datos: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Autonomous | Selector de perfil de conexión con reintentos | Descubrir al arrancar, no por consulta |
| MySQL HeatWave | Planificador de pools contra `max_connections` | Lógica pura + SDK |
| PostgreSQL | Enrutador lectura/escritura con ventana de consistencia | Reloj inyectable |
| NoSQL | Carrito con concurrencia optimista (`etag`/`ifMatch`) | Escrituras condicionales |
| OCI Cache | Cache-aside con anti-estampida y degradación | Almacén como interfaz |

## Cómo se relaciona con otros capítulos
- [Red](../01-red/README.md): subredes privadas, NSG y DNS.
- [Secretos](../03-secretos/README.md): contraseñas y llaves propias.
- [Compute](../04-compute/README.md): pools en OKE y VM.
- [Gobierno](../09-gobierno/README.md): costos, etiquetas y auditoría.
- [Casos integrados](../11-casos-integrados/README.md): la tienda en línea completa.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
