# Azure · Datos · Azure Database for PostgreSQL – Flexible Server

## 1. Qué es

**Es PostgreSQL de verdad (la comunidad de código abierto) ofrecido como servicio administrado: tú creas esquemas, extensiones y consultas; Azure se ocupa de la máquina, los parches, los respaldos, la alta disponibilidad y el monitoreo.** Es una base **relacional** con transacciones ACID, tipos ricos (`jsonb`, arreglos, rangos, geográficos), extensiones (PostGIS, pgvector, pg_cron…) y el SQL estándar más potente del software libre. Se llama *Flexible Server* porque ofrece más control que el servicio anterior: ventanas de mantenimiento, parada/arranque, alta disponibilidad por zonas y parámetros del servidor.

Analogía: **una biblioteca con un bibliotecario experto en un sistema abierto**. El sistema de catalogación (PostgreSQL) es el mismo que usarías en cualquier otra biblioteca, así que puedes mudarte cuando quieras llevándote tus fichas; el bibliotecario (Azure) se encarga de reparar estantes, sacar copias y tener una sala gemela lista.

```
   Aplicaciones (Spring / Quarkus) ──► PgBouncer integrado (puerto 6432, opcional)  ──┐
                                      o directo al servidor (puerto 5432)               │
                                                                                        ▼
                    ┌────────────────────────── Flexible Server  <nombre>.postgres.database.azure.com ──────────────┐
                    │  Primario (zona 1)  ══ replicación síncrona ══►  Standby de alta disponibilidad (zona 2)        │
                    │   • bases, esquemas, roles (Entra ID o contraseña)      (conmutación automática, ~1–2 min)        │
                    │   • extensiones permitidas (pgvector, PostGIS, pg_cron…)                                         │
                    │   • copias automáticas + registro de transacciones (PITR hasta 35 días)                          │
                    └──────────────┬──────────────────────────────────────────────────────────────────────────────────┘
                                   │ replicación asíncrona
                          Réplicas de lectura (misma región o entre regiones) ──► reportes, lecturas escaladas
```

---

## 2. Cómo funciona por dentro

### 2.1 Un servidor, varias bases
Un **servidor** (`<nombre>.postgres.database.azure.com`) es una instancia de PostgreSQL con su cómputo y su almacenamiento; contiene varias **bases de datos**. A diferencia de Azure SQL, aquí **sí hay un servidor** al que aplicas parámetros (`max_connections`, `work_mem`, etc.). Puerto **5432** (directo) y **6432** (PgBouncer).

### 2.2 Cómputo y almacenamiento

| Nivel de cómputo | Para qué |
|---|---|
| **Burstable** (serie B) | Desarrollo, pruebas, cargas con picos ocasionales (CPU por créditos) |
| **General Purpose** (serie D) | Producción típica: equilibrio CPU/memoria |
| **Memory Optimized** (serie E) | Consultas con mucha memoria, cachés grandes, analítica ligera |

- **Almacenamiento:** Premium SSD (tamaño fijo con IOPS según tamaño) o **Premium SSD v2** (IOPS y rendimiento configurables aparte). Opción de **crecimiento automático** (*storage autogrow*). El almacenamiento **no se puede reducir**.
- **Parar/arrancar** el servidor (hasta 7 días) para ahorrar en desarrollo: se paga el almacenamiento, no el cómputo.
- *Verifica las series de máquinas, tamaños y regiones vigentes.*

### 2.3 Versiones y mantenimiento
- Versiones principales de PostgreSQL soportadas (a la fecha de redacción, 14 a 18; las más antiguas salen de soporte según el calendario de la comunidad). *Verifica la lista vigente.*
- **Parches menores automáticos** en una **ventana de mantenimiento** que eliges (día y hora).
- **Actualización de versión principal** en el lugar (*in-place major version upgrade*): se prueba antes en una copia restaurada.
- Una actualización o mantenimiento puede provocar **un corte breve** de conexiones: tu aplicación debe reintentar.

### 2.4 Alta disponibilidad (HA)

| Modo | Qué hace |
|---|---|
| Sin HA | Un único servidor; se repara solo, con más tiempo de recuperación |
| **Misma zona** | Standby en la misma zona de disponibilidad |
| **Redundante entre zonas** (*zone redundant*) | Standby en **otra zona**, replicación síncrona; protege contra la caída de una zona (SLA más alto) |

La conmutación es automática (suele tomar 1–2 minutos) y el nombre DNS se mantiene. El standby **no sirve lecturas** (para eso están las réplicas).

