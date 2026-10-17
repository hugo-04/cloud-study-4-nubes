# AWS · RDS y Aurora · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. «Too many connections» en el Black Friday
**Qué pasó:** el catálogo escaló de 6 a 40 pods, cada uno con un pool de 20 conexiones: 800 conexiones contra una base que admitía ~500. Empezaron los `FATAL: too many connections`. **Solución:** dimensionar el pool (instancias × tamaño ≤ 80 % del máximo), bajar el pool a 5 y poner RDS Proxy delante. **Lección:** el pool se calcula contra la base, no «por si acaso».

## 2. El failover que duró cuarenta segundos… y cinco minutos en la app
**Qué pasó:** el escritor falló, Aurora promovió un lector en segundos, pero la aplicación seguía apuntando a la dirección vieja (nombre de instancia y caché DNS de la JVM) y devolvía `cannot execute INSERT in a read-only transaction`. **Solución:** conectar al endpoint de clúster, reducir el TTL de DNS de la JVM, usar el failover del AWS JDBC Wrapper y reintentar transacciones completas. **Lección:** ensaya el failover antes de que lo haga el azar.

## 3. «Acabo de pagar y no aparece»
**Qué pasó:** tras confirmar un pago, la pantalla consultaba el endpoint de lectura y el pedido aún no estaba (lag de réplica de unos cientos de ms). **Solución:** lecturas inmediatas posteriores a una escritura van al escritor; el resto, al lector. **Lección:** «lector» significa «puede ir un poco atrasado».

## 4. El `DELETE` sin `WHERE`
**Qué pasó:** un script de mantenimiento borró todas las filas de `pedidos` en producción. **Solución:** restauración a un punto en el tiempo (PITR) **a un clúster nuevo** dos minutos antes del error, comparación y copia de las filas perdidas. **Lección:** restaurar no «deshace»: crea otra base; practica el procedimiento y mide cuánto tardas.

## 5. Actualizar la versión mayor sin susto
**Qué pasó:** Café Andino debía pasar de PostgreSQL 14 a 16 con poco margen de corte. **Solución:** despliegue Blue/Green: se creó el entorno verde, se probó la aplicación contra él, y el *switchover* tardó menos de un minuto; el azul quedó un día como respaldo. **Lección:** prueba el cambio donde nadie lo sufre.

## 6. La contraseña rotó y la app no se enteró
**Qué pasó:** la contraseña administrada se rotó cada 7 días; la aplicación la leía una sola vez al arrancar y, al reciclar conexiones, empezó a fallar la autenticación. **Solución:** leer el secreto al crear conexiones nuevas (o usar autenticación IAM / RDS Proxy) y reintentar tras un fallo de autenticación refrescando el secreto. **Lección:** una credencial que rota exige un cliente que sepa refrescarla.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Conexiones agotadas | Cuenta del pool + RDS Proxy |
| 2 | App atascada tras failover | Endpoint de clúster + wrapper + reintento de transacción |
| 3 | Lectura de dato viejo | Escritor para «leer lo que acabo de escribir» |
| 4 | Borrado masivo | PITR a un clúster nuevo |
| 5 | Versión mayor | Blue/Green |
| 6 | Credencial rotada | Lectura del secreto por conexión / IAM / Proxy |
