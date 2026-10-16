# 09 · Bases de datos administradas

**Azure SQL Database**, **PostgreSQL Flexible Server** y **Cosmos DB**, con sus equivalentes en **AWS** (RDS, Aurora, DynamoDB), **OCI** (Autonomous Database, MySQL HeatWave, NoSQL) y **GCP** (Cloud SQL, AlloyDB, Spanner, Firestore).

---

## 1. Qué es (con analogía)

| Tipo | Analogía | Ejemplo |
|---|---|---|
| **Relacional (SQL)** | Un **archivador con fichas y relaciones** estrictas entre tablas | Pedidos, clientes, pagos |
| **Documento** | **Cajas etiquetadas** con todo lo de un cliente dentro | Catálogo, perfiles |
| **Clave-valor** | Un **casillero** con número: abres y sacas | Sesiones, carritos |
| **Caché (Redis)** | La **libreta** en tu escritorio para no ir al archivo | Respuestas repetidas |
| **Columnar / analítica** | Una **bodega** para análisis masivos | Reportes históricos |

Una base **administrada** significa que el proveedor se encarga de parches, respaldos, alta disponibilidad y hardware; tú modelas datos y consultas.

---

## 2. Para qué sirve y cuándo NO usarlo

| Necesito... | Elige |
|---|---|
| Transacciones, relaciones y consultas flexibles | **Relacional** (Azure SQL / PostgreSQL) |
| Escala masiva, baja latencia, acceso por clave | **NoSQL** (Cosmos DB / DynamoDB) |
| Respuestas instantáneas a lecturas repetidas | **Caché** |
| Análisis de grandes volúmenes | **Almacén analítico** (no la base transaccional) |

**Cuándo NO:** no uses NoSQL "porque escala" si tus datos son muy relacionales; no uses la base transaccional para reportes pesados; no uses un blob o una cola como base de datos.

---

## 3. Conceptos clave

| Término | Definición simple |
|---|---|
| **ACID** | Garantías de una transacción: Atómica, Consistente, Aislada, Durable |
| **Índice** | Atajo para buscar rápido; cuesta espacio y escrituras |
| **HA (alta disponibilidad)** | Réplica lista para tomar el control si falla la principal |
| **Réplica de lectura** | Copia para repartir consultas de lectura |
| **PITR** | *Point-in-time restore*: volver a un instante exacto |
| **Failover** | Cambio automático o manual a la réplica |
| **RPO / RTO** | Datos que puedes perder / tiempo que puedes estar caído |
| **vCore / DTU / RU/s** | Unidades con las que se paga la capacidad (Cosmos usa **RU/s**) |
| **Partición** | Reparto de datos para escalar (clave de partición) |
| **Consistencia** | Qué tan frescas son las lecturas (fuerte ↔ eventual) |
| **Connection pool** | Conjunto reutilizable de conexiones abiertas |
| **Migración de esquema** | Cambios versionados a las tablas (Flyway, Liquibase) |

---

## 4. Equivalencias en las 4 nubes

| Necesidad | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| SQL Server administrado | **Azure SQL Database** / Managed Instance | RDS for SQL Server | (en VM) | Cloud SQL for SQL Server |
| **PostgreSQL** administrado | **PostgreSQL Flexible Server** | RDS for PostgreSQL / **Aurora PostgreSQL** | OCI Database with PostgreSQL | Cloud SQL for PostgreSQL / **AlloyDB** |
| MySQL administrado | Database for MySQL Flexible | RDS MySQL / Aurora MySQL | **MySQL HeatWave** | Cloud SQL for MySQL |
| **Oracle Database** | Oracle Database@Azure / VM | RDS for Oracle | **Autonomous Database** / Exadata | Oracle Database@Google Cloud / Bare Metal |
| NoSQL global (documento/clave-valor) | **Cosmos DB** | **DynamoDB** | NoSQL Database Cloud Service | **Firestore** / Bigtable |
| Caché Redis | Azure Cache for Redis / Azure Managed Redis (verifica el servicio vigente) | ElastiCache / MemoryDB | OCI Cache | Memorystore |
| Relacional distribuido global | Azure SQL Hyperscale / Cosmos | Aurora (Global) | Autonomous (Data Guard) | **Spanner** |
| Almacén analítico | Synapse / Fabric | Redshift | Autonomous Data Warehouse | BigQuery |

### Diferencias reales