### 2.5 Réplicas de lectura
- Copias **asíncronas** (retraso medible) para repartir lecturas o hacer reportes sin molestar al primario; pueden estar en **otra región**.
- Se pueden **promover** a servidores independientes (útil para migraciones o DR manual).
- Hay un máximo por servidor (varias). Con réplicas existen **endpoints virtuales** para cambiar de servidor sin tocar las aplicaciones. *Verifica límites y disponibilidad.*

### 2.6 Copias y restauración
- Copias automáticas (instantánea + WAL): **PITR** con retención de **7 a 35 días**.
- **Copias geo-redundantes** opcionales (solo al crear el servidor) para restaurar en otra región.
- Restaurar **crea un servidor nuevo**; después decides cuál usar. También sirve como entorno de pruebas con datos reales (con cuidado de privacidad).

### 2.7 Red (la decisión más importante al crear el servidor)

| Opción | Cómo funciona | Cuándo |
|---|---|---|
| **Acceso privado (integración con VNet)** | El servidor vive **dentro de una subred delegada** con IP privada y zona DNS privada | Producción con red privada total. **No se puede cambiar después a público** |
| **Acceso público + Private Endpoint** | El servidor tiene endpoint público (cerrable) y puedes añadir un Private Endpoint | Flexibilidad; cerrar el público |
| **Acceso público + reglas de firewall** | Lista de IP permitidas | Desarrollo |

- Con integración VNet: subred delegada a `Microsoft.DBforPostgreSQL/flexibleServers` y una **zona DNS privada** que termina en `.postgres.database.azure.com`.
- **TLS** obligatorio por defecto (versión mínima configurable). En `sslmode` usa `require` o, mejor, `verify-full`.

### 2.8 Autenticación y autorización

| Método | Detalle |
|---|---|
| **PostgreSQL** | Usuario y contraseña (rol administrador al crear) |
| **Microsoft Entra ID** | El rol se mapea a una identidad (usuario, grupo, identidad administrada, entidad de servicio); el **token** de Entra se usa **como contraseña** |
| **Ambos** o solo Entra | Recomendado: **solo Entra** (`password_auth_enabled = false`) |

- Token con el ámbito `https://ossrdbms-aad.database.windows.net/.default`; **caduca (~1 hora)**: debe obtenerse **para cada conexión nueva**, no una vez al arrancar.
- Los roles de Entra se crean dentro de PostgreSQL con `SELECT * FROM pgaadauth_create_principal('id-api-pedidos', false, false);` y luego se les dan `GRANT` normales de PostgreSQL.
- Los **administradores de Entra** se configuran a nivel de servidor (de preferencia un grupo).

### 2.9 Extensiones y parámetros
- Las extensiones se **permiten** primero en el parámetro `azure.extensions` y luego se instalan con `CREATE EXTENSION`. Comunes: `pg_stat_statements`, `pgcrypto`, `uuid-ossp`, `pg_trgm`, `postgis`, `vector` (**pgvector**), `pg_cron`, `pg_partman`, `pgaudit`, `azure_ai`, `hypopg`, `pg_buffercache`. *Verifica la lista vigente por versión.*
- **Parámetros del servidor** (los que más se tocan): `max_connections` (límite según memoria del tamaño), `shared_buffers`, `work_mem`, `maintenance_work_mem`, `effective_cache_size`, `wal_level` (`logical` para CDC), `log_min_duration_statement`, `idle_in_transaction_session_timeout`, `statement_timeout`, `pgbouncer.enabled`, `pg_qs.query_capture_mode` (Query Store).

### 2.10 PgBouncer integrado
Un **agrupador de conexiones** (*connection pooler*) en el puerto **6432**. PostgreSQL crea un proceso por conexión: cientos o miles de conexiones desde muchos pods agotan memoria. PgBouncer mantiene pocas conexiones reales y reparte las del cliente.

| Modo | Cómo reparte | Cuidado |
|---|---|---|
| **session** | Una conexión real por sesión de cliente | Poca ganancia |
| **transaction** (el habitual) | Una conexión real solo durante cada transacción | Rompe cosas **de sesión**: `LISTEN/NOTIFY`, bloqueos consultivos de sesión, `SET` de sesión, cursores `WITH HOLD`; las sentencias preparadas dependen de la versión (en JDBC: `prepareThreshold=0` si falla) |

### 2.11 Rendimiento y diagnóstico
- **Query Store** y **Query Performance Insight:** historial de consultas y esperas.
- **`pg_stat_statements`:** consultas más costosas.
- **Ajuste inteligente** (índices, autovacuum): recomendaciones.
- **Autovacuum:** limpia versiones muertas de filas (MVCC). Tablas con muchas actualizaciones/borrados necesitan autovacuum agresivo.
- Índices: B-tree (por defecto), GIN (jsonb, arreglos, texto), GiST (geografía), BRIN (series temporales grandes), parciales y de expresión.

