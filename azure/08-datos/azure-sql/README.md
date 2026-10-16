# Azure · Datos · Azure SQL Database (SQL Server administrado)

## 1. Qué es

**Azure SQL Database es el motor de SQL Server ofrecido como servicio: tú creas tablas y consultas; Microsoft se encarga de servidores, parches, respaldos, alta disponibilidad y reemplazo de hardware.** Es una base de datos **relacional** (tablas, claves, transacciones ACID, T-SQL). Forma parte de una familia llamada *Azure SQL*:

| Variante | Qué es | La eliges cuando |
|---|---|---|
| **Azure SQL Database** (base única o *elastic pool*) | Una base de datos como servicio, sin ver el servidor | Aplicaciones nuevas o modernizadas (lo habitual en microservicios) |
| **Azure SQL Managed Instance** | Una "instancia" SQL Server casi completa (Agent, CLR, *linked servers*, bases cruzadas) dentro de tu red | Migrar SQL Server existente con cambios mínimos |
| SQL Server en una VM | SQL Server tradicional en una máquina virtual | Necesitas control total del SO o funciones que ninguna variante PaaS ofrece |

Este documento se centra en **Azure SQL Database** (con notas de Managed Instance).

Analogía: **un archivador de oficina con fichas, cajones y llaves, atendido por un archivista de confianza**. Tú decides qué fichas guardar y quién puede abrir cada cajón; el archivista cambia las cerraduras, saca copias cada noche, tiene un archivador gemelo listo por si se incendia el primero y se asegura de que el mueble esté siempre en buen estado.

```
                          Servidor lógico  sql-modalima.database.windows.net:1433
                          (administración, firewall, Entra, auditoría, DNS)
                                              │
        ┌─────────────────────────────────────┼─────────────────────────────────────┐
        │                                     │                                     │
   Base "pedidos"                       Base "catalogo"                       Elastic pool "comparte"
   General Purpose                      Serverless (se pausa)                 ├ base cliente-A
   4 vCore                              0,5–4 vCore                           ├ base cliente-B
                                                                              └ base cliente-C  (comparten vCores)
        │
   Réplicas internas (HA), copias de seguridad (PITR / LTR), geo-réplica opcional → otra región
```

---

## 2. Cómo funciona por dentro

### 2.1 Servidor lógico y bases
- El **servidor lógico** (`Microsoft.Sql/servers`) **no es una máquina**: es un punto de administración con nombre DNS (`<servidor>.database.windows.net`), reglas de firewall, administrador Entra, auditoría, políticas de seguridad. Las **bases** cuelgan de él.
- Cada base tiene su propio recurso de cómputo y almacenamiento; el servidor no limita CPU.
- Puerto **1433** (TCP, TDS sobre TLS).

### 2.2 Modelos de compra y niveles

| Modelo | Detalle |
|---|---|
| **vCore** (recomendado) | Eliges núcleos y nivel de servicio; permite *serverless*, *reserved capacity* y ahorro por licencia |
| **DTU** | Paquete simple (Basic/Standard/Premium) que mezcla CPU, memoria y E/S; útil para pruebas pequeñas |

**Niveles de servicio (vCore)**

| Nivel | Arquitectura | Para qué |
|---|---|---|
| **General Purpose** | Cómputo con almacenamiento remoto; HA por reemplazo rápido | Mayoría de cargas de negocio |
| **Business Critical** | Réplicas locales con SSD (3–4 copias), **réplica de lectura gratuita** | Baja latencia de E/S, HA más rápida, lectura escalada |
| **Hyperscale** | Almacenamiento en *page servers* separado del cómputo; hasta 128 TB; réplicas con nombre | Bases muy grandes, restauraciones rápidas, escalar lectura |

**Cómputo:** *provisionado* (siempre encendido) o ***serverless*** (escala entre un mínimo y un máximo de vCores, factura por segundo y **se pausa** tras un periodo sin actividad; la primera conexión tras la pausa tarda).

**Elastic pool:** muchas bases comparten vCores/DTU; conviene cuando sus picos no coinciden (un SaaS con una base por cliente).

### 2.3 Alta disponibilidad (HA) y redundancia
- **Dentro de la región:** el servicio mantiene réplicas y reemplaza automáticamente un nodo fallido (sin acción tuya). **Redundancia de zona** (*zone redundant*) distribuye las réplicas en varias zonas de disponibilidad.
- **Entre regiones (DR):** **geo-replicación activa** (hasta 4 secundarias legibles) o **grupo de conmutación por error** (*failover group*): dos puntos de conexión estables (`<grupo>.database.windows.net` lectura-escritura y `<grupo>.secondary...` solo lectura) que siguen a la base tras un *failover*.
- Términos: **RPO** (cuántos datos puedes perder) y **RTO** (cuánto tiempo puedes estar caído). *Verifica los valores del SLA vigentes.*

