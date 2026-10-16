# Consultas de la API para NoSQL (lenguaje parecido a SQL)

Reglas de oro: (1) la lectura puntual (`id` + clave) siempre gana a una consulta; (2) incluye la **clave de partición** en el filtro (`WHERE c.clienteId = @clienteId`) o, desde el SDK, fíjala en las opciones de la consulta; (3) **parametriza**; (4) proyecta solo lo que necesitas (nada de `SELECT *` en rutas calientes); (5) mide `getRequestCharge()`.

Ejemplos sobre el contenedor `pedidos` (clave `/clienteId`, documento de [pedido-ejemplo.json](../json/pedido-ejemplo.json)).

## 1. Pedidos recientes de un cliente por estado (una sola partición, usa el índice compuesto)
```sql
SELECT c.id, c.estado, c.totalCentimos, c.creadoEn
FROM c
WHERE c.clienteId = @clienteId AND c.estado = @estado
ORDER BY c.estado ASC, c.creadoEn DESC
```
Índice compuesto necesario: `(/estado ASC, /creadoEn DESC)` (ver [politica-indexado.json](../json/politica-indexado.json)). Sin él, el `ORDER BY` con varios campos falla o es caro.

## 2. Proyección con `VALUE` (devuelve valores sueltos, no objetos)
```sql
SELECT VALUE c.id FROM c WHERE c.clienteId = @clienteId AND c.estado = "PAGADO"
```

## 3. Totales por cliente (agregados dentro de la partición)
```sql
SELECT COUNT(1) AS pedidos, SUM(c.totalCentimos) AS vendidoCentimos, AVG(c.totalCentimos) AS promedioCentimos
FROM c
WHERE c.clienteId = @clienteId AND c.tipo = "pedido"
```
Un agregado **sin** la clave recorre todas las particiones: útil para tableros, no para la ruta caliente.

## 4. `JOIN` dentro del mismo documento (aplana el arreglo de líneas)
```sql
SELECT c.id, l.sku, l.cantidad
FROM c
JOIN l IN c.lineas
WHERE c.clienteId = @clienteId AND l.sku = @sku
```
No existe `JOIN` entre documentos ni entre contenedores: se resuelve **incrustando** o consultando dos veces.

## 5. Buscar dentro de arreglos
```sql
SELECT c.id FROM c
WHERE c.clienteId = @clienteId AND ARRAY_CONTAINS(c.etiquetas, "vip")
```

## 6. Campos opcionales
```sql
SELECT c.id FROM c
WHERE c.clienteId = @clienteId AND NOT IS_DEFINED(c.referenciaExterna)
```

## 7. Subconsulta correlacionada (líneas caras)
```sql
SELECT c.id,
       ARRAY(SELECT VALUE l.sku FROM l IN c.lineas WHERE l.precioCentimos > 15000) AS skus_caros
FROM c
WHERE c.clienteId = @clienteId
```

## 8. Consulta entre particiones (fan-out) controlada
```sql
SELECT TOP 100 c.id, c.clienteId, c.totalCentimos
FROM c
WHERE c.estado = "PENDIENTE_PAGO" AND c.creadoEn < @limite
```
Revisa todas las particiones: ejecútala en trabajos de fondo, no por cada petición del usuario. Si es frecuente, **cambia el modelo** (un contenedor con otra clave, alimentado por el change feed).

## 9. Paginación
Usa el **token de continuación** del SDK (`iterableByPage(token, tamaño)`), no `OFFSET ... LIMIT` grande:
```sql
-- Evitar para páginas profundas: cada página repite el trabajo de las anteriores
SELECT c.id FROM c WHERE c.clienteId = @clienteId ORDER BY c.creadoEn DESC OFFSET 5000 LIMIT 50
```

## 10. Actualización parcial desde el SDK (patch), no con consultas
Cosmos no tiene `UPDATE`: se hace `replaceItem` (documento completo, con ETag) o `patchItem` con operaciones `set/add/replace/remove/incr`. Ver [uso en Java](../../uso-en-java.md) sección 3.

## 11. Cómo ver cuánto cuesta una consulta
- En el SDK: `FeedResponse.getRequestCharge()` por página (suma las páginas).
- En el portal: *Explorador de datos → Query Stats*.
- En los registros: tabla `CDBQueryRuntimeStatistics` y `CDBDataPlaneRequests` (ver [KQL](../kql/kql-cosmos.md)).
- Señales de mala consulta: muchas RU para pocos documentos devueltos, `OFFSET` alto, funciones en el filtro que impiden usar el índice (`WHERE LOWER(c.correo) = @x`: guarda el valor ya normalizado).

## 12. Búsqueda vectorial (si activas la capacidad)
```sql
SELECT TOP 10 c.id, c.nombre, VectorDistance(c.embedding, @consulta) AS distancia
FROM c
ORDER BY VectorDistance(c.embedding, @consulta)
```
Requiere definir una **política vectorial** y un **índice vectorial** en el contenedor al crearlo. *Verifica la capacidad, las funciones y los límites vigentes.*
