# Azure · PostgreSQL Flexible Server · Repaso

## Preguntas de repaso
1. ¿Qué es PostgreSQL Flexible Server en una frase?
   - *PostgreSQL de la comunidad como servicio administrado: servidor con bases, extensiones y parámetros, con parches, copias y HA a cargo de Azure.*
2. ¿En qué se diferencia de Azure SQL?
   - *Aquí hay un servidor con parámetros y puerto 5432; el motor es PostgreSQL (portable); la autenticación Entra usa tokens como contraseña.*
3. ¿Qué opciones de red hay y cuál es irreversible?
   - *Acceso privado (VNet integrada) o público (+ Private Endpoint/firewall). Un servidor público no se convierte a VNet integrada.*
4. ¿Cómo funciona la alta disponibilidad?
   - *Standby síncrono (misma zona o entre zonas), conmutación automática en 1–2 min; el standby no sirve lecturas.*
5. ¿Qué son las réplicas de lectura?
   - *Copias asíncronas para lecturas/reportes, incluso entre regiones; se pueden promover.*
6. ¿Cómo se autentica una aplicación sin contraseña?
   - *Identidad administrada, rol creado con `pgaadauth_create_principal`, token de Entra como contraseña obtenido por cada conexión nueva.*
7. ¿Por qué falla la aplicación después de una hora?
   - *El token se pidió una sola vez y caducó.*
8. ¿Qué es PgBouncer y qué rompe?
   - *Agrupador de conexiones (6432); en modo transacción rompe `LISTEN/NOTIFY`, bloqueos de sesión y `SET` de sesión; las sentencias preparadas pueden requerir `prepareThreshold=0`.*
9. ¿Cómo habilito una extensión?
   - *La permito en `azure.extensions` y luego `CREATE EXTENSION`.*
10. ¿Para qué sirve `FOR UPDATE SKIP LOCKED`?
    - *Para que varias réplicas tomen tareas distintas de una tabla-cola sin pisarse.*
11. ¿Qué es el bloat y cómo se evita?
    - *Versiones muertas de filas sin limpiar; autovacuum, transacciones cortas y `idle_in_transaction_session_timeout`.*
12. ¿Se puede reducir el almacenamiento?
    - *No; por eso hay que prevenir el crecimiento innecesario.*
13. ¿Cómo se restaura una base?
    - *PITR (7–35 días) crea un servidor nuevo; después decides cuál usar.*
14. ¿Qué rol debe ser dueño del esquema?
    - *La identidad de migraciones; la aplicación solo tiene `GRANT` de datos.*
15. ¿Cómo hago CDC?
    - *`wal_level=logical` + Debezium hacia Event Hubs; vigilando las ranuras de replicación.*
16. ¿Cuándo prefiero Azure SQL?
    - *Cuando dependo de T-SQL, Agent, CLR o de un ecosistema SQL Server/.NET.*

## Entrevista
- Diseña la base de pedidos para 40 pods con picos. ¿Pool, PgBouncer, réplicas, HA, red?
- Una API falla exactamente una hora después de arrancar. ¿Qué pasó y cómo se arregla en Spring y en Quarkus?
- La tabla `pedido` ocupa 40 GB con 2 GB de datos. ¿Qué investigas?
- ¿Cómo implementas una cola de trabajo con PostgreSQL y qué límites tiene?
- ¿Cómo lo protegerías para un auditor de seguridad?

## Ejercicio práctico
1. Despliega el [Terraform](ejemplos/terraform/main.tf) en `dev`.
2. Ejecuta [01-roles-y-permisos.sql](ejemplos/sql/01-roles-y-permisos.sql) y [02-esquema-pedidos.sql](ejemplos/sql/02-esquema-pedidos.sql).
3. Conecta una aplicación Spring Boot con el `DataSource` que renueva el token; compruébalo con `max-lifetime` de 2 minutos.
4. Activa PgBouncer y compara conexiones y latencia con 40 clientes simulados.
5. Implementa la cola con `SKIP LOCKED` y ejecuta 3 trabajadores.
6. Crea una réplica de lectura y mide el retraso.
7. Provoca una transacción larga y observa el efecto con [04-diagnostico.sql](ejemplos/sql/04-diagnostico.sql).
8. Restaura a un punto en el tiempo después de un `DELETE` accidental.
