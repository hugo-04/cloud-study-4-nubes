# Azure · 08 Datos

Dónde viven los datos de los microservicios. Regla de oro: **cada servicio es dueño de su base de datos** (nadie más la toca directamente) y **eliges el motor por la forma de los datos y de las consultas, no por costumbre**.

| Servicio | Modelo | Analogía | La eliges para |
|---|---|---|---|
| [Azure SQL Database](azure-sql/README.md) | **Relacional** (SQL Server, T-SQL) | Archivador con fichas, cajones y llaves | Pedidos, pagos, facturación: transacciones ACID, integridad, informes con SQL |
| [PostgreSQL Flexible Server](postgresql-flexible/README.md) | **Relacional** (PostgreSQL, extensiones) | Archivador abierto con muchos complementos | Lo mismo que SQL, con ecosistema abierto: JSONB, PostGIS, pgvector, Flyway/Liquibase |
| [Cosmos DB (NoSQL)](cosmos-db/README.md) | **Documentos JSON** repartidos por clave | Bodega con casilleros etiquetados | Escala masiva por clave, baja latencia global, esquemas flexibles, change feed |
| [Redis (Azure Managed Redis)](redis/README.md) | **Clave-valor en memoria** | Mesa de trabajo: rápida, pequeña y volátil | Caché, sesiones, límites de tasa, bloqueos, reservas rápidas |

## Árbol de decisión

```
¿Los datos son la ÚNICA copia y deben ser correctos pase lo que pase?
   ├─ ¿Hay relaciones, transacciones entre varias tablas, informes con JOIN?
   │     ├─ ¿Tu equipo/ecosistema es SQL Server (T-SQL, SSMS, Managed Instance)?  → Azure SQL
   │     └─ ¿Prefieres PostgreSQL (extensiones, JSONB, código abierto)?            → PostgreSQL Flexible
   └─ ¿Acceso casi siempre por una clave (cliente, pedido), volumen/escala muy altos,
      documentos con forma variable, o multirregión de escritura?                    → Cosmos DB

¿Es un dato que puedes RECONSTRUIR y necesitas leerlo en microsegundos-milisegundos?
   └─ → Redis (caché, sesión, límite, bloqueo), con la verdad en una de las bases de arriba

¿Son archivos, imágenes o PDF? → no es una base de datos: Blob Storage (capítulo 06)
¿Es un flujo de eventos que se debe releer? → Event Hubs / Kafka (capítulo 07)
```

## Comparativa

| Característica | Azure SQL | PostgreSQL Flexible | Cosmos DB (NoSQL) | Redis |
|---|---|---|---|---|
| Modelo | Tablas | Tablas (+ JSONB) | Documentos JSON | Clave-valor y estructuras |
| Lenguaje | T-SQL | SQL (PostgreSQL) | SQL de Cosmos (sobre JSON) | Comandos Redis (+ Lua) |
| Transacciones | ACID completas | ACID completas | ACID **dentro de una partición lógica** | Atómicas por comando/script |
| Joins y consultas ad hoc | **Sí** | **Sí** | Limitado (dentro del documento/partición) | No |
| Escala | Vertical + lectura en réplicas; hiperescala | Vertical + réplicas de lectura | **Horizontal automática** por clave de partición | Vertical + shards (clúster) |
| Cobro | vCore/DTU (o sin servidor) | vCore + almacenamiento | **RU/s** (o sin servidor) + almacenamiento | Por SKU/hora |
| Latencia típica | ms | ms | ms de un dígito (lectura puntual) | sub-ms a pocos ms |
| Durabilidad | Alta (copias, HA, geo) | Alta (copias, HA, geo) | Alta (réplicas, copia continua) | **Volátil** salvo persistencia opcional |
| Esquema | Rígido (migraciones) | Rígido (migraciones) | Flexible (tú lo versionas) | Sin esquema |
| Distribución global | Failover groups / geo-réplicas | Réplicas entre regiones | **Multirregión nativa** | Geo-replicación activa |
| Autenticación sin claves | Entra ID | Entra ID | Entra ID + roles de datos | Entra ID |
| Uso típico | Pedidos, pagos, ERP | Pedidos, catálogo, geoespacial | Carrito, perfil, eventos, catálogo masivo | Caché, sesiones, límites |

## Patrones de combinación (los que ves en proyectos reales)

| Patrón | Cómo se combinan | Para qué |
|---|---|---|
| **Cache-aside** | SQL/PostgreSQL/Cosmos + Redis | Leer rápido lo que se repite; la verdad queda en la base |
| **Outbox transaccional** | Base relacional (o Cosmos con lote transaccional) + Service Bus | Cambiar datos y publicar el evento sin doble escritura |
| **CQRS / proyecciones** | Escritura en SQL/PostgreSQL → eventos → lectura en Cosmos (o Cosmos change feed → proyecciones) | Consultas de lectura rápidas con otra forma de los datos |
| **Base por servicio** | Cada microservicio con su propia base (o esquema aislado con credenciales propias) | Independencia de despliegue y de modelo |
| **Persistencia políglota** | SQL (pedidos) + Cosmos (carrito/catálogo) + Redis (sesión) | Cada dato en el motor que mejor le calza |
| **Claim Check** | Base guarda la referencia; el archivo vive en Blob | Evitar filas/documentos enormes |

## Reglas transversales
- **Entra ID antes que contraseñas/claves:** Azure SQL y PostgreSQL con autenticación de Entra, Cosmos con `disableLocalAuth`, Redis con claves de acceso desactivadas.
- **Private Endpoint** con su zona DNS privada en producción (`privatelink.database.windows.net`, `privatelink.postgres.database.azure.com`, `privatelink.documents.azure.com`, `privatelink.redis.azure.net`) y acceso público cerrado.
- **Migraciones de esquema versionadas** (Flyway/Liquibase) en las bases relacionales; en Cosmos, versión de esquema dentro del documento.
- **Idempotencia** en todo lo que reintente (claves únicas, `Idempotency-Key`, ETag).
- **Diseñar para que la caché falle**: Redis es una optimización, no la fuente de verdad.
- **Copias y recuperación probadas**: restauración a un instante (SQL, PostgreSQL, Cosmos con copia continua) con un simulacro real.
- **Dinero en enteros (céntimos) y fechas en ISO-8601 UTC** en cualquier motor.
- **Alertas** en CPU/RU/memoria, conexiones, almacenamiento y replicación.

## Cómo se relacionan con otros capítulos
- [Red · Private Endpoint y DNS](../01-red/private-endpoint-dns/README.md): conectividad privada a las bases.
- [IAM · Managed Identity](../02-iam/managed-identity/README.md) y [Workload Identity](../02-iam/workload-identity/README.md): acceso sin claves desde App Service, Functions, AKS y Container Apps.
- [Secretos · Key Vault](../03-secretos/README.md): claves administradas por el cliente (CMK) y secretos que aún sean necesarios.
- [Mensajería](../07-mensajeria/README.md): Outbox, change feed → Service Bus, CDC → Event Hubs.
- [Storage](../06-storage/README.md): archivos en Blob y Claim Check.
- Gobierno *(por escribir)*: políticas que exigen Private Endpoint, Entra ID y copias.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, consultas, KQL y los específicos de cada servicio), troubleshooting, repaso y prompt de NotebookLM.
