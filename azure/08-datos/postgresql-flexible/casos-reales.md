# Azure · PostgreSQL Flexible Server · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · "Se acabaron las conexiones" con 40 pods
- **Problema:** `FATAL: remaining connection slots are reserved...` en horas pico; las APIs fallaban.
- **Causa:** 40 pods × pool de 20 = 800 conexiones; PostgreSQL crea un proceso por conexión y el servidor solo permitía unas 400.
- **Solución:** activar **PgBouncer** (puerto 6432, modo transacción), bajar el pool a 5 por pod y poner `prepareThreshold=0`; alerta de `active_connections`.
- **Lección:** en PostgreSQL las conexiones son caras: pocas reales y un agrupador en medio.

## Caso 2 · A la hora exacta de arrancar, todo fallaba (token vencido)
- **Problema:** una API funcionaba una hora y luego devolvía `password authentication failed`.
- **Causa:** el token de Entra se obtuvo **una vez** al arrancar y se puso como contraseña fija; caduca en ~1 hora y el pool abría conexiones nuevas con un token vencido.
- **Solución:** un `DataSource` que pide un token **por cada conexión física nueva** (o `CredentialsProvider` en Quarkus) y `max-lifetime` de 30 min.
- **Lección:** el token es una credencial con vida corta: se pide cuando hace falta.

## Caso 3 · El failover nocturno que nadie notó… excepto una API
- **Problema:** durante el mantenimiento de las 03:00, una API quedó caída 25 minutos.
- **Causa:** el pool conservaba conexiones muertas y no había reintentos; la otra API sí validaba conexiones y se recuperó sola.
- **Solución:** `keepalive-time`, `max-lifetime`, reintentos de SQLSTATE `57P01`/`08006` y prueba trimestral de conmutación forzada.
- **Lección:** la HA protege al servidor; la resiliencia del cliente protege a tu servicio.

## Caso 4 · Dos réplicas del mismo trabajo procesaban la misma tarea
- **Problema:** correos de confirmación duplicados cuando se escaló el trabajador a 3 réplicas.
- **Causa:** cada réplica hacía `SELECT ... WHERE estado='PENDIENTE'` y todas tomaban las mismas filas.
- **Solución:** `FOR UPDATE SKIP LOCKED` y estado `EN_CURSO` en la misma transacción; además, idempotencia por tarea.
- **Lección:** PostgreSQL sirve como cola/Outbox para volúmenes moderados si se usa `SKIP LOCKED`.

## Caso 5 · La tabla que pesaba 40 GB con 2 GB de datos (bloat)
- **Problema:** consultas cada vez más lentas y almacenamiento creciendo sin que crecieran los datos.
- **Causa:** una transacción abierta durante días impedía que el autovacuum limpiara versiones muertas de filas en una tabla con muchos `UPDATE`.
- **Solución:** cerrar la transacción huérfana, `idle_in_transaction_session_timeout=60s`, ajustar autovacuum por tabla y `VACUUM (ANALYZE)`; recuperar espacio con `pg_repack`.
- **Lección:** el almacenamiento **no se reduce** en Flexible Server: prevenir el bloat es más barato que curarlo.

## Caso 6 · El informe mensual que frenaba la tienda
- **Problema:** el reporte financiero tardaba minutos y subía la CPU del primario.
- **Solución:** **réplica de lectura** para reportes y rol `Analistas` con `statement_timeout` de 5 minutos; luego, exportación al lago para históricos.
- **Lección:** las réplicas son asíncronas: los reportes ven datos con segundos de retraso (aceptable) y no molestan a las escrituras.

## Caso 7 · Migrar desde Oracle/SQL Server… y la sorpresa de los índices
- **Problema:** tras migrar, una pantalla pasó de 80 ms a 4 s.
- **Causa:** faltaban índices equivalentes y un tipo `text` comparado con `varchar` sin índice parcial.
- **Solución:** `EXPLAIN (ANALYZE, BUFFERS)`, índice compuesto y parcial, y `pg_stat_statements` para vigilar.
- **Lección:** el rendimiento no se migra solo: se mide con el plan de ejecución.

## Caso 8 · Búsqueda por atributos dentro de `jsonb`
- **Problema:** el catálogo guardaba atributos variables (talla, color, material) y las búsquedas escaneaban toda la tabla.
- **Solución:** columna `jsonb` con **índice GIN** (`jsonb_path_ops`) y consultas con `@>`.
- **Lección:** `jsonb` da flexibilidad sin renunciar a índices; los atributos que se filtran siempre conviene volverlos columnas normales.

## Caso 9 · CDC de pedidos hacia el buscador
- **Problema:** el buscador de productos se alimentaba con trabajos nocturnos.
- **Solución:** `wal_level=logical`, **Debezium** lee los cambios y los publica en [Event Hubs](../../07-mensajeria/event-hubs-kafka/README.md) con la clave primaria como clave de partición; un consumidor idempotente actualiza el índice.
- **Cuidado:** la ranura de replicación retiene WAL: si el consumidor se detiene, **crece el almacenamiento**; monitoréala.
- **Lección:** CDC es potente, pero cada ranura es una responsabilidad operativa.

## Caso 10 · El rol de la aplicación era dueño de todo
- **Problema:** una aplicación comprometida pudo borrar tablas.
- **Causa:** usaba el rol administrador/propietario por comodidad.
- **Solución:** la identidad de **migraciones** es dueña; la aplicación recibe solo `SELECT/INSERT/UPDATE/DELETE` y `ALTER DEFAULT PRIVILEGES`; Entra ID only; auditoría con `pgaudit`.
- **Lección:** el rol de la aplicación nunca debe poder cambiar el esquema.

## Caso 11 · Elegir red pública "por ahora"
- **Problema:** meses después seguridad exigió red privada total.
- **Causa:** el servidor se creó con acceso público; **no se puede convertir** a integración con VNet.
- **Solución:** crear un servidor nuevo con subred delegada y migrar con restauración + replicación lógica.
- **Lección:** la red es la decisión más difícil de revertir; decídela primero.

## Caso 12 · Búsqueda semántica con pgvector
- **Problema:** buscar productos "parecidos" por descripción.
- **Solución:** extensión `vector`, columna `embedding vector(1536)` e índice `hnsw`; la API calcula el embedding y consulta `ORDER BY embedding <=> :q LIMIT 10`.
- **Lección:** para volúmenes moderados, vectores y datos transaccionales conviven en el mismo motor sin otro servicio.

## Caso 13 · Actualizar de versión sin sustos
- **Problema:** la versión 14 salía de soporte.
- **Solución:** restaurar una copia reciente a un servidor temporal, hacer la **actualización de versión principal** allí, correr las pruebas de la aplicación, medir planes de consulta y recién entonces actualizar producción en la ventana de mantenimiento.
- **Lección:** ensaya las actualizaciones sobre una copia con datos reales.
