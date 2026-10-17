# Google Cloud · Datos · Cloud SQL · Casos reales

## 1. «too many connections» en el Black Friday
**Qué pasó:** Cloud Run escaló a 80 instancias de pedidos de ModaLima y la base rechazó conexiones.
**Causa:** pool de 20 por instancia = 1 600 contra `max_connections` 800.
**Arreglo:** pool de 5, tope de instancias de Cloud Run y réplica de lectura para reportes.
**Lección:** el pool se multiplica por las instancias.

## 2. La contraseña en el repositorio
**Qué pasó:** una contraseña de Café Andino apareció en un commit.
**Causa:** cadena de conexión en `application.yml`.
**Arreglo:** autenticación IAM con el conector; borrar al usuario con contraseña.
**Lección:** sin contraseña no hay contraseña que filtrar.

## 3. El borrado de las 15:02
**Qué pasó:** un `DELETE` sin `WHERE` borró los pedidos del día.
**Causa:** error humano.
**Arreglo:** clon con PITR a las 15:01 y copia de las filas.
**Lección:** PITR activo y probado.

## 4. La conmutación que cortó 40 segundos
**Qué pasó:** en mantenimiento, la app dio errores un minuto.
**Causa:** el pool no reintentaba conexiones rotas.
**Arreglo:** validación de conexiones, reintentos y ventana de mantenimiento de madrugada.
**Lección:** HA reduce, no elimina, el corte.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Conexiones agotadas | Pool × instancias | Pool chico + tope |
| 2 | Secreto filtrado | Contraseña | IAM auth |
| 3 | Datos borrados | Error humano | PITR |
| 4 | Corte en conmutación | Pool sin reintento | Validación + reintento |
