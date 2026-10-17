# Oracle OCI · Datos · MySQL HeatWave

MySQL administrado por Oracle (el mismo motor de la comunidad, edición Enterprise) con un acelerador opcional, **HeatWave**: un clúster en memoria que ejecuta consultas analíticas sobre los mismos datos transaccionales, sin ETL. También ofrece alta disponibilidad, réplicas de lectura, respaldos y recuperación a un punto en el tiempo.

## 1. Qué es

**Analogía:** una cocina con un horno industrial al lado. La cocina normal (MySQL) prepara los pedidos del día; cuando llega un pedido de banquete (consulta analítica pesada), se pasa al horno industrial (HeatWave), que cocina cientos de platos a la vez sin desordenar la cocina.

```
 Apps (pool JDBC, TLS) ──► endpoint primario 10.0.6.10:3306 (lectura/escritura)
                       └─► endpoint de lectura (réplicas)
 DB system (forma MySQL.*, HA en 3 AD/FD, respaldos + PITR)
   └─ HeatWave cluster (N nodos en memoria) ── las consultas analíticas se descargan solas
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **DB system** | La instancia MySQL: forma, almacenamiento (crece solo), versión, configuración |
| **Alta disponibilidad** | Tres instancias en distintos AD/FD con replicación de grupo; *failover* automático |
| **Réplicas de lectura** | Copias asíncronas detrás de un **endpoint de lectura** |
| **HeatWave** | Clúster en memoria; el optimizador decide descargar consultas elegibles |
| **HeatWave Lakehouse/AutoML** | Consultar archivos de Object Storage y entrenar modelos en la base *(verifica disponibilidad)* |
| **Respaldos** | Automáticos con retención configurable + PITR |
| **Canales** | Replicación entrante/saliente con otros MySQL (migraciones) |
| **Configuración** | Conjunto de variables (por ejemplo `max_connections`) por forma |

### Conexiones
- Cada forma tiene un `max_connections` por defecto; **todas las réplicas de todos tus servicios** comparten ese total.
- El endpoint primario cambia de instancia en un *failover*, no de dirección: los clientes deben reconectar.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| App existente hecha para MySQL | **MySQL HeatWave** |
| OLTP + reportes sobre los mismos datos sin ETL | **MySQL + HeatWave** |
| Muchas lecturas que toleran segundos de retraso | Réplicas de lectura |
| Funcionalidades de PostgreSQL (extensiones, JSONB avanzado) | [PostgreSQL](../postgresql/README.md) |
| Clave-valor a escala masiva | [NoSQL](../nosql/README.md) |
| Sin DBA y SQL Oracle | [Autonomous](../autonomous-database/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **HA** | Si cae la instancia primaria, otra toma su lugar |
| **PITR** | Volver la base a un minuto exacto del pasado |
| **Descarga a HeatWave** | El optimizador manda la consulta al clúster en memoria |
| **`max_connections`** | Tope global de conexiones simultáneas |
| **Retraso de réplica** | Cuánto atrasa una réplica respecto del primario |

## 5. Cómo se usa
1. DB system con HA, respaldos, protección contra borrado y HeatWave: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Reparte `max_connections` entre servicios y réplicas y lee los endpoints reales: [uso en Java](uso-en-java.md).
3. Estado y endpoints: [`ejemplos/cli/mysql.sh`](ejemplos/cli/mysql.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage mysql-family` | Usuario administrador (en Vault) |
| App | `read mysql-db-systems` (descubrir endpoints) | Usuario propio con `GRANT` mínimos |
| Auditoría | `read mysql-family` | Plugin de auditoría |

- Solo endpoint **privado**; NSG 3306/33060 desde las apps.
- TLS obligatorio (`sslMode=VERIFY_IDENTITY` o `REQUIRED` según tus certificados).
- Un usuario por servicio; administrador solo para migraciones.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Calcular pools contra `max_connections` | Pools de 100 en cada réplica |
| HA en producción | Una sola instancia «porque es más barata» |
| Lecturas no críticas al endpoint de lectura | Leer el saldo recién escrito desde una réplica |
| `deletion_policy` con protección | Poder borrar la base con un `destroy` |
| Probar la restauración PITR | Confiar en respaldos nunca probados |

## 8. Límites, costos y versiones
- **Costo:** por hora de la forma (× 3 con HA), por GB de almacenamiento y respaldos, por nodo de HeatWave *(verifica)*.
- **Límites** (verifica): `max_connections` por forma, almacenamiento máximo, réplicas de lectura.
- **Terraform:** `oci_mysql_mysql_db_system`, `oci_mysql_heat_wave_cluster`, `oci_mysql_replica`.
- **SDK:** `DbSystemClient` (`oci-java-sdk-mysql`); datos con `mysql-connector-j`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
