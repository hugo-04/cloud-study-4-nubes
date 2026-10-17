# Oracle OCI · Datos · Autonomous Database

Base de datos Oracle administrada que se parchea, respalda, ajusta y escala sola. Eliges el tipo de carga (transaccional, *data warehouse*, JSON, APEX), los OCPU/ECPU y el almacenamiento; Oracle hace el resto. Para microservicios suele usarse **Autonomous Transaction Processing (ATP)** en infraestructura compartida (serverless).

## 1. Qué es

**Analogía:** un auto con chofer y mecánico incluidos. Tú dices a dónde ir (tus consultas) y cuánta prisa tienes (servicio de conexión); el mantenimiento, los cambios de aceite (parches) y el seguro (respaldos) vienen incluidos.

```
 App Java (pool UCP/Hikari) ──TLS──► endpoint privado de la ADB (subred privada, NSG)
                                        ├─ servicio TP / TPURGENT  (OLTP, alta concurrencia)
                                        ├─ servicio LOW / MEDIUM / HIGH (reportes, paralelo)
                                        ├─ respaldos automáticos (60 días) + clones
                                        └─ Autonomous Data Guard (standby en otro AD/región)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Tipo de carga** | `OLTP` (ATP), `DW` (ADW), `AJD` (JSON), `APEX` |
| **Cómputo** | ECPU (modelo actual) u OCPU; **autoescalado** hasta 3× *(verifica)* |
| **Servicios de conexión** | `tp`, `tpurgent`, `low`, `medium`, `high`: prioridad y paralelismo distintos |
| **TLS** | Mutuo (wallet) u one-way (sin wallet, requiere lista de acceso o endpoint privado) |
| **Endpoint privado** | IP en tu subred; la base no queda expuesta a Internet |
| **Lista de control de acceso** | IPs/VCN permitidas si el endpoint es público |
| **Respaldos** | Automáticos, recuperación a un punto en el tiempo |
| **Autonomous Data Guard** | Standby local o entre regiones; *failover* automático o manual |
| **Clones** | Copia completa o de metadatos para pruebas |

### Conexión desde Java
1. Obtén el *connect string* del perfil (por ejemplo `tp` con TLS de un solo sentido).
2. URL JDBC: `jdbc:oracle:thin:@(description=(retry_count=20)(retry_delay=3)(address=(protocol=tcps)…))`.
3. Usuario de aplicación propio (no `ADMIN`) y contraseña desde [Vault](../../03-secretos/README.md).
4. Pool de conexiones con validación; los reintentos de conexión ya van en el *connect string*.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Pedidos, pagos e inventario con SQL y transacciones | **ATP** |
| Analítica y reportes pesados | **ADW** o servicio `low/medium/high` |
| Documentos JSON con SQL | **AJD** o ATP con colecciones JSON |
| Equipo sin DBA dedicado | **Autonomous** |
| App diseñada para MySQL o PostgreSQL | [MySQL HeatWave](../mysql-heatwave/README.md) / [PostgreSQL](../postgresql/README.md) |
| Clave-valor masivo de latencia de un dígito | [NoSQL](../nosql/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **ECPU** | Unidad de cómputo facturable de Autonomous |
| **Servicio TP** | Para transacciones cortas y muchas sesiones |
| **Wallet** | Archivo con certificados para TLS mutuo |
| **TLS one-way** | Cifrado sin wallet (el servidor se identifica) |
| **Data Guard** | Copia en espera lista para tomar el control |

## 5. Cómo se usa
1. ATP con endpoint privado, TLS one-way y Data Guard: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Elige el perfil de conexión correcto desde el SDK: [uso en Java](uso-en-java.md).
3. Estado, perfiles y clones: [`ejemplos/cli/adb.sh`](ejemplos/cli/adb.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| DBA/plataforma | `manage autonomous-database-family` | Usuario `ADMIN` (guardado en Vault, uso excepcional) |
| App (lectura del perfil) | `read autonomous-databases` | Usuario propio con privilegios mínimos |
| Auditoría | `read` + Data Safe | Auditoría de la base |

- Endpoint **privado**; NSG solo desde las subredes de apps.
- Un esquema/usuario por microservicio; nada de `ADMIN` en aplicaciones.
- Cifrado con llave propia de Vault si lo exige la normativa.
- Data Safe para evaluar usuarios, enmascarar datos en clones y auditar.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Servicio `tp` para OLTP | `high` para transacciones (limita sesiones) |
| Pool con tamaño acotado | Una conexión por petición |
| Usuario por servicio | Todos con `ADMIN` |
| Clones enmascarados para pruebas | Copiar datos reales a desarrollo |
| Autoescalado con alarma de costo | Autoescalado sin mirar la factura |

## 8. Límites, costos y versiones
- **Costo:** por ECPU-hora y por TB de almacenamiento; el autoescalado se cobra cuando se usa; hay ADB siempre gratis con límites *(verifica)*.
- **Límites** (verifica): sesiones por ECPU y servicio, almacenamiento máximo, retención de respaldos.
- **Terraform:** `oci_database_autonomous_database`, `oci_database_autonomous_database_wallet`.
- **SDK:** `DatabaseClient` (`oci-java-sdk-database`); acceso a datos con el driver JDBC de Oracle (`ojdbc11`, UCP).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