### 2.4 Copias de seguridad y restauración
- Automáticas: completas, diferenciales y de registro de transacciones. Sin trabajo tuyo.
- **PITR (*point-in-time restore*):** volver a **cualquier instante** dentro de la retención (por defecto 7 días; configurable de 1 a 35).
- **LTR (*long-term retention*):** conservar copias semanales/mensuales/anuales hasta 10 años.
- **Redundancia del almacenamiento de copias:** local (LRS), zona (ZRS), geográfica (GRS) o zona-geográfica (GZRS).
- **Restaurar** crea **otra base** (no pisa la original): después decides cuál usar. También se puede restaurar una base eliminada dentro de la retención.

### 2.5 Seguridad: capas
| Capa | Control |
|---|---|
| Red | Firewall del servidor, **Private Endpoint** (`privatelink.database.windows.net`), acceso público deshabilitado, reglas de salida |
| Identidad | **Solo Entra ID** (sin usuario/clave SQL), administrador Entra (un grupo), **usuarios contenidos** para aplicaciones |
| Datos en reposo | **TDE** (cifrado transparente, activo por defecto), opcionalmente **clave propia** (CMK) en Key Vault |
| Datos en uso/columna | **Always Encrypted** (las claves nunca llegan al servidor), **enmascarado dinámico** (*dynamic data masking*), **seguridad a nivel de fila** (RLS) |
| Transporte | TLS (versión mínima configurable) |
| Vigilancia | **Auditoría** (a Log Analytics/Storage/Event Hubs), **Microsoft Defender for SQL**, evaluación de vulnerabilidades, **Ledger** (tablas a prueba de manipulación) |

### 2.6 Cómo se conectan las aplicaciones
- Cadena JDBC: `jdbc:sqlserver://<servidor>.database.windows.net:1433;database=<base>;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;`
- **Directiva de conexión:** *Redirect* (el cliente se conecta directo al nodo; requiere abrir el rango de puertos 11000–11999) o *Proxy* (todo por el puerto 1433 a través de una pasarela). **Con Private Endpoint la conexión usa Proxy.**
- **Autenticación sin contraseña desde Java:** `authentication=ActiveDirectoryManagedIdentity` (identidad administrada) o `ActiveDirectoryDefault` (cadena de credenciales de `azure-identity`: desarrollador local o Azure).
- **Errores transitorios:** durante *failover*, reconfiguración o escalado, la conexión puede caerse por segundos (códigos como 40613, 40501, 40197, 49918, 10928/10929). Toda aplicación debe **reintentar** consultas idempotentes y re-abrir conexiones; el *pool* debe validar conexiones.

### 2.7 Rendimiento
- **Query Store** (activado por defecto): historial de consultas, planes y estadísticas; permite **forzar un plan** estable.
- **Ajuste automático (*automatic tuning*):** forzar último plan bueno; crear/eliminar índices (opcional).
- **Procesamiento inteligente de consultas:** mejoras automáticas en planes.
- **Aislamiento de lectura confirmada con versiones de fila (RCSI):** activo por defecto en Azure SQL Database: las lecturas no bloquean a las escrituras.
- **Gobernanza de recursos:** límites de CPU, memoria, E/S de datos y de registro, *workers* y sesiones según nivel y tamaño. Al alcanzarlos: lentitud o errores (p. ej. 10928, 10929, 40501).
- **Índices:** el mejor ahorro de CPU; cuidado con índices de más (cuestan escrituras y espacio).

### 2.8 Esquema y migraciones
El esquema se versiona con **Flyway** o **Liquibase** (scripts `V1__crear_tablas.sql`). Las migraciones se ejecutan con una identidad distinta a la de la aplicación (la aplicación solo lee/escribe; el *pipeline* altera esquema).

