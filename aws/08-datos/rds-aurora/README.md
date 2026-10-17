# AWS · Datos · Amazon RDS y Aurora (bases relacionales administradas)

**RDS es el servicio que te da una base de datos relacional (PostgreSQL, MySQL, MariaDB, SQL Server, Oracle, Db2) ya instalada, respaldada, parchada y con alta disponibilidad; Aurora es la versión «nativa de la nube» de AWS, compatible con PostgreSQL y MySQL, con el almacenamiento repartido en tres zonas.** Tú diseñas tablas y consultas; AWS cuida los servidores, las copias y el reemplazo de hardware.

Este documento se centra en **RDS para PostgreSQL/MySQL y Aurora PostgreSQL/MySQL**, que cubren la mayoría de microservicios con Java.

## 1. Qué es

**Analogía:** un **archivo de oficina con un archivista de guardia**. Tú decides qué fichas guardar, cómo ordenarlas y quién puede abrir cada cajón; AWS cuida el edificio, hace copias cada día y, si el archivista se enferma, pone a otro en su lugar en segundos.

```
              Servicios (EKS / ECS / Lambda)
                        │
                 ┌──────▼───────┐        RDS Proxy: agrupa conexiones, acelera el failover
                 │  RDS Proxy   │
                 └──┬────────┬──┘
        escritura   │        │  lectura
     (cluster endpoint)    (reader endpoint)
          ┌─────────▼──┐  ┌──▼─────────┐  ┌────────────┐
          │ Writer AZ-a│  │ Reader AZ-b│  │ Reader AZ-c│     ← instancias (cómputo)
          └─────┬──────┘  └─────┬──────┘  └─────┬──────┘
                └───────────────┴───────────────┘
              Almacenamiento compartido de Aurora: 6 copias en 3 zonas (crece solo)
```

| Opción | Qué es | La eliges cuando |
|---|---|---|
| **RDS Multi-AZ (instancia)** | Una base + una réplica en espera síncrona en otra zona | Carga moderada, motores distintos de Aurora, costo contenido |
| **RDS Multi-AZ (clúster de BD)** | Escritor + dos réplicas legibles en 3 zonas (PostgreSQL/MySQL) | Quieres lecturas escalables y failover rápido sin Aurora *(verifica)* |
| **Aurora (provisionado)** | Clúster con escritor + hasta 15 lectores sobre almacenamiento compartido | Producción exigente: failover rápido, muchas réplicas, gran tamaño |
| **Aurora Serverless v2** | Aurora cuya capacidad (ACU) sube y baja sola | Cargas variables, entornos de desarrollo, picos impredecibles |
| **Aurora Global Database** | Clúster principal + secundarios en otras regiones | Lecturas locales en varias regiones y recuperación ante desastres regional |

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Instancia de BD** | El «motor» (CPU y memoria) de una clase (`db.r6g.large`, `db.t4g.medium`, `db.serverless`) |
| **Clúster de Aurora** | Conjunto de instancias (un escritor, varios lectores) que comparten un volumen |
| **Endpoints** | *Clúster* (siempre apunta al escritor), *lector* (reparte entre lectores), *instancia* (uno concreto), *personalizados*. **Usa clúster y lector, no instancias** |
| **Failover** | Si cae el escritor, un lector se promueve; el endpoint de clúster cambia de destino (DNS). Segundos a decenas de segundos *(verifica)* |
| **Grupo de subredes** | Subredes (mínimo dos zonas) donde puede vivir la base |
| **Grupo de parámetros** | Configuración del motor (`max_connections`, `rds.force_ssl`, `shared_buffers`…) |
| **Copias automáticas y PITR** | Respaldo diario + registros; restauras a **cualquier segundo** dentro de la retención (1–35 días). Restaurar crea **otra** base |
| **Instantáneas (*snapshots*)** | Copias manuales que duran hasta que las borres; base de clonados y migraciones |
| **Blue/Green** | Crea un entorno «verde» sincronizado para probar una actualización y hacer *switchover* en poco tiempo |
| **RDS Proxy** | Agrupa conexiones y las reutiliza; mantiene conexiones durante un failover; autentica con IAM o Secrets Manager |
| **Autenticación IAM** | Token de 15 minutos en lugar de contraseña; el usuario de BD se crea con rol `rds_iam` |
| **Contraseña administrada** | RDS crea y **rota** la contraseña maestra en Secrets Manager |
| **Cifrado** | En reposo con KMS (**se decide al crear**) y en tránsito con TLS |
| **Monitoreo** | Métricas de CloudWatch, Monitoreo mejorado (SO) y Performance Insights / Database Insights *(verifica el nombre vigente)* |
| **Mantenimiento** | Parches menores en una ventana que eliges; las versiones mayores las decides tú (Blue/Green) |
| **Escalado** | Vertical (cambiar clase), horizontal de lectura (réplicas), almacenamiento (autoescalable) |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Datos con relaciones, transacciones ACID, consultas flexibles | **RDS / Aurora** |
| Muchas lecturas que pueden tener segundos de retraso | **Aurora con lectores** (endpoint de lectura) |
| Cargas variables o entornos efímeros | **Aurora Serverless v2** |
| Cientos de funciones Lambda o pods con muchas conexiones | **RDS Proxy** delante |
| Clave-valor a escala enorme con latencia de milisegundos | [DynamoDB](../dynamodb/README.md) |
| Acelerar lecturas repetidas o guardar sesiones | [ElastiCache](../elasticache-redis/README.md) delante de la base |
| Eventos y colas | [Mensajería](../../07-mensajeria/README.md), no una tabla usada como cola |
| Archivos grandes (imágenes, PDF) | [S3](../../06-storage/s3/README.md); en la base solo la referencia |
| Analítica pesada sobre terabytes | No en la base transaccional: exporta a un almacén analítico (S3 + Athena, Redshift) |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Writer / Reader** | La instancia que escribe / las que solo leen |
| **Multi-AZ** | Copia lista en otra zona de disponibilidad |
| **PITR** | «Volver al segundo exacto» dentro de la retención |
| **RPO / RTO** | Cuánto dato puedes perder / cuánto puedes tardar en volver |
| **Pool de conexiones** | Conexiones abiertas reutilizadas por la aplicación |
| **`max_connections`** | Tope de conexiones simultáneas; depende de la memoria de la instancia |
| **Lag de réplica** | Retraso de un lector respecto al escritor |
| **ACU** | Unidad de capacidad de Aurora Serverless v2 (≈ 2 GiB de memoria + CPU asociada) |
| **Token IAM** | Contraseña temporal (15 min) que firmas con tu identidad |

