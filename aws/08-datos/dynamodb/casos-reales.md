# AWS · DynamoDB · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El `Scan` que se comía el presupuesto
**Qué pasó:** la API «mis órdenes» hacía `Scan` con un filtro por cliente: 2 segundos y miles de lecturas por petición. **Solución:** rediseñar con `pk = CLIENTE#id` y `sk = ORDEN#fecha#id`; la petición pasó a un `Query` de pocos milisegundos. **Lección:** el filtro de un `Scan` se aplica *después* de leer y cobrar todo.

## 2. La partición caliente del día
**Qué pasó:** la clave de partición era la fecha: durante el Black Friday todas las escrituras iban a `2026-11-27` y se limitaban mientras el resto de la tabla estaba tranquila. **Solución:** clave `FECHA#hora#shard` con un sufijo repartido y consulta en paralelo por los fragmentos; para lo demás, claves por cliente. **Lección:** una buena clave reparte el tráfico, no lo concentra.

## 3. Dos cajeros, un stock
**Qué pasó:** dos instancias leían el inventario (10), restaban 1 y escribían 9, perdiendo una venta. **Solución:** actualización atómica `SET stock = stock - :n` con condición `stock >= :n`, y bloqueo optimista con atributo de versión para el resto. **Lección:** leer-modificar-escribir sin condición es una carrera.

## 4. El mensaje que se procesó dos veces
**Qué pasó:** SQS entregó dos veces el mismo mensaje y se emitieron dos facturas. **Solución:** tabla de idempotencia con `PutItem` condicional (`attribute_not_exists(pk)`) y TTL a 7 días; si la condición falla, el mensaje ya se procesó. **Lección:** la idempotencia es una escritura condicional.

## 5. «Lo acabo de guardar y el índice no lo ve»
**Qué pasó:** tras crear una orden, la pantalla consultaba un GSI y no aparecía. Además, un GSI con poca capacidad empezó a limitar las escrituras de la tabla base. **Solución:** leer de la tabla base cuando se necesita consistencia, dimensionar el GSI como la tabla y vigilar sus métricas. **Lección:** los GSI son eventualmente consistentes y tienen su propia capacidad.

## 6. Las sesiones que no caducaban
**Qué pasó:** con TTL de 30 minutos, los usuarios seguían «con sesión» horas después: el borrado por TTL no es exacto. **Solución:** comparar siempre `expira_en` con la hora actual al leer (y dejar que TTL solo limpie). **Lección:** TTL ahorra espacio; no es un temporizador de seguridad.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | `Scan` caro | Diseño por patrón de acceso + `Query` |
| 2 | Partición caliente | Clave repartida (fragmentos) |
| 3 | Carrera de stock | Actualización atómica condicional + versión |
| 4 | Doble procesamiento | `PutItem` condicional + TTL |
| 5 | GSI atrasado/limitando | Lectura de la tabla base + capacidad del GSI |
| 6 | TTL "tarde" | Comparar la caducidad al leer |
