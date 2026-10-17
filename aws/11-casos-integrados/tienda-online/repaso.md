# AWS · Caso integrado · Tienda online · Repaso

## Preguntas
1. ¿Por qué no basta con `INSERT` seguido de `PutEvents`?
2. ¿Qué es la bandeja de salida y por qué va en la misma transacción?
3. ¿Qué significa «al menos una vez» y cómo se compensa?
4. ¿Por qué `PutEvents` con HTTP 200 puede haber fallado parcialmente?
5. ¿Qué ventaja tiene una cola + DLQ por consumidor?
6. ¿Cómo evita DynamoDB procesar dos veces el mismo mensaje?
7. ¿Para qué sirve `FOR UPDATE SKIP LOCKED`?
8. ¿Qué lleva el evento cuando el comprobante es un PDF?
9. ¿Qué alarmas pondrías y por qué esas?
10. ¿Cómo reproduces los eventos de ayer sin duplicar efectos?

## Respuestas
1. Si el proceso muere entre ambas, se pierde el aviso (o se inventa uno).
2. Tabla donde el servicio anota el evento junto con el dato; así ambos existen o ninguno.
3. Puede repetirse; se compensa con consumidores idempotentes (bandeja de entrada).
4. `PutEvents` devuelve un resultado por entrada; hay que mirar `FailedEntryCount` y cada `ErrorCode`.
5. Un mensaje venenoso o lento de uno no frena a los demás.
6. `PutItem` con `attribute_not_exists(idMensaje)`: el segundo intento falla y se descarta.
7. Para que varias réplicas del publicador tomen filas distintas sin bloquearse.
8. La referencia (bucket/clave/versión), no el archivo (Claim Check).
9. Antigüedad del mensaje más viejo, mensajes en DLQ, `FailedInvocations` y bandeja de salida pendiente.
10. Reproducción del archivo de EventBridge hacia el bus + consumidores idempotentes.

## Ejercicios
1. Añade el consumidor `antifraude` con patrón `total > 500`; ¿qué cambia en Terraform?
2. Escribe la consulta que mide cuántas filas de la bandeja llevan más de 5 minutos sin publicar.
3. Cambia la visibilidad a un valor menor que el procesamiento y observa los duplicados en una prueba local.
4. Diseña el evento `PedidoCancelado` con `version: 1` compatible con `PedidoCreado`.

## Autoevaluación
- [ ] Explico el riesgo de la doble escritura.
- [ ] Sé qué hace cada pieza de la bandeja de salida/entrada.
- [ ] Puedo diagnosticar «el evento no llegó» en el orden correcto.
