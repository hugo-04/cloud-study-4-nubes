# AWS · DynamoDB · Repaso

## Preguntas
1. ¿Qué es la clave de partición y para qué la clave de ordenación?
   - *La primera decide dónde vive el ítem; la segunda ordena los ítems de esa partición y permite rangos.*
2. ¿Qué diferencia hay entre `Query` y `Scan`?
   - *`Query` lee una partición por su clave; `Scan` recorre toda la tabla.*
3. ¿Bajo demanda o aprovisionado?
   - *Bajo demanda para empezar o carga impredecible; aprovisionado con auto scaling para carga estable.*
4. ¿Qué es una partición caliente y cómo se evita?
   - *Una clave que concentra el tráfico; con claves de alta cardinalidad y fragmentación.*
5. ¿Cuándo usar un GSI y qué advertencias tiene?
   - *Para un segundo patrón de acceso; es eventualmente consistente y tiene capacidad propia.*
6. ¿Cómo se implementa idempotencia?
   - *`PutItem` condicional con `attribute_not_exists` (y TTL para limpiar).*
7. ¿Cómo evitas la carrera de leer-modificar-escribir?
   - *Actualización atómica o condición de versión.*
8. ¿Cómo paginar resultados?
   - *Con `LastEvaluatedKey`; devolviendo un cursor opaco y firmado al cliente.*
9. ¿Qué garantías da el TTL?
   - *Borra eventualmente (hasta ~48 h); hay que comparar la caducidad al leer.*
10. ¿Cuándo NO usar DynamoDB?
    - *Consultas ad-hoc y joins (relacional), búsqueda de texto, objetos grandes (S3).*

## Ejercicios
1. Modela clientes, órdenes y un índice por estado con 4 patrones de acceso; escribe las consultas.
2. Implementa la reserva de stock con condición `stock >= :n` y prueba la concurrencia.
3. Crea una tabla de idempotencia con TTL y úsala desde un consumidor de SQS.
4. Pagina una consulta con cursor firmado y verifica que un cursor alterado se rechaza.

## Autoevaluación
- [ ] Diseño claves desde los patrones de acceso.
- [ ] Evito `Scan` y particiones calientes.
- [ ] Uso condiciones para idempotencia y versión.
- [ ] Reintento `UnprocessedItems` y sigo `LastEvaluatedKey`.
- [ ] Elijo entre DynamoDB, Aurora y ElastiCache con criterios.
