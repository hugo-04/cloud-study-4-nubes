# AWS · Lambda · Repaso

## Preguntas
1. ¿Qué es un arranque en frío?
   - *La primera ejecución de un entorno nuevo, que incluye Init (JVM, clases, clientes).*
2. ¿Por qué se crean los clientes SDK fuera del handler?
   - *Para reutilizarlos entre invocaciones.*
3. ¿Qué es `ReportBatchItemFailures`?
   - *Devolver solo los ids fallidos del lote SQS en vez de fallar todo.*
4. ¿Qué relación hay entre memoria y CPU?
   - *La CPU es proporcional a la memoria.*
5. ¿Qué hace SnapStart?
   - *Restaura una instantánea del entorno ya inicializado para acelerar el arranque.*
6. ¿Qué diferencia hay entre execution role y resource policy?
   - *Qué puede hacer la función vs. quién puede invocarla.*
7. ¿Qué relación deben tener el timeout y la visibilidad de la cola?
   - *Visibilidad ≥ 6 × timeout.*
8. ¿Para qué sirve la concurrencia reservada?
   - *Garantizar y limitar la concurrencia de una función.*
9. ¿Cuándo NO usar Lambda?
   - *Más de 15 min, conexiones persistentes o tráfico constante con latencia estable.*
10. ¿Cómo manejas el límite de payload?
    - *Claim Check: guardas el archivo en S3 y envías la referencia.*

## Ejercicios
1. Diseña timeout, visibilidad y `maxReceiveCount` para una función que tarda 20 s.
2. Escribe el procesamiento de un lote FIFO con fallos parciales.
3. Mide cuánto cuesta una función con 512 MB y 1 s frente a 1024 MB y 0,4 s.
4. Lista qué debe ser estático y qué no en un handler.

## Autoevaluación
- [ ] Sé reducir un cold start de Java.
- [ ] Sé diseñar fallos parciales e idempotencia.
- [ ] Sé coordinar timeout, visibilidad y DLQ.
- [ ] Sé separar permisos de ejecución y de invocación.