## 5. Cómo se usa
1. Crea el clúster **cifrado**, en **subredes privadas**, sin acceso público, con **protección contra borrado**, copias de 7–35 días y contraseña administrada: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Abre el puerto (5432/3306) **solo** al grupo de seguridad de los servicios ([red](../../01-red/README.md)).
3. Crea los usuarios de aplicación (mínimo privilegio; con IAM: [`ejemplos/sql`](ejemplos/sql)) y las migraciones con Flyway.
4. Pon **RDS Proxy** si hay muchas instancias de aplicación, Lambda, o necesitas failover más suave.
5. En Java: **un pool por aplicación dimensionado** ([uso en Java](uso-en-java.md) trae la cuenta), reintentos de errores transitorios **alrededor de la transacción completa**, escrituras al endpoint de clúster y lecturas tolerantes al retraso al de lector.
6. Alarmas: CPU, conexiones, memoria libre, almacenamiento libre, lag de réplica; **ensaya un failover** antes de producción ([`ejemplos/cli/rds.sh`](ejemplos/cli/rds.sh)).

## 6. Seguridad

| Identidad | Plano de control (API de AWS) | Plano de datos (SQL) |
|---|---|---|
| **Aplicación** | — | Usuario de BD con mínimo privilegio; con IAM: `rds-db:connect` sobre `dbuser:<cluster-resource-id>/<usuario>` |
| **RDS Proxy** | Rol que lee el secreto (`secretsmanager:GetSecretValue`, `kms:Decrypt`) | Conexiones hacia la base |
| **Operación** | `rds:Describe*`, `rds:FailoverDBCluster`, `rds:CreateDBSnapshot`, restauraciones | — |
| **Pipeline** | `rds:CreateDBCluster`, `ModifyDBCluster`, `CreateDBInstance`… | Migraciones con usuario propio |

- **Red:** subredes privadas, `publicly_accessible = false`, grupo de seguridad por origen (no por CIDR amplio).
- **TLS obligatorio** (`rds.force_ssl=1` en PostgreSQL) y verificación del certificado con el paquete de AWS.
- **Cifrado en reposo:** no se puede activar después en una base existente (se restaura una copia cifrada).
- **Secretos:** contraseña administrada con rotación o autenticación IAM; nada de contraseñas en el código ([secretos](../../03-secretos/README.md)).
- **Registro:** exporta registros de PostgreSQL/MySQL a CloudWatch; cuida que no contengan datos personales.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Endpoints de clúster y lector | Conectar a una instancia concreta (falla al hacer failover) |
| Dimensionar el pool: instancias × tamaño ≤ ~80 % de `max_connections` | Pool de 20 en cada pod/función sin hacer la cuenta |
| RDS Proxy con Lambda o muchas réplicas de aplicación | Abrir una conexión por invocación |
| Reintentar errores transitorios envolviendo **toda** la transacción | Reintentar solo la sentencia fallida |
| Protección contra borrado + instantánea final + PITR probado | Confiar en copias que nunca restauraste |
| Contraseña administrada o IAM | Contraseña fija en una variable de entorno |
| Blue/Green para versiones mayores | Actualizar producción «a ver qué pasa» |
| Ensayar failover cada trimestre | Descubrir el comportamiento de la app durante el incidente |
| Leer de réplicas solo lo que tolera retraso | Leer de un lector justo después de escribir |
| Índices y revisión de consultas lentas | Subir de clase sin mirar las consultas |

## 8. Límites, costos y versiones
- **Costo:** horas de instancia (o ACU en Serverless v2) + almacenamiento + E/S (Aurora: estándar o *I/O-Optimized*) + copias por encima del tamaño de la base + transferencia entre zonas/regiones; RDS Proxy se cobra por vCPU de la base *(verifica precios y modalidades)*.
- **Límites** *(verifica)*: lectores por clúster (15), tamaño máximo de almacenamiento, `max_connections` por clase, retención de copias (35 días).
- **Versiones:** cada motor tiene su calendario de soporte; las versiones antiguas entran en soporte extendido con costo extra.
- **Terraform:** `aws_rds_cluster`, `aws_rds_cluster_instance`, `aws_db_subnet_group`, `aws_rds_cluster_parameter_group`, `aws_db_proxy`, `aws_cloudwatch_metric_alarm`. Validado con `init` + `validate`.
- **Java:** JDBC con HikariCP, **AWS Advanced JDBC Wrapper** (failover, autenticación IAM, separación lectura/escritura), R2DBC / cliente reactivo de Vert.x.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