### 2.9 Funciones útiles para microservicios
- **JSON** nativo (`OPENJSON`, `JSON_VALUE`, tipo `json` en versiones recientes): documentos dentro de una columna.
- **Tablas temporales con versión del sistema** (*temporal tables*): historial automático de cambios.
- **`rowversion`** para concurrencia optimista.
- **Secuencias** y columnas `IDENTITY`.
- **Change Tracking / CDC / Change Event Streaming:** exponer cambios (hacia [Event Hubs](../../07-mensajeria/event-hubs-kafka/README.md)). *Verifica disponibilidad por nivel.*
- **Service Broker** solo en Managed Instance (en Database no: usa un bus).

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Datos transaccionales con relaciones:** pedidos, clientes, pagos, inventario, facturación.
- **Consultas flexibles** (filtros, uniones, agregaciones) que cambian con el negocio.
- **Integridad fuerte:** claves foráneas, restricciones, transacciones ACID.
- **Equipos con experiencia en SQL Server/.NET/T-SQL**, o migración desde SQL Server local.
- **SaaS multi-cliente** con una base por cliente (elastic pool).

| NO lo uses si | Alternativa |
|---|---|
| Necesitas escala masiva por clave con latencia de milisegundos en el mundo | **Cosmos DB** |
| Tu stack y habilidades son PostgreSQL y no dependes de T-SQL | **PostgreSQL Flexible Server** |
| Quieres almacenar archivos grandes | **Blob Storage** |
| Haces análisis pesado sobre años de historia | Almacén/lago analítico |
| Datos de sesión o caché con TTL | **Redis** |
| Cola de mensajes | **Service Bus / Storage Queue** |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Servidor lógico** | Punto de administración con nombre DNS; no es una máquina | `sql-modalima.database.windows.net` |
| **vCore / DTU** | Unidades de cómputo (modelo moderno / paquete) | 4 vCore |
| **Serverless** | Escala y se pausa solo; factura por segundo | 0,5–4 vCore, pausa 60 min |
| **Elastic pool** | Capacidad compartida entre muchas bases | 50 bases de clientes |
| **Hyperscale** | Nivel con almacenamiento separado, hasta 128 TB | Base de 20 TB |
| **TDE** | Cifrado transparente en reposo | Activo por defecto |
| **PITR / LTR** | Restauración a un instante / retención de años | 35 días / 7 años |
| **Failover group** | Pareja de servidores con DNS estable | `fg-modalima` |
| **Usuario contenido** | Usuario que vive dentro de la base, no en el servidor | `[app-pedidos]` |
| **Entra ID only** | Solo identidades de Entra, sin contraseñas SQL | Sí |
| **Query Store** | Registro de consultas y planes | Forzar un plan |
| **RCSI** | Lecturas por versiones: lectores no bloquean escritores | Activo |
| **Interbloqueo (*deadlock*)** | Dos transacciones se esperan mutuamente; una se cancela | Error 1205 |
| **Error transitorio** | Falla breve que se resuelve reintentando | 40613 |
| **Directiva de conexión** | Redirect o Proxy | Proxy con Private Endpoint |

---

## 5. Cómo se usa

1. **Elige la variante y el nivel:** Database + vCore General Purpose (serverless en desarrollo/uso intermitente); Business Critical si necesitas E/S mínima latencia; Hyperscale para bases enormes.
2. **Crea el servidor** con **solo Entra ID**, administrador = grupo (`DBAdmins`), TLS mínimo 1.2, **acceso público deshabilitado** y **Private Endpoint**.
3. **Crea la base** con redundancia de zona (si el nivel lo soporta), retención PITR acorde y LTR si el negocio lo exige.
4. **Da acceso a las aplicaciones:** identidad administrada → `CREATE USER ... FROM EXTERNAL PROVIDER` + roles mínimos (`db_datareader`/`db_datawriter` o roles propios).
5. **Versiona el esquema** con Flyway/Liquibase ejecutado por el *pipeline* con una identidad de migración.
6. **Conecta desde Java** con el *driver* `mssql-jdbc`, `authentication=ActiveDirectoryManagedIdentity`, *pool* con validación y **reintentos de errores transitorios**.
7. **Activa auditoría y Defender;** diagnóstico a Log Analytics.
8. **Planifica DR:** failover group si el RTO/RPO lo exige; prueba el *failover* y la restauración.
9. **Observa:** CPU, E/S de datos y de registro, *workers*, conexiones fallidas, deadlocks, Query Store.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/azure-sql.sh) · [SQL](ejemplos/sql/) · [KQL](ejemplos/kql/kql-azure-sql.md).

---

## 6. Seguridad

