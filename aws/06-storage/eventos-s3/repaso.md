# AWS · Eventos de S3 · Repaso

## Preguntas
1. ¿A qué destinos puede enviar S3 sus notificaciones?
   - *SQS, SNS, Lambda y EventBridge.*
2. ¿Qué ventaja tiene EventBridge sobre las notificaciones?
   - *Filtros ricos (tamaño, motivo), muchos destinos, archivo y reproducción.*
3. ¿Qué garantías de entrega hay?
   - *Al menos una vez, sin orden garantizado.*
4. ¿Para qué sirve el `sequencer`?
   - *Decidir cuál de dos eventos de la misma clave es más nuevo.*
5. ¿Cómo llega la clave en una notificación?
   - *Codificada como URL (`+` por espacio, `%XX`).*
6. ¿Qué es un bucle de recursión y cómo se evita?
   - *El consumidor escribe en el prefijo que lo dispara; separa entrada y salida.*
7. ¿Por qué el destino necesita una política con `SourceArn`?
   - *Para que solo ese bucket pueda publicar (evitar confused deputy).*
8. ¿Por qué poner SQS entre S3 y Lambda?
   - *Absorbe picos, reintenta y permite DLQ y concurrencia controlada.*
9. ¿Qué es `s3:TestEvent`?
   - *Mensaje de prueba que S3 envía al crear la notificación.*
10. ¿Cuándo no basta el evento?
    - *Si necesitas el contenido: descarga el objeto (Claim Check).*

## Ejercicios
1. Escribe la política de una cola que acepte solo eventos de tu bucket.
2. Define un patrón de EventBridge para PDF mayores de 1 MB en `facturas/`.
3. Decodifica `reportes/mi+informe+%C3%B1.pdf`.
4. Diseña la clave de idempotencia de un evento.

## Autoevaluación
- [ ] Sé elegir notificación o EventBridge.
- [ ] Sé evitar bucles, duplicados y órdenes invertidos.
- [ ] Sé configurar permisos del destino.
- [ ] Sé diagnosticar «no llegan eventos».
