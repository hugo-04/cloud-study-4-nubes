# NotebookLM · Azure · Azure SQL Database

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, CLI, SQL, KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure SQL Database, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es Azure SQL Database con la analogía del archivador atendido por un archivista; diferencia entre Database, Managed Instance y SQL Server en máquina virtual.
2. Servidor lógico y bases; modelos vCore y DTU; General Purpose, Business Critical e Hyperscale; serverless y elastic pools. Diagrama.
3. Alta disponibilidad, zonas, geo-replicación y grupos de conmutación por error; RPO y RTO.
4. Copias de seguridad: PITR, retención a largo plazo, redundancia y cómo se restaura.
5. Seguridad por capas: Entra ID solamente, usuarios contenidos, Private Endpoint, TDE y clave propia, Always Encrypted, enmascarado, seguridad a nivel de fila, auditoría, Defender y Ledger. Plano de control frente a plano de datos y roles mínimos.
6. Conexión desde Java: JDBC, ActiveDirectoryManagedIdentity, directivas Redirect y Proxy, errores transitorios y reintentos, dimensionado del pool.
7. Rendimiento: Query Store, ajuste automático, aislamiento por versiones de fila, gobernanza de recursos, índices, deadlocks.
8. Los 13 casos reales como historias con su lección: restauración tras un DELETE, cortes en un escalado, saturación de workers, plan regresado, contraseña filtrada, concurrencia optimista, Outbox, elastic pool, RLS, despliegue sin caída, serverless, réplicas de lectura y deadlocks.
9. Código Java: Spring Boot con JPA y @Version, JdbcClient con paginación por clave, reintentos, Outbox hacia Service Bus, RLS con SESSION_CONTEXT, WebFlux con JDBC en planificador elástico, R2DBC y sus límites, Quarkus imperativo y reactivo con Panache, Flyway y pruebas.
10. Ejemplos de Terraform, CLI, T-SQL y KQL; qué hacer y qué NO hacer; costos y límites.
11. Tabla de troubleshooting y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
