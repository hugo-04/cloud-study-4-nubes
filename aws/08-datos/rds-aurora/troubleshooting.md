# AWS · RDS y Aurora · Troubleshooting

Orden: **red (¿llego al puerto?) → autenticación (usuario, contraseña/token, TLS) → capacidad (conexiones, CPU, memoria, E/S, disco) → réplicas (lag, endpoint) → failover/mantenimiento → bloqueos y consultas lentas.**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `Connection timed out` / `refused` | Grupo de seguridad, subredes o base no accesible | `nc -vz <endpoint> 5432` desde el cliente; reglas del SG | Permitir el puerto desde el SG de la aplicación; misma VPC o ruta |
| `no pg_hba.conf entry … SSL off` | La base exige TLS | Parámetro `rds.force_ssl` | Conectar con `sslmode=verify-full` y el paquete de certificados |
| `password authentication failed` | Contraseña rotada, usuario equivocado | Secreto actual; fecha de rotación | Refrescar el secreto; releer por conexión |
| `PAM authentication failed` (IAM) | Token vencido (15 min), falta `rds-db:connect` o el usuario no tiene `rds_iam` | Política IAM; `\du` | Generar token por conexión; política y rol `rds_iam` |
| `too many connections` | Suma de pools > `max_connections` | Métrica `DatabaseConnections`; `show max_connections` | Redimensionar pools; RDS Proxy; subir de clase |
| `cannot execute … in a read-only transaction` | Conectado a un lector o al escritor viejo tras failover | `select pg_is_in_recovery()` | Endpoint de clúster; reducir TTL de DNS; wrapper de failover |
| Lecturas con datos viejos | Lag de réplica en el endpoint de lectura | Métrica `AuroraReplicaLag` / `ReplicaLag` | Leer del escritor lo recién escrito; reducir carga |
| CPU al 100 % | Consultas sin índice o picos | Performance Insights / `pg_stat_statements` | Índices; optimizar; escalar |
| `FreeableMemory` bajo / intercambio | Clase pequeña o demasiadas conexiones | Monitoreo mejorado | Menos conexiones; clase mayor |
| `FreeStorageSpace` bajo (RDS) | Datos o registros crecen | Métrica y tamaño por tabla | Autoescalado de almacenamiento; limpiar; rotación de registros |
| `deadlock detected` / `could not serialize access` | Orden de bloqueos distinto o aislamiento alto | Registro de errores (40P01 / 40001) | Orden consistente; reintentar la transacción entera |
| Transacciones en `idle in transaction` | Conexión con transacción abierta sin cerrar | `pg_stat_activity` | Tiempos límite (`idle_in_transaction_session_timeout`); cerrar bien las transacciones |
| Restauración «no devolvió mis datos» | Se restauró a otro clúster | Lista de clústeres | Cambiar el endpoint o copiar los datos; planificar el procedimiento |
| Mantenimiento inesperado | Ventana de parches menores | `describe-pending-maintenance-actions` | Fijar ventana; Multi-AZ; tolerar reinicios |
