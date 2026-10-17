# AWS · Kinesis Data Streams · Repaso

## Preguntas
1. ¿Qué es un shard y qué garantiza?
   - *La unidad de capacidad y de orden: el orden solo está garantizado dentro de un shard.*
2. ¿Cómo se elige el shard de un registro?
   - *MD5 de la clave de partición → rango de hash asignado a un shard.*
3. ¿Qué es un shard caliente y cómo se evita?
   - *Un shard saturado por claves mal repartidas; con claves de alta cardinalidad.*
4. ¿Qué diferencia hay entre bajo demanda y aprovisionado?
   - *Bajo demanda escala solo y se paga por uso; aprovisionado fija los shards y el costo.*
5. ¿Qué es la retención y qué permite?
   - *Cuánto tiempo se conservan los registros (24 h a 365 días); permite releer y reprocesar.*
6. ¿Consumidor compartido o fan-out mejorado?
   - *Compartido reparte 2 MiB/s por shard entre todos; fan-out da 2 MiB/s a cada consumidor.*
7. ¿Qué hace KCL?
   - *Reparte shards entre instancias, guarda checkpoints en DynamoDB y maneja el resharding.*
8. ¿Por qué comparar números de secuencia como número?
   - *Son cifras largas de longitud variable; como texto el orden sería incorrecto.*
9. ¿Qué hacer si `PutRecords` devuelve `FailedRecordCount > 0`?
   - *Reintentar solo los registros fallidos con espera creciente; descartar o desviar los errores definitivos.*
10. ¿Cuándo preferir SQS, SNS o Kafka en vez de Kinesis?
    - *SQS: cola de trabajo; SNS: fan-out simple; Kafka: ecosistema Kafka y control fino.*

## Ejercicios
1. Con 10 000 claves `idSesion` y 4 shards, calcula la distribución con el simulador y compara con la clave `pais`.
2. Escribe un productor que parta 1 200 registros en lotes ≤ 500 y ≤ 5 MiB y reintente solo los fallidos.
3. Levanta un consumidor KCL con una tabla de leases propia y mide el atraso.
4. Define una alarma de atraso > 5 min y una de throttling de escritura.

## Autoevaluación
- [ ] Explico cómo la clave de partición decide el shard y el orden.
- [ ] Distingo compartido vs. fan-out mejorado.
- [ ] Reintento por registro y comparo secuencias como números.
- [ ] Hago checkpoint después de procesar.
- [ ] Sé cuándo elegir Kinesis, SQS, SNS, EventBridge o Kafka.