- **Cosmos DB** ofrece **varias APIs** (NoSQL, MongoDB, Cassandra, Gremlin, Table, PostgreSQL); DynamoDB tiene una sola.
- **Aurora** y **AlloyDB** son motores optimizados compatibles con PostgreSQL/MySQL, no el PostgreSQL "estándar".
- **Autonomous Database (OCI)** se **autoajusta** (índices, parches, escalado); es una propuesta distinta a las demás.
- **Spanner** da **SQL con consistencia fuerte y distribución global**, algo que ninguna otra nube iguala con exactamente el mismo modelo.
- **DynamoDB** y **Cosmos** se pagan por capacidad de **lecturas/escrituras** (RCU/WCU o RU/s), no por tamaño de máquina.

---

## 5. Azure SQL Database en detalle

### 5.1 Opciones

| Opción | Cuándo |
|---|---|
| **Single database** | Una base por aplicación (lo habitual) |
| **Elastic pool** | Muchas bases con picos en momentos distintos: comparten capacidad |
| **Managed Instance** | Migrar SQL Server con casi total compatibilidad |
| **Serverless** | Uso intermitente: pausa automática cuando no hay actividad |
| **Hyperscale** | Bases muy grandes con escalado de lectura |

Modelos de compra: **vCore** (recomendado) o DTU (paquete simple).

### 5.2 Seguridad y resiliencia

| Tema | Detalle |
|---|---|
| Autenticación | **Solo Entra ID** (sin usuario/clave de SQL) cuando sea posible |
| Red | Private Endpoint (`privatelink.database.windows.net`) y acceso público deshabilitado |
| Cifrado | TDE activo por defecto; opción de clave propia (CMK en Key Vault) |
| Auditoría y amenazas | Auditing y Microsoft Defender for SQL |
| HA | Redundancia de zona en los niveles que lo soportan |
| DR | Geo-replicación activa o **grupos de conmutación por error** |
| Backups | Automáticos, **PITR** (por defecto suelen ser 7 días, configurable hasta 35) y retención a largo plazo |

### 5.3 CLI

```bash
RG=rg-estudio-db
SQL=sql-modalima-estudio01

az group create -n $RG -l eastus2

# Servidor con administración solo por Entra ID
az sql server create -g $RG -n $SQL -l eastus2 \
  --enable-ad-only-auth \
  --external-admin-principal-type Group \
  --external-admin-name "DBAdmins" \
  --external-admin-sid <ID_DEL_GRUPO_EN_ENTRA>

# Base serverless que se pausa tras 60 minutos sin uso
az sql db create -g $RG -s $SQL -n tienda \
  --edition GeneralPurpose --family Gen5 --capacity 2 \
  --compute-model Serverless --auto-pause-delay 60 --min-capacity 0.5

# Cerrar el acceso público (después de crear el Private Endpoint)
az sql server update -g $RG -n $SQL --enable-public-network false

# Restaurar a un punto en el tiempo (por ejemplo, tras un DELETE sin WHERE)
az sql db restore -g $RG -s $SQL -n tienda --dest-name tienda-restaurada \
  --time "2026-10-16T14:30:00Z"
```
> Los parámetros varían por versión del CLI. Revisa `--help`.

### 5.4 Dar acceso a una aplicación (sin contraseñas)

Dentro de la base de datos (conectado como administrador Entra):

```sql
CREATE USER [app-modalima-api] FROM EXTERNAL PROVIDER;   -- nombre de la identidad administrada
ALTER ROLE db_datareader ADD MEMBER [app-modalima-api];
ALTER ROLE db_datawriter ADD MEMBER [app-modalima-api];
```
La aplicación se conecta con su identidad:

```
jdbc:sqlserver://sql-modalima-estudio01.database.windows.net:1433;
  database=tienda;encrypt=true;trustServerCertificate=false;
  hostNameInCertificate=*.database.windows.net;loginTimeout=30;
  authentication=ActiveDirectoryManagedIdentity
```
(Para una identidad *user-assigned*, añade `msiClientId=<CLIENT_ID>`.)

> Dar `db_owner` a la aplicación es un error común: **solo los permisos que necesita**.

---

## 6. PostgreSQL Flexible Server en detalle

| Tema | Detalle |
|---|---|
| Alta disponibilidad | Zone-redundant (réplica en otra zona) o misma zona |
| Acceso privado | **Dos modos**: integración con VNet (subnet **delegada**) **o** acceso público + Private Endpoint. Se elige al crear y condiciona el DNS |
| Backups | Automáticos con PITR (por defecto unos 7 días, configurable) |
| Réplicas de lectura | Sí |
| Conexiones | PgBouncer integrado (opcional) |
| Extensiones | Solo las permitidas (lista blanca) |
| Autenticación | Contraseña y/o Entra ID |

