# Transversal · Quarkus · Repaso

## Preguntas
1. ¿Qué significa que Quarkus haga trabajo en build time?
2. ¿Dónde corre un endpoint que retorna `Uni` y uno que retorna un tipo normal?
3. ¿Qué pasa si bloqueas el event loop?
4. ¿Qué tres formas hay de hacer I/O bloqueante sin dañar el event loop?
5. ¿Para qué sirve `@ConfigMapping`?
6. ¿Qué combinación de anotaciones protege una llamada externa?
7. ¿Qué son los Dev Services?
8. ¿Qué cambia al compilar a nativo?
9. ¿Qué diferencia hay entre `@QuarkusTest` y `@QuarkusIntegrationTest`?
10. ¿Por qué reintentar en una sola capa?

## Respuestas
1. Escaneo, inyección y proxies se resuelven al compilar: arranque rápido y menos memoria.
2. En el event loop / en un hilo de trabajo.
3. Se detienen todas las peticiones que ese hilo atiende.
4. `runSubscriptionOn` al pool de trabajo, `@Blocking` o `@RunOnVirtualThread`.
5. Configuración tipada en interfaces.
6. `@Timeout`, `@Retry` acotado, `@CircuitBreaker` y `@Fallback`.
7. Dependencias (bases, brokers) levantadas solas en dev y test.
8. Arranque en milisegundos y menos memoria; la reflexión debe declararse.
9. El primero prueba dentro de la JVM de pruebas; el segundo, el artefacto empaquetado.
10. Para no multiplicar las llamadas (tormenta de reintentos).

## Ejercicios
1. Convierte `crear` a Hibernate Reactive Panache.
2. Agrega `@Bulkhead` a la pasarela y explica el valor elegido.
3. Escribe un `@QuarkusTest` del 404.
