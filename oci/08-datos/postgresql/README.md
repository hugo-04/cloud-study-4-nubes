# Oracle OCI · Datos · OCI Database with PostgreSQL

PostgreSQL administrado con almacenamiento optimizado de OCI: los datos se guardan en una capa de almacenamiento distribuida y replicada entre dominios de disponibilidad, de modo que el *failover* no pierde datos y las réplicas de lectura no copian todo de nuevo. Tú eliges versión, forma y número de nodos; OCI parchea, respalda y vigila.

## 1. Qué es

**Analogía:** una biblioteca con un solo bibliotecario que presta y recibe libros (primario) y varios ayudantes que solo los muestran en sala (réplicas); todos trabajan sobre el mismo depósito central blindado (almacenamiento optimizado), así que si el bibliotecario se enferma, un ayudante asume sin perder ningún registro.

```
 Apps ──► endpoint primario (lectura/escritura) ──┐
      └─► endpoint de lectura (réplicas)          ├─► almacenamiento optimizado (replicado en 3 AD)
 DB system: 1 primario + N réplicas (forma flexible, versión 14/15/16…) + respaldos
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **DB system** | Clúster de 1 a N nodos (instancias) con la misma forma |
| **Primario** | Acepta escrituras; si falla, una réplica es promovida |
| **Réplicas** | Leen del almacenamiento compartido; detrás del **endpoint de lectura** |
| **Almacenamiento optimizado** | Volúmenes replicados entre AD; durabilidad independiente de los nodos |
| **Configuración** | Parámetros de PostgreSQL por conjunto (por ejemplo `max_connections`, `work_mem`) |
| **Respaldos** | Automáticos y manuales; restauración a un punto en el tiempo |
| **Extensiones** | Lista soportada (`pg_stat_statements`, `postgis`, `pgvector`… *verifica*) |

### Diferencias con un PostgreSQL en VM
- No hay acceso al sistema operativo ni superusuario real: un administrador con privilegios amplios.
- Las réplicas no usan replicación de flujo clásica: comparten almacenamiento; el retraso suele ser pequeño pero existe.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Microservicio con modelo relacional y extensiones de PostgreSQL | **PostgreSQL** |
| Búsqueda vectorial junto a datos relacionales | **PostgreSQL** con `pgvector` *(verifica)* |
| Muchas lecturas con tolerancia a milisegundos de retraso | Réplicas + endpoint de lectura |
| App hecha para MySQL | [MySQL HeatWave](../mysql-heatwave/README.md) |
| Necesitas una extensión no soportada o acceso al SO | **No**: PostgreSQL en VM/OKE |
| Clave-valor masivo | [NoSQL](../nosql/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Endpoint de lectura** | Una dirección que reparte entre réplicas |
| **Leer lo que escribí** | Tras escribir, leer del primario |
| **`sslmode=verify-full`** | Cifrado y verificación del nombre del servidor |
| **Pool de conexiones** | Conexiones reutilizadas; PostgreSQL sufre con miles de conexiones |
| **Migraciones** | Cambios de esquema versionados (Flyway) |

## 5. Cómo se usa
1. DB system con 2 nodos, respaldos y configuración: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Enruta lecturas y escrituras con consistencia «leer lo que escribí»: [uso en Java](uso-en-java.md).
3. Estado y endpoints: [`ejemplos/cli/postgresql.sh`](ejemplos/cli/postgresql.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage postgres-db-systems` (familia `postgres`) | Administrador (en Vault) |
| App | `read postgres-db-systems` | Rol propio con `GRANT` mínimos, dueño de su esquema |
| Auditoría | `read` | `pgaudit` si está disponible *(verifica)* |

- Subred privada + NSG 5432 desde las apps.
- TLS obligatorio con verificación del certificado.
- Un esquema y rol por microservicio; migraciones con un rol distinto al de ejecución.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Pools pequeños (PostgreSQL prefiere pocas conexiones activas) | 500 conexiones abiertas «por si acaso» |
| Leer del primario tras escribir | Mostrar datos de réplica justo después de guardar |
| Flyway con rol de migración | Que la app cree tablas en caliente |
| `pg_stat_statements` para encontrar consultas lentas | Optimizar a ciegas |
| Probar restauraciones | Confiar en respaldos sin probar |

## 8. Límites, costos y versiones
- **Costo:** por OCPU y memoria de cada nodo y por GB de almacenamiento optimizado; respaldos *(verifica)*.
- **Límites** (verifica): nodos por sistema, versiones soportadas, extensiones, almacenamiento máximo.
- **Terraform:** `oci_psql_db_system`, `oci_psql_configuration`, `oci_psql_backup`.
- **SDK:** `PostgresqlClient` (`oci-java-sdk-psql`); datos con el driver `postgresql` (JDBC) o `r2dbc-postgresql` (reactivo).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