```bash
az postgres flexible-server create -g $RG -n pg-modalima-estudio01 -l eastus2 \
  --tier Burstable --sku-name Standard_B1ms --storage-size 32 \
  --version 16 \
  --vnet vnet-estudio --subnet snet-pg \
  --private-dns-zone privatelink.postgres.database.azure.com \
  --high-availability Disabled
```
> `--high-availability` y los tamaños dependen de la región y el tier. Para producción usa un tier de propósito general y HA con redundancia de zona.

### Spring Boot + HikariCP

```yaml
spring:
  datasource:
    url: jdbc:postgresql://pg-modalima-estudio01.postgres.database.azure.com:5432/tienda?sslmode=require
    username: ${DB_USER}
    password: ${DB_PASSWORD}      # viene de Key Vault, nunca del repositorio
    hikari:
      maximum-pool-size: 10
      minimum-idle: 2
      connection-timeout: 10000
      max-lifetime: 1500000       # menor que el cierre de conexiones inactivas del servidor
```

**Regla del pool:**
```
conexiones totales = nº de pods × maximum-pool-size   <   max_connections del servidor
```
Con 20 pods y un pool de 10 son **200 conexiones**. Si el servidor soporta 100, el sistema cae. Ajusta el pool o usa PgBouncer.

---

## 7. Cosmos DB en detalle

### 7.1 Modelo

```
Cuenta → Base de datos → Contenedor → Ítems (JSON)
                              │
                       Clave de partición (/clienteId)
```

| Concepto | Detalle |
|---|---|
| **RU/s** | Unidad de costo de las operaciones. Una lectura puntual de 1 KB cuesta ~1 RU |
| Modos de capacidad | **Aprovisionada**, **autoscale** o **serverless** |
| **Clave de partición** | Decide cómo se reparten los datos; **no se puede cambiar** después |
| Índices | Automáticos sobre todas las propiedades (se pueden afinar) |
| Change feed | Flujo ordenado de cambios (alimenta otros sistemas) |
| TTL | Expiración automática de ítems |
| Multi-región | Replicación global y escrituras multi-región |

### 7.2 Los 5 niveles de consistencia

| Nivel | Idea | Para qué |
|---|---|---|
| **Strong** | Siempre el dato más reciente | Datos críticos (más latencia) |
| **Bounded staleness** | Retraso acotado | Lecturas casi frescas con garantías |
| **Session** (por defecto) | Tú ves tus propias escrituras | **La mayoría de las aplicaciones** |
| **Consistent prefix** | Orden respetado | Casos con orden causal |
| **Eventual** | Puede estar desactualizado | Lo más barato y rápido |

### 7.3 Elegir bien la clave de partición

| Buena clave | Mala clave |
|---|---|
| Muchos valores distintos (`clienteId`) | Pocos valores (`pais`, `estado`) |
| Reparto parejo | Un valor domina (`fecha` de hoy) |
| Aparece en tus consultas más frecuentes | Casi nunca se usa para filtrar |

> Una consulta **sin** clave de partición recorre todas las particiones (*cross-partition*) y **cuesta muchas más RU**.

### 7.4 Java

```java
CosmosClient cliente = new CosmosClientBuilder()
    .endpoint("https://cosmos-modalima-estudio01.documents.azure.com:443/")
    .credential(new DefaultAzureCredentialBuilder().build())
    .consistencyLevel(ConsistencyLevel.SESSION)
    .buildClient();

CosmosContainer pedidos = cliente.getDatabase("tienda").getContainer("pedidos");

// Crear
pedidos.createItem(pedido, new PartitionKey(pedido.getClienteId()),
                   new CosmosItemRequestOptions());

// Lectura puntual (la más barata): id + clave de partición
CosmosItemResponse<Pedido> r =
    pedidos.readItem("pedido-123", new PartitionKey("cliente-42"), Pedido.class);
System.out.println("RU consumidas: " + r.getRequestCharge());
```

Con **Entra ID** (no claves), la identidad necesita un rol de **datos** propio de Cosmos (*Cosmos DB Built-in Data Reader/Contributor*), que se asigna con `az cosmosdb sql role assignment create`. Considera deshabilitar las claves locales de la cuenta.

### 7.5 CLI

```bash
az cosmosdb create -g $RG -n cosmos-modalima-estudio01 \
  --kind GlobalDocumentDB --default-consistency-level Session \
  --locations regionName=eastus2 failoverPriority=0 isZoneRedundant=False

az cosmosdb sql database create -g $RG -a cosmos-modalima-estudio01 -n tienda
az cosmosdb sql container create -g $RG -a cosmos-modalima-estudio01 -d tienda \
  -n pedidos --partition-key-path "/clienteId" --throughput 400
```

