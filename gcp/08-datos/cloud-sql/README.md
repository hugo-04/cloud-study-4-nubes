# Google Cloud · Datos · Cloud SQL

**PostgreSQL, MySQL o SQL Server administrados**: Google se ocupa de parches, respaldos, réplicas y alta disponibilidad regional; tú eliges la máquina, el almacenamiento y las banderas, y diseñas el esquema. Para Java, lo propio de Google es **cómo conectarse**: IP privada, **Cloud SQL Auth Proxy** o el **conector Java** (*socket factory*), idealmente con **autenticación IAM** en vez de contraseñas.

## 1. Qué es

**Analogía:** un departamento amoblado con conserjería: tú vives (datos y consultas); la administración arregla cañerías, hace copias de llaves y tiene un departamento espejo listo en otra zona.

```
 Cloud Run / GKE (SA app-pedidos)
   │  conector Java: socketFactory=com.google.cloud.sql.postgres.SocketFactory, enableIamAuth=true
   │  (TLS + autorización IAM, sin abrir la IP a nadie)
   ▼
 Instancia "pedidos-pg" (PostgreSQL 17, HA regional)
   ├── primaria  zona a ◀── réplica síncrona (standby) zona b
   ├── réplica de lectura (otra región, DR)
   └── IP privada (PSA) · respaldos automáticos + PITR
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Edición** | Enterprise o Enterprise Plus (más rendimiento, caché de datos, SLA mayor) *(verifica)* |
| **HA regional** | Standby en otra zona con disco replicado; conmutación automática |
| **Réplicas de lectura** | Asíncronas, en la misma u otra región; promovibles para DR |
| **Conectividad** | IP privada (PSA o PSC), IP pública con redes autorizadas (evítalo), Auth Proxy, conectores |
| **Autenticación IAM** | Usuarios de base mapeados a cuentas de servicio; el token reemplaza la contraseña |
| **Respaldos y PITR** | Automáticos y recuperación a un instante |
| **Mantenimiento** | Ventana definida por ti |
| **Query Insights** | Consultas lentas y planes |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Microservicio relacional típico (pedidos, pagos) | Cloud SQL |
| Escala horizontal global con consistencia fuerte | [Spanner](../spanner/README.md) |
| Documentos con sincronización a móviles | [Firestore](../firestore/README.md) |
| Series de tiempo masivas, clave-valor ancho | [Bigtable](../bigtable/README.md) |
| Caché de sesiones | [Memorystore](../memorystore/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Connection name** | `proyecto:región:instancia`, lo que usa el conector |
| **Auth Proxy / conector** | Túnel TLS autorizado por IAM |
| **IAM database auth** | Entrar con la identidad de la SA, sin contraseña |
| **PITR** | Volver a un minuto exacto |
| **max_connections** | Límite que tu pool total no debe superar |

## 5. Cómo se usa
1. Instancia privada con HA, IAM auth y usuario de la SA: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Conexión con el conector Java y cálculo de pools en [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/cloudsql.sh`](ejemplos/cli/cloudsql.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/cloudsql.admin` | — |
| App | `roles/cloudsql.client` + `roles/cloudsql.instanceUser` | Usuario IAM con `GRANT` mínimos en la base |
| DBA | `roles/cloudsql.editor` | Rol de base dedicado |

- Sin IP pública (política de organización `sql.restrictPublicIp`).
- `cloudsql.iam_authentication=on` y usuarios tipo `CLOUD_IAM_SERVICE_ACCOUNT`.
- CMEK y SSL obligatorio (`ssl_mode`).

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Conector o Auth Proxy con IAM | Contraseñas en variables de entorno |
| Pool pequeño × instancias ≤ `max_connections` | Pools de 50 en cada réplica de Cloud Run |
| HA + PITR en producción | Solo respaldos diarios |
| Migraciones versionadas (Flyway/Liquibase) | Cambios manuales en producción |
| `deletion_protection` | Borrar la instancia por un `destroy` |

## 8. Límites, costos y versiones
- **Costo:** vCPU + memoria por hora, almacenamiento, HA duplica el cómputo, respaldos y tráfico *(verifica)*.
- **Límites** (verifica): conexiones según memoria, tamaño de disco, réplicas por primaria.
- **Versiones:** PostgreSQL 13–17, MySQL 8.0/8.4 *(verifica)*.
- **Java:** `com.google.cloud.sql:postgres-socket-factory` (y `jdbc-socket-factory-core`); R2DBC tiene su propio conector.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