### 2.12 Funciones útiles para microservicios
- **`jsonb`** con índices GIN: documentos dentro de una fila.
- **`INSERT ... ON CONFLICT`** (upsert) para idempotencia.
- **`SELECT ... FOR UPDATE SKIP LOCKED`:** cola de trabajo/Outbox sin colisiones entre réplicas.
- **Particionamiento declarativo** de tablas por fecha.
- **Replicación lógica** (`wal_level=logical`) para CDC con Debezium hacia [Event Hubs](../../07-mensajeria/event-hubs-kafka/README.md).
- **pgvector:** búsqueda por similitud (recomendaciones, búsqueda semántica).
- **Clusters elásticos** (basados en Citus, para escalar horizontalmente): *verifica disponibilidad y madurez antes de adoptarlos*.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Datos transaccionales** de microservicios (pedidos, clientes, inventario) con relaciones y transacciones.
- **Portabilidad:** sin dependencia de un dialecto propietario; el mismo PostgreSQL en cualquier lugar.
- **Datos semiestructurados** (`jsonb`), **geográficos** (PostGIS) y **vectoriales** (pgvector) en el mismo motor.
- **Equipos con experiencia en PostgreSQL** y ecosistema open source (Debezium, Flyway, pgAdmin).
- **Costo moderado** (Burstable para desarrollo, paradas programadas).

| NO lo uses si | Alternativa |
|---|---|
| Dependes de funciones propias de SQL Server (T-SQL, Agent, CLR) | **Azure SQL** / Managed Instance |
| Necesitas escala masiva por clave con latencia mínima en varias regiones | **Cosmos DB** |
| Necesitas caché con TTL por clave | **Redis** |
| Guardas archivos | **Blob Storage** |
| Es una cola | **Service Bus / Storage Queue** (aunque `SKIP LOCKED` sirva para Outbox) |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Servidor flexible** | Instancia de PostgreSQL administrada con su DNS | `pg-modalima.postgres.database.azure.com` |
| **Burstable / GP / MO** | Familias de cómputo | `GP_Standard_D4ds_v5` |
| **HA zonal** | Standby sincronizado en otra zona | `ZoneRedundant` |
| **Réplica de lectura** | Copia asíncrona para lecturas | Reportes |
| **PITR** | Restaurar a un instante (7–35 días) | Antes de un `DELETE` |
| **WAL** | Registro de cambios; base de la replicación y PITR | `wal_level=logical` |
| **PgBouncer** | Agrupador de conexiones | Puerto 6432 |
| **Entra ID** | Autenticación con tokens, sin contraseña | `pgaadauth_create_principal` |
| **Extensión** | Funcionalidad adicional (pgvector, PostGIS) | `CREATE EXTENSION vector` |
| **MVCC / autovacuum** | Versiones de filas / limpieza automática | Tablas con muchas actualizaciones |
| **`SKIP LOCKED`** | Salta filas bloqueadas por otros | Cola de trabajo |
| **`jsonb`** | JSON binario indexable | `data @> '{"vip":true}'` |
| **Integración con VNet** | Servidor con IP privada en subred delegada | Acceso privado |
| **Ventana de mantenimiento** | Día/hora de parches | Domingo 03:00 |

---

## 5. Cómo se usa

1. **Decide la red antes de crear:** acceso privado (VNet) o público + Private Endpoint. Es la decisión más difícil de cambiar.
2. **Crea el servidor:** versión principal reciente, cómputo General Purpose (Burstable en desarrollo), HA redundante entre zonas en producción, **Entra ID only**, retención PITR ≥ 14 días, ventana de mantenimiento.
3. **Permite extensiones** (`azure.extensions`) y activa `pg_stat_statements` / Query Store.
4. **Crea la base y los roles:** un rol por aplicación mapeado a su identidad (`pgaadauth_create_principal`), `GRANT` mínimos, `ALTER DEFAULT PRIVILEGES`.
5. **Versiona el esquema** con Flyway/Liquibase ejecutado por una identidad de migración (propietaria de los objetos).
6. **Conecta desde Java:** `pgjdbc` + **token de Entra como contraseña obtenido en cada conexión nueva**; Hikari con `max-lifetime` < vida del token; `sslmode=verify-full`.
7. **Usa PgBouncer** (6432) si tienes muchos pods; ajusta `prepareThreshold`.
8. **Escala lecturas** con réplicas; **DR** con réplica entre regiones o copias geo-redundantes.
9. **Observa:** CPU, memoria, almacenamiento, conexiones activas y fallidas, retraso de réplica, consultas lentas, bloat/autovacuum.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/postgresql-flexible.sh) · [SQL](ejemplos/sql/) · [KQL](ejemplos/kql/kql-postgresql.md).