### 7.6 Errores 429

Un **429** significa que superaste los RU/s. El SDK reintenta según `Retry-After`. Si es frecuente: sube RU/s o autoscale, mejora la clave de partición, evita consultas entre particiones, o usa índices más selectivos.

---

## 8. Acceso privado y seguridad (lista de verificación)

| Control | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Sin IP pública | Private Endpoint / VNet integration | Subnets privadas + Security Groups | Endpoint privado en subnet privada | IP privada (private services access / PSC) |
| Sin contraseñas | Entra ID + identidad administrada | IAM database authentication | IAM / wallet mTLS (Autonomous) | IAM database authentication / Cloud SQL connectors |
| Gestión de secretos | Key Vault | Secrets Manager (con rotación) | Vault | Secret Manager |
| Cifrado con clave propia | CMK en Key Vault | KMS | Vault | CMEK |
| Pool de conexiones administrado | PgBouncer | **RDS Proxy** | — | Cloud SQL Auth Proxy / Connector |
| Auditoría | Auditing + Defender | CloudTrail + Database Activity Streams | Audit | Cloud Audit Logs |

Zonas DNS privadas en Azure: `privatelink.database.windows.net` (SQL), `privatelink.postgres.database.azure.com` (PostgreSQL), `privatelink.documents.azure.com` (Cosmos DB SQL). Recuerda enlazarlas a **todas** las VNets que consulten la base (módulo 02).

---

## 9. Alta disponibilidad y recuperación (resumen)

| | Azure SQL | PostgreSQL Flex | Cosmos DB | Equivalentes |
|---|---|---|---|---|
| Fallo de servidor | Réplica interna automática | HA con réplica en espera | Réplicas internas | RDS Multi-AZ, Cloud SQL HA |
| Fallo de zona | Redundancia de zona | HA entre zonas | Zonas redundantes | Aurora multi-AZ, regional HA |
| Fallo de región | Geo-replicación / failover groups | Réplica entre regiones | Multi-región | Aurora Global, DynamoDB Global Tables, Data Guard en OCI, réplica cross-region en GCP |
| Error humano | PITR | PITR | Backup continuo / restauración | PITR y snapshots |

> **HA no es backup.** La réplica copia también el `DELETE` accidental. Necesitas PITR o copias.

---

## 10. Migraciones de esquema

- Usa **Flyway** o **Liquibase** con scripts versionados en el repositorio.
- Cambios en **dos tiempos** (*expand / contract*):
  1. **Expandir:** agrega la columna nueva (compatible con la versión vieja de la app).
  2. Despliega la app nueva.
  3. **Contraer:** elimina lo viejo cuando ya nadie lo usa.
- No ejecutes migraciones destructivas en el arranque de **todos** los pods a la vez.

---

## 11. Casos de uso de vida real

### Caso 1 · Pedidos en Azure SQL con failover
- **Problema:** la base de pedidos de `ModaLima` era un punto único de falla.
- **Solución:** Azure SQL con redundancia de zona, grupo de conmutación por error a otra región y PITR.
- **Resultado:** una caída de zona pasó sin que nadie lo notara.
- **Lección:** diseña HA **y** recuperación; no son lo mismo.

### Caso 2 · Catálogo en Cosmos con la clave equivocada
- **Problema:** el catálogo usaba `/categoria` como clave; la categoría "ofertas" recibía el 70 % del tráfico y devolvía 429 mientras las demás estaban ociosas.
- **Solución:** clave sintética (`categoria` + hash del producto) y un contenedor para consultas por categoría.
- **Lección:** una partición caliente limita a toda la base.

### Caso 3 · "Too many connections"
- **Problema:** al escalar a 20 pods, PostgreSQL empezó a rechazar conexiones.
- **Causa:** 20 pods × pool de 20 = 400 conexiones, con un límite de 100.
- **Solución:** pool de 5 por pod y PgBouncer.
- **Lección:** escalar pods **multiplica** conexiones.

### Caso 4 · El `DELETE` sin `WHERE`
- **Problema:** un script en producción borró la tabla de promociones.
- **Solución:** restaurar a un punto 5 minutos antes en una **base nueva**, exportar la tabla y reinsertarla.
- **Lección:** restaura **a un lado**, no encima de producción, y valida antes de mover datos.

### Caso 5 · Base alcanzable desde internet
- **Problema:** un escaneo encontró el puerto 1433 abierto con una regla de firewall `0.0.0.0/255.255.255.255`.
- **Solución:** acceso público deshabilitado, Private Endpoint, autenticación solo Entra, y política que impide bases con acceso público (módulo 10).
- **Lección:** una regla "temporal" abierta es un incidente en espera.

