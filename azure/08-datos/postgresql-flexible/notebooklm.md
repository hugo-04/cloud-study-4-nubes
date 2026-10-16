# NotebookLM · Azure · PostgreSQL Flexible Server

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, CLI, SQL, KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Database for PostgreSQL – Flexible Server, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de la biblioteca con un sistema abierto; servidor, bases, puertos 5432 y 6432.
2. Cómputo (Burstable, General Purpose, Memory Optimized), almacenamiento y su irreversibilidad, parar y arrancar, versiones y mantenimiento. Diagrama.
3. Alta disponibilidad entre zonas, réplicas de lectura, endpoints virtuales, copias y restauración PITR.
4. Red: acceso privado con subred delegada frente a acceso público y Private Endpoint, y por qué es la decisión más difícil de revertir.
5. Autenticación: Entra ID con token como contraseña, ciclo de vida del token, pgaadauth_create_principal, administradores y roles de la base.
6. Extensiones y parámetros: azure.extensions, pgvector, pg_cron, pgaudit; max_connections, work_mem, timeouts.
7. PgBouncer: qué problema resuelve, modos, qué rompe y cómo ajustarlo desde JDBC.
8. Rendimiento y diagnóstico: Query Store, pg_stat_statements, autovacuum y bloat, índices GIN y parciales, EXPLAIN.
9. Patrones en la base: upsert, SKIP LOCKED, bloqueos consultivos, LISTEN/NOTIFY, particionamiento, RLS, replicación lógica y CDC.
10. Seguridad e IAM: plano de control frente a plano de datos, rol dueño del esquema frente al de la aplicación, auditoría y cifrado.
11. Los 13 casos reales como historias con su lección: conexiones agotadas, token vencido, failover nocturno, tareas duplicadas, bloat, réplicas para reportes, migración, jsonb, CDC, roles, red pública, pgvector y actualización de versión.
12. Código Java: DataSource con token renovable, JPA con jsonb y @Version, JdbcClient con upsert y SKIP LOCKED, reintentos por SQLSTATE, R2DBC con token reactivo, Quarkus imperativo y reactivo con CredentialsProvider, Flyway y pruebas.
13. Ejemplos de Terraform, CLI, SQL y KQL; qué hacer y qué NO hacer; costos y límites.
14. Tabla de troubleshooting y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
