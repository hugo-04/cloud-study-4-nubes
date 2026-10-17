# AWS · Claim Check · Repaso

## Preguntas
1. ¿Qué viaja por la cola en Claim Check?
   - *Un ticket pequeño con la referencia (bucket, clave, versión, hash, tamaño…).*
2. ¿Por qué subir antes de publicar?
   - *Para que el consumidor nunca reciba una referencia a algo que aún no existe.*
3. ¿Para qué sirve `versionId`?
   - *Identificar la versión exacta e inmutable del objeto.*
4. ¿Por qué hace falta idempotencia?
   - *La entrega es al menos una vez; puede llegar duplicado.*
5. ¿Qué es el visibility timeout?
   - *El tiempo en que un mensaje recibido queda oculto para otros consumidores.*
6. ¿Cuándo no usar Claim Check?
   - *Cuerpos pequeños: añade piezas sin beneficio.*
7. ¿Qué riesgo de seguridad tiene un ticket?
   - *Apuntar a objetos ajenos: validar bucket y prefijo, rol mínimo.*
8. ¿Por qué no meter una URL prefirmada en el ticket?
   - *Caduca y se filtra por logs y DLQ.*
9. ¿Qué relación deben tener la retención del objeto y la DLQ?
   - *El objeto debe vivir más que la DLQ.*
10. ¿Cuándo usar evento de S3 y cuándo ticket explícito?
    - *Evento: subida directa simple. Ticket: necesitas hash, esquema y correlación propios.*

## Ejercicios
1. Diseña el ticket JSON para un lote CSV de 800 MB.
2. Escribe las políticas de IAM del productor y del consumidor.
3. Describe qué pasa si el consumidor muere a mitad del proceso (línea de tiempo).
4. Diseña la tabla de idempotencia (clave, estado, TTL).

## Autoevaluación
- [ ] Sé explicar el flujo completo con su orden.
- [ ] Sé implementar un consumidor idempotente y validar el ticket.
- [ ] Sé dimensionar visibility timeout y retenciones.
- [ ] Sé diagnosticar un `NoSuchKey` intermitente.