---

## 6. Seguridad

- **Entra ID only** (`password_auth_enabled = false`); sin contraseñas que filtrar ni rotar.
- **Red:** integración con VNet o Private Endpoint; **acceso público deshabilitado** en producción.
- **TLS:** `ssl_min_protocol_version` ≥ TLS 1.2; en el cliente `sslmode=verify-full`.
- **Cifrado en reposo:** clave administrada por Microsoft o **clave propia** (CMK) en Key Vault.
- **Mínimo privilegio en la base:** el rol de la aplicación **no es propietario** de los objetos; el rol de migraciones sí; los analistas, solo `SELECT`.
- **Auditoría:** extensión **pgaudit** + registros a Log Analytics; **Defender for open-source relational databases** (verifica el nombre vigente).
- **Seguridad a nivel de fila** (RLS) para multi-inquilino.
- **Consultas parametrizadas** siempre.
- **Copias:** retención PITR suficiente; geo-redundantes si el negocio lo exige; **prueba restauraciones**.

### IAM de este servicio

| Plano | Quién | Qué hace | Rol/permiso mínimo |
|---|---|---|---|
| **Control** (Azure RBAC) | Plataforma/IaC | Crear y configurar servidores | *Contributor* acotado o rol personalizado |
| **Control** | Seguridad | Auditoría, red, claves | *Contributor* con alcance al servidor + roles de Key Vault para CMK |
| **Control** | Lectura | Ver configuración | *Reader* |
| **Datos** (dentro de PostgreSQL) | Aplicación (identidad administrada) | Leer y escribir | Rol de Entra (`pgaadauth_create_principal`) + `GRANT SELECT, INSERT, UPDATE, DELETE` sobre su esquema |
| **Datos** | Pipeline de migraciones | Cambiar esquema | Rol de Entra **propietario** de los objetos (o miembro del rol dueño) |
| **Datos** | Analistas | Solo lectura | Grupo de Entra + `GRANT SELECT` (o `pg_read_all_data` según política) |
| **Datos** | Administradores | Administración | Administrador Entra del servidor (grupo) |

> El rol *Contributor* de Azure **no** da acceso a los datos: los permisos de datos son roles y `GRANT` de PostgreSQL.

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Elegir **la red al inicio**; Entra ID only; identidad administrada por aplicación.
- **Token por conexión nueva** y `max-lifetime` del pool menor que la vida del token.
- **PgBouncer** con muchos pods; pool pequeño por pod.
- `INSERT ... ON CONFLICT` para idempotencia; `SKIP LOCKED` para colas internas/Outbox.
- Índices guiados por `pg_stat_statements`/Query Store; `EXPLAIN (ANALYZE, BUFFERS)` antes de indexar.
- Migraciones versionadas, compatibles hacia atrás, con identidad dueña.
- Monitorear **autovacuum**, conexiones y retraso de réplica.
- Probar actualizaciones de versión principal en una copia restaurada.
- `statement_timeout` y `idle_in_transaction_session_timeout` razonables.

**Qué NO hacer**
- Usar el administrador de la base para la aplicación.
- Dejar el token obtenido una sola vez al arrancar (caduca).
- Abrir cientos de conexiones directas desde muchos pods.
- Transacciones largas (retrasan el autovacuum y causan *bloat*).
- Dar a la aplicación el rol propietario o `SUPERUSER`-like.
- Usar `SELECT *` o `OFFSET` enorme.
- Instalar extensiones sin permitirlas ni probar versiones.
- Depender de funciones de sesión (`LISTEN/NOTIFY`, `SET`) a través de PgBouncer en modo transacción.
- Elegir acceso público "por ahora" si necesitas red privada: no podrás cambiar después.
- Ignorar el crecimiento: el almacenamiento no se reduce.

---

## 8. Límites, costos y versiones
- **Costo:** cómputo por hora (se detiene al parar el servidor), almacenamiento, IOPS adicionales (Premium SSD v2), copias fuera del espacio incluido, réplicas, HA (duplica cómputo y almacenamiento del standby). *Verifica precios y reservas.*
- **Límites:** `max_connections` según memoria del tamaño, tamaño máximo de almacenamiento, número de réplicas, regiones con zonas. *Verifica la tabla vigente.*
- **Versiones:** PostgreSQL 14–18; driver `pgjdbc` (gestionado por Spring Boot 4.1) o `quarkus-jdbc-postgresql`; extensiones por versión.
- **Cambios frecuentes:** funciones nuevas (clusters elásticos, SSD v2, endpoints virtuales, PgBouncer) evolucionan rápido: confirma disponibilidad antes de diseñar.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