---

## 12. Qué hacer / qué NO hacer

**Qué hacer**
- Acceso **privado** y autenticación **por identidad** (sin contraseñas).
- Habilitar **HA**, **backups** y **probar la restauración**.
- Modelar según las **consultas** (sobre todo en NoSQL).
- Dimensionar el **pool de conexiones** en función del número de pods.
- Reintentar con espera ante **errores transitorios**.
- Monitorear: CPU, almacenamiento, conexiones, RU, consultas lentas.
- Migraciones versionadas y compatibles hacia atrás.
- Etiquetar y poner presupuesto (las bases son de lo más caro).

**Qué NO hacer**
- Dejar `0.0.0.0` abierto o claves compartidas entre aplicaciones.
- Dar `db_owner`/administrador a las aplicaciones.
- Hacer `SELECT *` sin límites en tablas grandes.
- Usar la base transaccional para reportes pesados.
- Confundir HA con backup.
- Elegir clave de partición sin analizar las consultas.
- Probar la restauración **por primera vez** durante un incidente.
- Ejecutar scripts destructivos sin transacción y sin revisión.

---

## 13. Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Azure SQL error **40615** "Client with IP not allowed" | Firewall del servidor | Reglas de red del servidor | Private Endpoint o regla específica |
| Error **40613** "Database is not currently available" | Base pausada (serverless) o conmutación | Estado de la base | Reintentar con espera; considerar no usar auto-pausa |
| `Login failed for user '<token-identified principal>'` | La identidad no tiene usuario en la base | `CREATE USER … FROM EXTERNAL PROVIDER` hecho | Crear el usuario y asignar roles |
| El nombre resuelve a IP pública | Zona DNS privada sin enlazar | `nslookup` desde la app | Enlazar la zona (módulo 02) |
| Timeout desde AKS | NSG, ruta o DNS | `ConnCheck.java host 1433` | RPDSI (módulo 02) |
| PostgreSQL `remaining connection slots are reserved` | Demasiadas conexiones | Conexiones activas | Reducir pools, PgBouncer |
| PostgreSQL `SSL connection is required` | Falta `sslmode` | URL de conexión | `sslmode=require` |
| Consultas lentas | Falta de índice o plan malo | Query Store / `EXPLAIN` | Crear índice, reescribir consulta |
| Interbloqueos (deadlocks) | Transacciones largas en orden distinto | Gráfico de deadlock | Acortar transacciones, ordenar accesos |
| Cosmos **429** | Superaste RU/s | Métrica de RU y particiones calientes | Subir RU, mejorar clave, evitar cross-partition |
| Cosmos **403** con Entra | Falta rol de **datos** de Cosmos | Asignaciones de rol de datos | `az cosmosdb sql role assignment create` |
| Tras un failover la app sigue en la IP vieja | La JVM cachea el DNS | Propiedad `networkaddress.cache.ttl` | Fijar un TTL corto y usar el nombre del listener |

---

## 14. IAM del módulo

| Quién | Qué hace | Rol mínimo (Azure) |
|---|---|---|
| Equipo de plataforma | Crear servidores y bases | SQL DB Contributor / Cosmos DB Operator |
| Aplicación (SQL) | Leer/escribir datos | Usuario de base + `db_datareader`/`db_datawriter` |
| Aplicación (Cosmos) | Leer/escribir ítems | Cosmos DB Built-in Data Contributor (rol de datos) |
| Persona de soporte | Ver métricas | Monitoring Reader |
| Administrador de datos | Administrar la base | Administrador Entra de la base |

Equivalentes: `rds:*` acotado y usuarios con IAM auth en AWS, políticas `manage database-family` en OCI, `roles/cloudsql.client` y `roles/cloudsql.instanceUser` en GCP.

---

## 15. Repaso y entrevista

**Repaso**
1. ¿Cuándo eliges NoSQL en lugar de relacional?
2. ¿Qué es una clave de partición y por qué no se puede cambiar?
3. ¿Qué diferencia hay entre HA y backup?
4. ¿Por qué escalar pods puede tumbar la base de datos?
5. ¿Qué equivale a Cosmos DB en AWS, OCI y GCP?

**Entrevista**
- Diseña la base de datos de una tienda online con acceso privado y sin contraseñas.
- Un `DELETE` borró datos hace 10 minutos: ¿qué haces?
- Explica los niveles de consistencia de Cosmos con un ejemplo.