- **Entra ID only:** `azuread_authentication_only = true`; sin `sa`, sin contraseñas.
- **Un grupo como administrador** (no una persona): rotación de personal sin tocar la base.
- **Aplicaciones con identidad administrada** y usuario contenido con **roles mínimos**; el *pipeline* de migraciones con otra identidad (`db_ddladmin`).
- **Red:** acceso público deshabilitado + Private Endpoint (zona `privatelink.database.windows.net`). Regla "permitir servicios de Azure" **desactivada** (abre a *cualquier* suscripción de Azure).
- **TDE** con clave de Microsoft o **CMK** en Key Vault ([Key Vault](../../03-secretos/key-vault/README.md)).
- **Datos sensibles:** Always Encrypted (columna), enmascarado dinámico, RLS para multi-inquilino.
- **Auditoría** a Log Analytics y **Defender for SQL**; revisa alertas de inyección SQL y accesos anómalos.
- **Consultas parametrizadas siempre** (prepared statements): evita inyección SQL.
- **Backups:** retención PITR y LTR; copias redundantes en zona/geografía; **prueba restauraciones**.

### IAM de este servicio

Hay **dos planos** con permisos distintos:

| Plano | Quién | Qué hace | Rol/permiso mínimo |
|---|---|---|---|
| **Control** (Azure RBAC) | Plataforma/IaC | Crear servidores y bases, configurar | *SQL DB Contributor* / *SQL Server Contributor* |
| **Control** | Seguridad | Auditoría, Defender, TDE | *SQL Security Manager* |
| **Control** | Lectura | Ver configuración | *Reader* |
| **Datos** (dentro de la base) | Aplicación (identidad administrada) | Leer y escribir | Usuario contenido + `db_datareader`, `db_datawriter` (o rol propio con `EXECUTE` en procedimientos) |
| **Datos** | Pipeline de migraciones | Cambiar esquema | Usuario contenido + `db_ddladmin` (y `db_datareader`/`db_datawriter` si siembra datos) |
| **Datos** | Analistas | Solo lectura | Grupo de Entra como usuario contenido + `db_datareader` |
| **Datos** | Administrador Entra (grupo) | Administración total | `DBAdmins` como administrador del servidor |

> El rol *Contributor* de Azure **no** da acceso a los datos. Los permisos de datos se otorgan **dentro de la base** con `CREATE USER ... FROM EXTERNAL PROVIDER`.

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Entra ID only + identidad administrada + roles mínimos.
- Private Endpoint y acceso público deshabilitado.
- **Reintentos** de errores transitorios y `pool` con validación y vida máxima de conexión.
- Consultas **parametrizadas** y paginación con `OFFSET/FETCH` (con orden estable).
- Índices guiados por Query Store; revisar planes regresados.
- Esquema versionado (Flyway) con identidad separada.
- Pruebas de restauración (PITR) y de *failover*.
- Serverless para desarrollo; reservas de capacidad para producción estable.
- Transacciones **cortas**; evitar mantener transacciones abiertas durante llamadas HTTP.
- Concurrencia optimista (`rowversion`/`@Version`) para actualizaciones concurrentes.

**Qué NO hacer**
- Dejar usuario/contraseña SQL o el "permitir servicios de Azure".
- Poner `SELECT *` sin límite o paginar con `OFFSET` enorme.
- Abrir una conexión por solicitud (usa pool).
- Una transacción que envuelve llamadas externas lentas.
- Ignorar el límite de *workers*/conexiones al escalar réplicas de pods (cada pod × pool de 10 = muchas conexiones).
- Dar `db_owner` a las aplicaciones.
- Usar la base como cola o como almacén de archivos.
- Cambiar el esquema a mano en producción.
- Confiar en que "serverless" no se pausa: la primera conexión tras la pausa tarda (configura *timeouts* y reintentos).

---

## 8. Límites, costos y versiones
- **Costo:** vCores (provisionado por hora, serverless por segundo de uso), almacenamiento, copias de seguridad (más allá del espacio incluido), LTR, réplicas, Defender. *Verifica precios, reservas y la oferta gratuita vigente.*
- **Límites:** tamaño máximo por nivel (General Purpose/Business Critical hasta unos 4 TB; Hyperscale hasta 128 TB), *workers*, sesiones, E/S, número de bases por servidor y por pool. *Verifica la tabla de límites vigente por tamaño de cómputo.*
- **Compatibilidad:** nivel de compatibilidad de la base (afecta funciones de T-SQL); tipos nuevos (p. ej. JSON nativo, vectores) pueden estar en vista previa o por región.
- **Driver:** `mssql-jdbc` reciente (gestionado por Spring Boot 4.1; en Quarkus, `quarkus-jdbc-mssql`).

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
